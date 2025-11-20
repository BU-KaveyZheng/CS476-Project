#!/bin/bash

# Comprehensive Scheduler Test Script
# Tests carbon-aware vs non-carbon-aware scheduling scenarios

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="default"
SCHEDULER_NAME="custom-scheduler"
TEST_PREFIX="test-pod"
NUM_PODS=5
CLEANUP=true

# Helper functions
print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Cleanup function
cleanup() {
    if [ "$CLEANUP" = true ]; then
        print_info "Cleaning up test pods..."
        kubectl delete pods -l test-scenario --ignore-not-found=true 2>/dev/null || true
        kubectl delete pods ${TEST_PREFIX}-* --ignore-not-found=true 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    if ! kubectl cluster-info &>/dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    print_success "Connected to Kubernetes cluster"
    
    if ! kubectl get nodes &>/dev/null; then
        print_error "Cannot list nodes"
        exit 1
    fi
    print_success "Can list nodes"
    
    # Check if scheduler is running
    if ! kubectl get pods -l app=custom-scheduler &>/dev/null; then
        print_error "Custom scheduler pod not found"
        exit 1
    fi
    print_success "Custom scheduler is running"
    
    # Check if carbon-api is running
    if ! kubectl get pods -l app=carbon-api &>/dev/null; then
        print_error "Carbon API pod not found"
        exit 1
    fi
    print_success "Carbon API is running"
    
    # Get node information
    NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
    print_info "Available nodes: $NODES"
    
    # Show node labels
    print_info "Node carbon-region labels:"
    kubectl get nodes -o custom-columns=NAME:.metadata.name,REGION:.metadata.labels.carbon-region --no-headers
}

# Get carbon intensity for a node
get_node_carbon_intensity() {
    local node=$1
    local region=$(kubectl get node $node -o jsonpath='{.metadata.labels.carbon-region}' 2>/dev/null)
    
    if [ -z "$region" ]; then
        echo "N/A"
        return
    fi
    
    # Try to get from cache via carbon-api pod
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

# Scenario 1: Carbon-Aware Scheduling - Multiple Pods
test_carbon_aware_multiple_pods() {
    print_header "Scenario 1: Carbon-Aware Scheduling (Multiple Pods)"
    
    print_info "Creating $NUM_PODS pods with carbon-aware scheduler..."
    
    for i in $(seq 1 $NUM_PODS); do
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_PREFIX}-carbon-aware-${i}
  labels:
    test-scenario: carbon-aware
spec:
  schedulerName: ${SCHEDULER_NAME}
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
    local max_wait=30
    local waited=0
    while [ $waited -lt $max_wait ]; do
        local pending=$(kubectl get pods -l test-scenario=carbon-aware -o jsonpath='{.items[?(@.spec.nodeName=="")].metadata.name}' 2>/dev/null | wc -w)
        if [ "$pending" -eq 0 ]; then
            break
        fi
        sleep 2
        waited=$((waited + 2))
    done
    sleep 2  # Extra wait for node assignment to propagate
    
    # Show scheduling results
    print_info "Scheduling Results:"
    echo ""
    printf "%-40s %-20s %-15s %s\n" "POD NAME" "NODE" "REGION" "CARBON INTENSITY"
    echo "─────────────────────────────────────────────────────────────────────────────────────────"
    
    for pod in $(kubectl get pods -l test-scenario=carbon-aware -o jsonpath='{.items[*].metadata.name}'); do
        local node=$(kubectl get pod $pod -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "")
        if [ -z "$node" ]; then
            local status=$(kubectl get pod $pod -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            printf "%-40s %-20s %-15s %s\n" "$pod" "Pending" "$status" "N/A"
            continue
        fi
        local region=$(kubectl get node $node -o jsonpath='{.metadata.labels.carbon-region}' 2>/dev/null || echo "")
        local intensity=$(get_node_carbon_intensity $node)
        
        printf "%-40s %-20s %-15s %s g CO2/kWh\n" "$pod" "$node" "${region:-N/A}" "$intensity"
    done
    
    echo ""
    
    # Analyze distribution
    print_info "Node Distribution:"
    kubectl get pods -l test-scenario=carbon-aware -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | \
        sort | uniq -c | awk '{printf "  %s: %d pods\n", $2, $1}'
    
    # Check if all pods went to lowest carbon node
    local best_region=$(kubectl exec $(kubectl get pods -l app=carbon-api -o jsonpath='{.items[0].metadata.name}') -- \
        cat /cache/carbon_cache.json 2>/dev/null | \
        python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('best_region', 'N/A'))" 2>/dev/null)
    
    if [ "$best_region" != "N/A" ]; then
        print_info "Expected best region from cache: $best_region"
    fi
}

# Scenario 2: Non-Carbon-Aware Scheduling (Default Scheduler)
test_default_scheduler() {
    print_header "Scenario 2: Default Scheduler (Non-Carbon-Aware)"
    
    print_info "Creating $NUM_PODS pods with default Kubernetes scheduler..."
    
    for i in $(seq 1 $NUM_PODS); do
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_PREFIX}-default-${i}
  labels:
    test-scenario: default-scheduler
spec:
  schedulerName: default-scheduler
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
    local max_wait=30
    local waited=0
    while [ $waited -lt $max_wait ]; do
        local pending=$(kubectl get pods -l test-scenario=default-scheduler -o jsonpath='{.items[?(@.spec.nodeName=="")].metadata.name}' 2>/dev/null | wc -w)
        if [ "$pending" -eq 0 ]; then
            break
        fi
        sleep 2
        waited=$((waited + 2))
    done
    sleep 2  # Extra wait for node assignment to propagate
    
    # Show scheduling results
    print_info "Scheduling Results:"
    echo ""
    printf "%-40s %-20s %-15s %s\n" "POD NAME" "NODE" "REGION" "CARBON INTENSITY"
    echo "─────────────────────────────────────────────────────────────────────────────────────────"
    
    for pod in $(kubectl get pods -l test-scenario=default-scheduler -o jsonpath='{.items[*].metadata.name}'); do
        local node=$(kubectl get pod $pod -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "")
        if [ -z "$node" ]; then
            local status=$(kubectl get pod $pod -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            printf "%-40s %-20s %-15s %s\n" "$pod" "Pending" "$status" "N/A"
            continue
        fi
        local region=$(kubectl get node $node -o jsonpath='{.metadata.labels.carbon-region}' 2>/dev/null || echo "")
        local intensity=$(get_node_carbon_intensity $node)
        
        printf "%-40s %-20s %-15s %s g CO2/kWh\n" "$pod" "$node" "${region:-N/A}" "$intensity"
    done
    
    echo ""
    
    # Analyze distribution
    print_info "Node Distribution:"
    kubectl get pods -l test-scenario=default-scheduler -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | \
        sort | uniq -c | awk '{printf "  %s: %d pods\n", $2, $1}'
}

# Scenario 3: Carbon-Aware with Different Resource Requests
test_different_resources() {
    print_header "Scenario 3: Carbon-Aware with Different Resource Requests"
    
    print_info "Creating pods with varying resource requests..."
    
    # Small pod
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_PREFIX}-resources-small
  labels:
    test-scenario: resources
spec:
  schedulerName: ${SCHEDULER_NAME}
  containers:
  - name: test-container
    image: nginx:latest
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
EOF
    
    # Medium pod
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_PREFIX}-resources-medium
  labels:
    test-scenario: resources
spec:
  schedulerName: ${SCHEDULER_NAME}
  containers:
  - name: test-container
    image: nginx:latest
    resources:
      requests:
        memory: "256Mi"
        cpu: "500m"
EOF
    
    # Large pod
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_PREFIX}-resources-large
  labels:
    test-scenario: resources
spec:
  schedulerName: ${SCHEDULER_NAME}
  containers:
  - name: test-container
    image: nginx:latest
    resources:
      requests:
        memory: "512Mi"
        cpu: "1000m"
EOF
    
    print_info "Waiting for pods to be scheduled..."
    local max_wait=30
    local waited=0
    while [ $waited -lt $max_wait ]; do
        local pending=$(kubectl get pods -l test-scenario=resources -o jsonpath='{.items[?(@.spec.nodeName=="")].metadata.name}' 2>/dev/null | wc -w)
        if [ "$pending" -eq 0 ]; then
            break
        fi
        sleep 2
        waited=$((waited + 2))
    done
    sleep 2  # Extra wait for node assignment to propagate
    
    # Show scheduling results
    print_info "Scheduling Results:"
    echo ""
    printf "%-40s %-20s %-15s %-20s %s\n" "POD NAME" "NODE" "REGION" "RESOURCES" "CARBON INTENSITY"
    echo "────────────────────────────────────────────────────────────────────────────────────────────────────────────"
    
    for pod in $(kubectl get pods -l test-scenario=resources -o jsonpath='{.items[*].metadata.name}'); do
        local node=$(kubectl get pod $pod -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "")
        if [ -z "$node" ]; then
            local status=$(kubectl get pod $pod -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            printf "%-40s %-20s %-15s %-20s %s\n" "$pod" "Pending" "$status" "N/A" "N/A"
            continue
        fi
        local region=$(kubectl get node $node -o jsonpath='{.metadata.labels.carbon-region}' 2>/dev/null || echo "")
        local intensity=$(get_node_carbon_intensity $node)
        local cpu=$(kubectl get pod $pod -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "N/A")
        local memory=$(kubectl get pod $pod -o jsonpath='{.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "N/A")
        
        printf "%-40s %-20s %-15s %-20s %s g CO2/kWh\n" "$pod" "$node" "${region:-N/A}" "CPU:${cpu} Mem:${memory}" "$intensity"
    done
}

# Scenario 4: Comparison Summary
generate_comparison_summary() {
    print_header "Scenario 4: Comparison Summary"
    
    # Calculate average carbon intensity for each scenario
    print_info "Carbon Intensity Analysis:"
    echo ""
    
    # Carbon-aware pods
    local carbon_aware_total=0
    local carbon_aware_count=0
    for pod in $(kubectl get pods -l test-scenario=carbon-aware -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        local node=$(kubectl get pod $pod -o jsonpath='{.spec.nodeName}' 2>/dev/null)
        local intensity=$(get_node_carbon_intensity $node)
        if [ "$intensity" != "N/A" ]; then
            carbon_aware_total=$(echo "$carbon_aware_total + $intensity" | bc)
            carbon_aware_count=$((carbon_aware_count + 1))
        fi
    done
    
    # Default scheduler pods
    local default_total=0
    local default_count=0
    for pod in $(kubectl get pods -l test-scenario=default-scheduler -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        local node=$(kubectl get pod $pod -o jsonpath='{.spec.nodeName}' 2>/dev/null)
        local intensity=$(get_node_carbon_intensity $node)
        if [ "$intensity" != "N/A" ]; then
            default_total=$(echo "$default_total + $intensity" | bc)
            default_count=$((default_count + 1))
        fi
    done
    
    if [ $carbon_aware_count -gt 0 ]; then
        local carbon_aware_avg=$(echo "scale=2; $carbon_aware_total / $carbon_aware_count" | bc)
        printf "  Carbon-Aware Average: %.2f g CO2/kWh (%d pods)\n" "$carbon_aware_avg" "$carbon_aware_count"
    fi
    
    if [ $default_count -gt 0 ]; then
        local default_avg=$(echo "scale=2; $default_total / $default_count" | bc)
        printf "  Default Scheduler Average: %.2f g CO2/kWh (%d pods)\n" "$default_avg" "$default_count"
        
        if [ $carbon_aware_count -gt 0 ]; then
            local reduction=$(echo "scale=2; (($default_avg - $carbon_aware_avg) / $default_avg) * 100" | bc)
            printf "  Carbon Reduction: %.2f%%\n" "$reduction"
        fi
    fi
    
    echo ""
    print_info "Scheduler Logs (Recent Carbon-Aware Decisions):"
    kubectl logs -l app=custom-scheduler --tail=50 2>&1 | grep -E "(Carbon-aware decision|Node Scoring Summary)" | tail -10 || true
}

# Main execution
main() {
    print_header "Carbon-Aware Scheduler Test Suite"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-cleanup)
                CLEANUP=false
                shift
                ;;
            --pods)
                NUM_PODS="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [--no-cleanup] [--pods NUM]"
                echo ""
                echo "Options:"
                echo "  --no-cleanup    Don't clean up test pods after completion"
                echo "  --pods NUM      Number of pods to create per scenario (default: 5)"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    check_prerequisites
    
    # Run scenarios
    test_carbon_aware_multiple_pods
    sleep 3
    
    test_default_scheduler
    sleep 3
    
    test_different_resources
    sleep 3
    
    generate_comparison_summary
    
    print_header "Test Suite Complete"
    print_success "All scenarios executed successfully"
    
    if [ "$CLEANUP" = true ]; then
        print_info "Test pods will be cleaned up on exit"
    else
        print_info "Test pods preserved (--no-cleanup flag set)"
    fi
}

# Run main function
main "$@"

