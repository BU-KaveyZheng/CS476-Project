# Edge Case Testing Guide

This document describes the comprehensive edge case test script for validating carbon-aware scheduler behavior under various real-world scenarios.

## Overview

The `test-edge-cases.sh` script tests the carbon-aware scheduler's behavior in challenging scenarios that may occur in production environments.

## Prerequisites

1. **Kubernetes cluster** (minikube) with at least 2 nodes (recommended)
2. **Custom scheduler** deployed and running
3. **Carbon API** deployed and running
4. **Nodes labeled** with `carbon-region` labels
5. **bc command** installed (for calculations): `brew install bc` (macOS) or `apt-get install bc` (Linux)

## Usage

```bash
# Run all edge case scenarios
./test-edge-cases.sh

# Run specific scenario only
./test-edge-cases.sh --scenario 1

# Keep test resources for manual inspection
./test-edge-cases.sh --no-cleanup

# Show help
./test-edge-cases.sh --help
```

## Test Scenarios

### Scenario 1: Best Node is Full (Resource Constrained)

**Purpose**: Verify that the scheduler correctly handles the case when the lowest-carbon node is full and cannot accept more pods.

**What it does**:
1. Identifies the node with the lowest carbon intensity
2. Fills that node with pods (up to 80% capacity)
3. Attempts to schedule a new pod
4. Verifies the pod is scheduled to the next-best carbon node

**Expected Result**:
- New pod should be scheduled to the second-best carbon node
- Scheduler should gracefully handle resource constraints
- Carbon optimization should still be attempted on remaining nodes

**Key Test Points**:
- Resource constraint detection
- Fallback to alternative nodes
- Carbon optimization within available resources

---

### Scenario 2: All Nodes Busy (High Load)

**Purpose**: Test scheduler behavior when all nodes are under high load.

**What it does**:
1. Creates deployments to fill all nodes (70% capacity each)
2. Attempts to schedule a new pod
3. Verifies scheduling behavior under high load

**Expected Result**:
- Pod may be scheduled if any node has available resources
- Pod may remain pending if no resources are available
- Scheduler should still prefer lower-carbon nodes when possible

**Key Test Points**:
- Handling of resource exhaustion
- Graceful degradation under load
- Carbon awareness maintained when resources allow

---

### Scenario 3: Missing Carbon Region Labels

**Purpose**: Verify graceful fallback when nodes don't have `carbon-region` labels.

**What it does**:
1. Removes `carbon-region` labels from all nodes
2. Attempts to schedule a pod
3. Restores labels after testing

**Expected Result**:
- Pod should still be scheduled (fallback to default behavior)
- Scheduler should log warnings about missing labels
- Should use default high score (1000 g CO2/kWh) for unlabeled nodes

**Key Test Points**:
- Graceful degradation
- Error handling
- Fallback behavior

---

### Scenario 4: Stale/Missing Cache

**Purpose**: Test scheduler behavior when carbon cache is unavailable or stale.

**What it does**:
1. Checks cache status
2. Attempts to schedule a pod
3. Verifies fallback behavior

**Expected Result**:
- Pod should still be scheduled
- Scheduler should fall back to first available node
- Should log cache-related warnings

**Key Test Points**:
- Cache error handling
- Fallback mechanism
- System resilience

---

### Scenario 5: Large Resource Requests

**Purpose**: Verify scheduler handles pods with very large resource requirements.

**What it does**:
1. Displays node capacities
2. Creates a pod requesting large resources (8Gi memory, 4 CPU)
3. Verifies scheduling behavior

**Expected Result**:
- Pod may be scheduled if a node has sufficient resources
- Pod may remain pending if no node can accommodate it
- Demonstrates resource constraint handling

**Key Test Points**:
- Resource limit enforcement
- Large resource handling
- Pending pod behavior

---

### Scenario 6: Rapid Sequential Scheduling

**Purpose**: Test scheduler performance and consistency under rapid load.

**What it does**:
1. Creates 10 pods rapidly (one after another)
2. Waits for all to be scheduled
3. Analyzes distribution and carbon optimization

**Expected Result**:
- All pods should be scheduled
- Pods should prefer lower-carbon nodes
- Distribution should show carbon-aware pattern

**Key Test Points**:
- Performance under load
- Consistency of decisions
- Carbon optimization maintained

---

### Scenario 7: Mixed Workload Sizes

**Purpose**: Verify carbon-aware scheduling works correctly with varying workload sizes.

**What it does**:
1. Creates pods with different resource requirements:
   - Small: 64Mi memory, 100m CPU
   - Medium: 256Mi memory, 500m CPU
   - Large: 512Mi memory, 1000m CPU
2. Analyzes scheduling distribution

**Expected Result**:
- All workload sizes should prefer lower-carbon nodes
- Resource constraints respected
- Carbon optimization across all sizes

**Key Test Points**:
- Resource-aware carbon optimization
- Handling of mixed workloads
- Consistent carbon preference

## Interpreting Results

### ✅ Success Indicators

1. **Resource Constraints Handled**
   - Pods scheduled to alternative nodes when best node is full
   - No crashes or errors under high load

2. **Graceful Degradation**
   - Scheduler continues working when labels/cache missing
   - Fallback behavior is reasonable

3. **Carbon Optimization Maintained**
   - When resources allow, lower-carbon nodes preferred
   - Consistent behavior across scenarios

4. **Performance**
   - Rapid scheduling completes successfully
   - No significant delays or timeouts

### ⚠️ Common Issues

1. **Pods Stuck in Pending**
   - **Cause**: Insufficient resources on all nodes
   - **Solution**: Reduce resource requests or add more nodes

2. **All Pods Go to Same Node**
   - **Cause**: Only one node has available resources
   - **Solution**: Add more nodes or reduce existing load

3. **Cache Errors**
   - **Cause**: Carbon API pod not running or cache not accessible
   - **Solution**: Check carbon-api pod status and PVC mount

4. **Label Issues**
   - **Cause**: Labels not restored after test
   - **Solution**: Script should restore automatically, but verify with `kubectl get nodes --show-labels`

## Troubleshooting

### Check Node Resources
```bash
kubectl describe nodes
kubectl top nodes
```

### Check Pod Status
```bash
kubectl get pods -l test-type -o wide
kubectl describe pod <pod-name>
```

### Check Scheduler Logs
```bash
kubectl logs -l app=custom-scheduler --tail=100 | grep -E "(error|Error|ERROR|warning|Warning)"
```

### Check Carbon Cache
```bash
kubectl exec -it $(kubectl get pods -l app=carbon-api -o jsonpath='{.items[0].metadata.name}') -- cat /cache/carbon_cache.json
```

### Manual Cleanup
```bash
# Clean up all test resources
kubectl delete pods -l test-type
kubectl delete deployments -l test-type
kubectl delete pods ${TEST_PREFIX}-*

# Restore node labels
kubectl label node <node-name> carbon-region=US-CAL-CISO
kubectl label node <node-name> carbon-region=US-NY-NYIS
```

## Running Individual Scenarios

You can run specific scenarios to focus on particular edge cases:

```bash
# Test only resource constraints
./test-edge-cases.sh --scenario 1

# Test only high load
./test-edge-cases.sh --scenario 2

# Test only missing labels
./test-edge-cases.sh --scenario 3
```

## Expected Behaviors Summary

| Scenario | Expected Behavior |
|----------|------------------|
| Best Node Full | Schedule to next-best carbon node |
| All Nodes Busy | Schedule if resources available, else pending |
| Missing Labels | Fallback to default behavior, log warnings |
| Stale Cache | Fallback to first available node |
| Large Resources | Schedule if node has capacity, else pending |
| Rapid Scheduling | All scheduled, prefer lower-carbon nodes |
| Mixed Workloads | All sizes prefer lower-carbon nodes |

## Notes

- The script automatically cleans up test resources unless `--no-cleanup` is specified
- Some scenarios may take longer to complete (especially high-load scenarios)
- Resource calculations are approximate and may vary based on node capacity
- The script restores node labels after testing, but verify manually if needed
- Requires `bc` command for mathematical calculations

## Integration with Main Test Suite

This edge case script complements the main `test-scheduler-scenarios.sh` script:

- **Main script**: Tests normal operation and comparison scenarios
- **Edge case script**: Tests failure modes and challenging conditions

Run both scripts for comprehensive testing:
```bash
./test-scheduler-scenarios.sh
./test-edge-cases.sh
```

