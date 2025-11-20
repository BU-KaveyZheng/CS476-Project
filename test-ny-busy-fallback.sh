#!/bin/bash

# Test: NY Node Busy → Fallback to California
# Demonstrates resource-aware carbon scheduling

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Get carbon intensity for a node
get_node_carbon_intensity() {
    local node=$1
    local region=$(kubectl get node $node -o jsonpath='{.metadata.labels.carbon-region}' 2>/dev/null)
    
    if [ -z "$region" ]; then
        echo "N/A"
        return
    fi
    
    local carbon_api_pod=$(kubectl get pods -l app=carbon-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$carbon_api_pod" ]; then
        local cache_json=$(kubectl exec $carbon_api_pod -- cat /cache/carbon_cache.json 2>/dev/null)
        if [ -n "$cache_json" ]; then
            local intensity=$(echo "$cache_json" | python3 -c "import sys, json; data=json.load(sys.stdin); regions=data.get('regions', {}); print(regions.get('$region', {}).get('carbonIntensity', 'N/A'))" 2>/dev/null)
            if [ -n "$intensity" ] && [ "$intensity" != "N/A" ] && [ "$intensity" != "None" ]; then
                echo "$intensity"
                return
            fi
        fi
    fi
    echo "N/A"
}

# Cleanup function
cleanup() {
    print_info "Cleaning up test resources..."
    kubectl delete deployment test-ny-busy --ignore-not-found=true 2>/dev/null || true
    kubectl delete pod test-fallback-pod --ignore-not-found=true 2>/dev/null || true
    sleep 3
}

trap cleanup EXIT

print_header "NY Node Busy → California Fallback Test"

# Step 1: Identify nodes
print_info "Identifying nodes..."
NY_NODE=""
CAL_NODE=""

for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    region=$(kubectl get node $node -o jsonpath='{.metadata.labels.carbon-region}' 2>/dev/null)
    if [ "$region" = "US-NY-NYIS" ]; then
        NY_NODE=$node
    elif [ "$region" = "US-CAL-CISO" ]; then
        CAL_NODE=$node
    fi
done

if [ -z "$NY_NODE" ] || [ -z "$CAL_NODE" ]; then
    print_warning "Need both NY and California nodes!"
    echo "Current nodes:"
    kubectl get nodes -o custom-columns=NAME:.metadata.name,REGION:.metadata.labels.carbon-region
    exit 1
fi

NY_INTENSITY=$(get_node_carbon_intensity $NY_NODE)
CAL_INTENSITY=$(get_node_carbon_intensity $CAL_NODE)

print_success "Found nodes:"
echo "  NY Node: $NY_NODE ($NY_INTENSITY g CO2/kWh)"
echo "  CA Node: $CAL_NODE ($CAL_INTENSITY g CO2/kWh)"

# Step 2: Check NY node capacity
print_info "Checking NY node capacity..."
NY_CPU=$(kubectl get node $NY_NODE -o jsonpath='{.status.allocatable.cpu}' | sed 's/[^0-9.]//g')
NY_MEMORY=$(kubectl get node $NY_NODE -o jsonpath='{.status.allocatable.memory}' | sed 's/[^0-9]//g')

print_info "NY Node Capacity: $NY_CPU CPU, ${NY_MEMORY} bytes memory"

# Step 3: Fill NY node with pods
print_header "Step 1: Filling NY Node (Best Carbon Node)"

# Calculate how many pods we can fit (use 80% of CPU)
POD_CPU=1000  # 1 CPU per pod
POD_MEMORY=$((1024 * 1024 * 256))  # 256Mi per pod
MAX_PODS_CPU=$(echo "$NY_CPU * 0.8 / 1" | bc | cut -d. -f1)
MAX_PODS_MEM=$(echo "$NY_MEMORY * 0.8 / $POD_MEMORY" | bc | cut -d. -f1)
MAX_PODS=$((MAX_PODS_CPU < MAX_PODS_MEM ? MAX_PODS_CPU : MAX_PODS_MEM))
MAX_PODS=$((MAX_PODS > 5 ? 5 : MAX_PODS))  # Cap at 5 for testing

if [ "$MAX_PODS" -lt 1 ]; then
    MAX_PODS=2  # Minimum 2 pods
fi

print_info "Creating $MAX_PODS pods to fill NY node ($NY_NODE)..."

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-ny-busy
spec:
  replicas: $MAX_PODS
  selector:
    matchLabels:
      test: ny-busy
  template:
    metadata:
      labels:
        test: ny-busy
    spec:
      nodeSelector:
        kubernetes.io/hostname: ${NY_NODE}
      containers:
      - name: busy-container
        image: nginx:latest
        resources:
          requests:
            memory: "256Mi"
            cpu: "1000m"
          limits:
            memory: "256Mi"
            cpu: "1000m"
EOF

print_info "Waiting for busy pods to be scheduled..."
sleep 15

BUSY_COUNT=$(kubectl get pods -l test=ny-busy --field-selector spec.nodeName=$NY_NODE --no-headers 2>/dev/null | wc -l | tr -d ' ')
print_success "NY node now has $BUSY_COUNT busy pods"

# Show current resource usage
print_info "Current pod distribution:"
kubectl get pods --all-namespaces --field-selector spec.nodeName=$NY_NODE --no-headers 2>/dev/null | wc -l | xargs -I {} echo "  $NY_NODE: {} total pods"
kubectl get pods --all-namespaces --field-selector spec.nodeName=$CAL_NODE --no-headers 2>/dev/null | wc -l | xargs -I {} echo "  $CAL_NODE: {} total pods"

# Step 4: Try to schedule new pod (should go to California)
print_header "Step 2: Scheduling New Pod (Should Fallback to California)"

print_info "Creating a new pod with larger resource requests..."
print_info "This pod needs 2000m CPU and 512Mi memory"
print_info "NY node should be too full to fit this pod, so it should fallback to CA..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-fallback-pod
spec:
  schedulerName: custom-scheduler
  containers:
  - name: test-container
    image: nginx:latest
    resources:
      requests:
        memory: "512Mi"
        cpu: "2000m"
EOF

print_info "Waiting for pod to be scheduled..."
sleep 10

SCHEDULED_NODE=$(kubectl get pod test-fallback-pod -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "")
POD_STATUS=$(kubectl get pod test-fallback-pod -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

# Step 5: Results
print_header "Results"

if [ -n "$SCHEDULED_NODE" ] && [ "$SCHEDULED_NODE" != "" ]; then
    SCHEDULED_REGION=$(kubectl get node $SCHEDULED_NODE -o jsonpath='{.metadata.labels.carbon-region}' 2>/dev/null || echo "")
    SCHEDULED_INTENSITY=$(get_node_carbon_intensity $SCHEDULED_NODE)
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Scheduling Decision                       ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║                                                              ║"
    echo "║  Preferred Node (NY):                                       ║"
    printf "║    • Node: %-45s ║\n" "$NY_NODE"
    printf "║    • Region: %-43s ║\n" "US-NY-NYIS"
    printf "║    • Carbon: %-43s ║\n" "$NY_INTENSITY g CO2/kWh"
    printf "║    • Status: %-43s ║\n" "BUSY ($BUSY_COUNT pods)"
    echo "║                                                              ║"
    echo "║  Fallback Node (California):                                 ║"
    printf "║    • Node: %-45s ║\n" "$CAL_NODE"
    printf "║    • Region: %-43s ║\n" "US-CAL-CISO"
    printf "║    • Carbon: %-43s ║\n" "$CAL_INTENSITY g CO2/kWh"
    printf "║    • Status: %-43s ║\n" "Available"
    echo "║                                                              ║"
    echo "║  Pod Scheduled To:                                           ║"
    printf "║    • Node: %-45s ║\n" "$SCHEDULED_NODE"
    printf "║    • Region: %-43s ║\n" "$SCHEDULED_REGION"
    printf "║    • Carbon: %-43s ║\n" "$SCHEDULED_INTENSITY g CO2/kWh"
    echo "║                                                              ║"
    
    if [ "$SCHEDULED_NODE" = "$CAL_NODE" ]; then
        echo "║  ✅ CORRECT: Pod scheduled to California (fallback)      ║"
        echo "║     Scheduler correctly handled resource constraints      ║"
    elif [ "$SCHEDULED_NODE" = "$NY_NODE" ]; then
        echo "║  ⚠️  Pod scheduled to NY (may have had resources)         ║"
    else
        echo "║  ⚠️  Pod scheduled to unexpected node                     ║"
    fi
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Check scheduler logs
    print_info "Checking scheduler logs for decision-making..."
    kubectl logs -l app=custom-scheduler --tail=50 2>&1 | grep -A 5 "test-fallback-pod" | head -15 || true
    
else
    print_warning "Pod status: $POD_STATUS"
    if [ "$POD_STATUS" = "Pending" ]; then
        print_info "Pod is pending - checking why..."
        kubectl describe pod test-fallback-pod | grep -A 10 "Events:" || true
    fi
fi

print_header "Test Complete"

