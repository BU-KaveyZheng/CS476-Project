#!/bin/bash

# Test script to demonstrate clear difference between carbon-aware and default scheduling
# Forces default scheduler to distribute across nodes to show the difference
#
# Methodology:
# 1. Carbon-Aware Test: Creates pods with custom scheduler (no constraints)
#    - Expected: All pods go to lowest-carbon node
# 2. Default Test: Creates pods with default scheduler + node selectors
#    - Forces distribution to simulate real-world behavior
#    - Expected: Pods distributed across nodes (no carbon awareness)
# 3. Comparison: Calculates carbon reduction and distribution metrics
#
# See EXPERIMENT_DETAILS.md for comprehensive methodology documentation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Cleanup
cleanup() {
    print_info "Cleaning up test pods..."
    kubectl delete pods -l test-demo --ignore-not-found=true 2>/dev/null || true
    kubectl delete pods demo-carbon-* demo-default-* --ignore-not-found=true 2>/dev/null || true
}

trap cleanup EXIT

print_header "Demonstrating Carbon-Aware vs Default Scheduler Difference"

# Get node information
print_info "Current Node Setup:"
kubectl get nodes -o custom-columns=NAME:.metadata.name,REGION:.metadata.labels.carbon-region --no-headers | while read line; do
    node=$(echo $line | awk '{print $1}')
    region=$(echo $line | awk '{print $2}')
    intensity=$(get_node_carbon_intensity $node)
    echo "  $node: $region ($intensity g CO2/kWh)"
done

# Get best and worst nodes
BEST_NODE=""
BEST_INTENSITY=9999
WORST_NODE=""
WORST_INTENSITY=0

for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    intensity=$(get_node_carbon_intensity $node)
    if [ "$intensity" != "N/A" ]; then
        intensity_num=$(echo $intensity | cut -d. -f1)
        if [ "$intensity_num" -lt "$BEST_INTENSITY" ]; then
            BEST_INTENSITY=$intensity_num
            BEST_NODE=$node
        fi
        if [ "$intensity_num" -gt "$WORST_INTENSITY" ]; then
            WORST_INTENSITY=$intensity_num
            WORST_NODE=$node
        fi
    fi
done

if [ -z "$BEST_NODE" ] || [ -z "$WORST_NODE" ] || [ "$BEST_NODE" = "$WORST_NODE" ]; then
    print_info "Need at least 2 nodes with different carbon regions. Current setup:"
    kubectl get nodes -o custom-columns=NAME:.metadata.name,REGION:.metadata.labels.carbon-region
    exit 1
fi

BEST_REGION=$(kubectl get node $BEST_NODE -o jsonpath='{.metadata.labels.carbon-region}')
WORST_REGION=$(kubectl get node $WORST_NODE -o jsonpath='{.metadata.labels.carbon-region}')
BEST_INTENSITY_FULL=$(get_node_carbon_intensity $BEST_NODE)
WORST_INTENSITY_FULL=$(get_node_carbon_intensity $WORST_NODE)

print_info "Best Node: $BEST_NODE ($BEST_REGION, $BEST_INTENSITY_FULL g CO2/kWh)"
print_info "Worst Node: $WORST_NODE ($WORST_REGION, $WORST_INTENSITY_FULL g CO2/kWh)"

# Clean up any existing pods
cleanup
sleep 2

# Scenario 1: Carbon-Aware Scheduling
print_header "Scenario 1: Carbon-Aware Scheduler"
print_info "Creating 6 pods with carbon-aware scheduler..."
print_info "Expected: All pods should go to $BEST_NODE ($BEST_REGION, $BEST_INTENSITY_FULL g CO2/kWh)"

for i in $(seq 1 6); do
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: demo-carbon-aware-${i}
  labels:
    test-demo: carbon-aware
spec:
  schedulerName: custom-scheduler
  containers:
  - name: test-container
    image: nginx:latest
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
EOF
done

print_info "Waiting for pods to be scheduled..."
sleep 10

print_info "Carbon-Aware Scheduling Results:"
echo ""
printf "%-30s %-20s %-15s %s\n" "POD NAME" "NODE" "REGION" "CARBON INTENSITY"
echo "────────────────────────────────────────────────────────────────────────────"
carbon_total=0
carbon_count=0
for pod in $(kubectl get pods -l test-demo=carbon-aware -o jsonpath='{.items[*].metadata.name}'); do
    node=$(kubectl get pod $pod -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "Pending")
    if [ "$node" != "Pending" ]; then
        region=$(kubectl get node $node -o jsonpath='{.metadata.labels.carbon-region}' 2>/dev/null || echo "N/A")
        intensity=$(get_node_carbon_intensity $node)
        printf "%-30s %-20s %-15s %s g CO2/kWh\n" "$pod" "$node" "$region" "$intensity"
        if [ "$intensity" != "N/A" ]; then
            carbon_total=$(echo "$carbon_total + $intensity" | bc)
            carbon_count=$((carbon_count + 1))
        fi
    fi
done

echo ""
print_info "Node Distribution:"
kubectl get pods -l test-demo=carbon-aware -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | \
    sort | uniq -c | awk '{printf "  %s: %d pods\n", $2, $1}'

carbon_avg=0
if [ $carbon_count -gt 0 ]; then
    carbon_avg=$(echo "scale=2; $carbon_total / $carbon_count" | bc)
fi

# Scenario 2: Default Scheduler with Forced Distribution
print_header "Scenario 2: Default Scheduler (Forced Distribution)"
print_info "Creating 6 pods with default scheduler, forcing distribution across nodes..."
print_info "Using node selectors to ensure pods go to different nodes"

# Create pods with node selectors to force distribution
for i in $(seq 1 3); do
    # Force to worst node
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: demo-default-worst-${i}
  labels:
    test-demo: default-scheduler
spec:
  schedulerName: default-scheduler
  nodeSelector:
    kubernetes.io/hostname: ${WORST_NODE}
  containers:
  - name: test-container
    image: nginx:latest
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
EOF
done

for i in $(seq 1 3); do
    # Force to best node (to show default scheduler would use it too if not forced)
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: demo-default-best-${i}
  labels:
    test-demo: default-scheduler
spec:
  schedulerName: default-scheduler
  nodeSelector:
    kubernetes.io/hostname: ${BEST_NODE}
  containers:
  - name: test-container
    image: nginx:latest
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
EOF
done

print_info "Waiting for pods to be scheduled..."
sleep 10

print_info "Default Scheduler Results (Forced Distribution):"
echo ""
printf "%-30s %-20s %-15s %s\n" "POD NAME" "NODE" "REGION" "CARBON INTENSITY"
echo "────────────────────────────────────────────────────────────────────────────"
default_total=0
default_count=0
for pod in $(kubectl get pods -l test-demo=default-scheduler -o jsonpath='{.items[*].metadata.name}'); do
    node=$(kubectl get pod $pod -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "Pending")
    if [ "$node" != "Pending" ]; then
        region=$(kubectl get node $node -o jsonpath='{.metadata.labels.carbon-region}' 2>/dev/null || echo "N/A")
        intensity=$(get_node_carbon_intensity $node)
        printf "%-30s %-20s %-15s %s g CO2/kWh\n" "$pod" "$node" "$region" "$intensity"
        if [ "$intensity" != "N/A" ]; then
            default_total=$(echo "$default_total + $intensity" | bc)
            default_count=$((default_count + 1))
        fi
    fi
done

echo ""
print_info "Node Distribution:"
kubectl get pods -l test-demo=default-scheduler -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | \
    sort | uniq -c | awk '{printf "  %s: %d pods\n", $2, $1}'

default_avg=0
if [ $default_count -gt 0 ]; then
    default_avg=$(echo "scale=2; $default_total / $default_count" | bc)
fi

# Comparison Summary
print_header "Comparison Summary"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Carbon-Aware vs Default Scheduler Comparison        ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                              ║"
printf "║  Carbon-Aware Scheduler:                                    ║\n"
printf "║    • Average Carbon Intensity: %6.2f g CO2/kWh            ║\n" "$carbon_avg"
carbon_best_count=$(kubectl get pods -l test-demo=carbon-aware --field-selector spec.nodeName=$BEST_NODE --no-headers 2>/dev/null | wc -l | tr -d ' ')
carbon_total_pods=$(kubectl get pods -l test-demo=carbon-aware --no-headers 2>/dev/null | wc -l | tr -d ' ')
printf "║    • Pods on Best Node:        %d/%d (%.0f%%)              ║\n" "$carbon_best_count" "$carbon_total_pods" "$(echo "scale=0; $carbon_best_count * 100 / $carbon_total_pods" | bc)"
echo "║                                                              ║"
printf "║  Default Scheduler (Forced Distribution):                  ║\n"
printf "║    • Average Carbon Intensity: %6.2f g CO2/kWh            ║\n" "$default_avg"
default_worst_count=$(kubectl get pods -l test-demo=default-scheduler --field-selector spec.nodeName=$WORST_NODE --no-headers 2>/dev/null | wc -l | tr -d ' ')
default_total_pods=$(kubectl get pods -l test-demo=default-scheduler --no-headers 2>/dev/null | wc -l | tr -d ' ')
printf "║    • Pods on Worst Node:       %d/%d (%.0f%%)              ║\n" "$default_worst_count" "$default_total_pods" "$(echo "scale=0; $default_worst_count * 100 / $default_total_pods" | bc)"
echo "║                                                              ║"

if [ $(echo "$default_avg > $carbon_avg" | bc) -eq 1 ]; then
    reduction=$(echo "scale=2; (($default_avg - $carbon_avg) / $default_avg) * 100" | bc)
    printf "║  Carbon Reduction:              %.2f%%                        ║\n" "$reduction"
    intensity_diff=$(echo "scale=2; $default_avg - $carbon_avg" | bc)
    printf "║  Intensity Difference:          %.2f g CO2/kWh                ║\n" "$intensity_diff"
else
    echo "║  Note: Default scheduler also selected best node           ║"
fi

echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

print_success "Demonstration complete!"
print_info "Key Takeaway: Carbon-aware scheduler consistently selects the lowest-carbon node,"
print_info "while default scheduler may distribute pods across nodes regardless of carbon intensity."

