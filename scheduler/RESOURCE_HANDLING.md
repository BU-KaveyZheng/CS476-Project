# Resource Request Handling

## Overview

The scheduler **does NOT assume uniform resource requests**. Each pod's resource requirements are calculated individually, and nodes are checked individually for each pod.

## How It Works

### 1. Per-Pod Resource Calculation

For each pod, we calculate its total resource requests:

```go
func getPodResourceRequests(pod *corev1.Pod) (cpu, memory resource.Quantity) {
    // Sums resource requests from ALL containers in the pod
    for _, container := range pod.Spec.Containers {
        if req := container.Resources.Requests; req != nil {
            cpu.Add(cpuReq)      // Adds each container's CPU request
            memory.Add(memReq)   // Adds each container's memory request
        }
    }
    return cpu, memory
}
```

**Key Points:**
- ✅ Handles pods with **multiple containers** (sums all containers)
- ✅ Handles pods with **no resource requests** (returns zero)
- ✅ Handles pods with **different resource requirements** (each pod calculated separately)

### 2. Per-Node Resource Tracking

For each node, we calculate currently allocated resources:

```go
func getNodeAllocatedResources(nodeName string, clientset *kubernetes.Clientset) {
    // Gets ALL pods on this node
    pods, err := clientset.CoreV1().Pods("").List(..., 
        FieldSelector: "spec.nodeName=" + nodeName)
    
    // Sums resource requests from ALL pods on the node
    for _, pod := range pods.Items {
        for _, container := range pod.Spec.Containers {
            cpu.Add(cpuReq)      // Adds each pod's CPU request
            memory.Add(memReq)   // Adds each pod's memory request
        }
    }
}
```

**Key Points:**
- ✅ Tracks **all pods** on the node (not just uniform pods)
- ✅ Sums **actual resource requests** (not assumed values)
- ✅ Skips pods being deleted (accurate current state)

### 3. Per-Pod Availability Check

For each pod, we check each node individually:

```go
func nodeHasResources(node *corev1.Node, pod *corev1.Pod, clientset *kubernetes.Clientset) bool {
    // Get THIS pod's resource requests
    podCPU, podMemory := getPodResourceRequests(pod)
    
    // Get THIS node's available resources
    availableCPU = nodeCPU - allocatedCPU
    availableMemory = nodeMemory - allocatedMemory
    
    // Check if THIS node can fit THIS pod
    return availableCPU >= podCPU && availableMemory >= podMemory
}
```

**Key Points:**
- ✅ Each pod-node pair checked individually
- ✅ Different pods have different requirements
- ✅ Different nodes have different availability

## Examples

### Example 1: Different Pod Sizes

**Scenario:**
- Pod A: requests CPU=0.5, Memory=512Mi
- Pod B: requests CPU=2.0, Memory=2Gi
- Node: has 4 CPU, 8Gi Memory available

**What Happens:**
1. Pod A arrives:
   - Checks: Node has 4 CPU, 8Gi → ✅ Can fit (needs 0.5 CPU, 512Mi)
   - Schedules to greenest node that can fit

2. Pod B arrives:
   - Checks: Node has 3.5 CPU, 7.5Gi available (after Pod A) → ✅ Can fit (needs 2.0 CPU, 2Gi)
   - Schedules to greenest node that can fit

**Result:** ✅ Both pods scheduled correctly with different requirements

### Example 2: Resource Filtering

**Scenario:**
- Pod: requests CPU=4.0, Memory=8Gi
- Node A: 2 CPU available, Carbon: 357 g CO2/kWh (lowest)
- Node B: 6 CPU available, Carbon: 436 g CO2/kWh

**What Happens:**
1. Check Node A: available=2 CPU, needs=4 CPU → ❌ Filtered out
2. Check Node B: available=6 CPU, needs=4 CPU → ✅ Can fit
3. Select Node B (lowest carbon among nodes that can fit)

**Result:** ✅ Correctly filters out Node A, selects Node B

### Example 3: No Resource Requests

**Scenario:**
- Pod: no resource requests specified
- Node: any node

**What Happens:**
```go
if podCPU.IsZero() && podMemory.IsZero() {
    return true  // Assume it fits
}
```

**Result:** ✅ Pod can be scheduled to any node (Kubernetes default behavior)

## What We Use: Requests vs Limits

### Resource Requests (What We Check)

- **Requests**: Minimum resources guaranteed to the pod
- **Used for**: Scheduling decisions (what we check)
- **Example**: `requests: {cpu: "1", memory: "512Mi"}`

### Resource Limits (What We Don't Check)

- **Limits**: Maximum resources pod can use
- **Used for**: Resource enforcement (not scheduling)
- **Example**: `limits: {cpu: "2", memory: "1Gi"}`

**Why:** Kubernetes uses **requests** for scheduling, **limits** for enforcement. We follow this pattern.

## Current Limitations

### ✅ What We Handle Correctly

1. **Variable pod sizes** - Each pod's requests calculated individually
2. **Multiple containers** - Sums all containers in a pod
3. **Dynamic node capacity** - Calculates available resources per node
4. **No resource requests** - Handles gracefully (assumes fits)

### ⚠️ What We Don't Handle Yet

1. **Resource Limits** - We don't check limits (only requests)
2. **Ephemeral Storage** - Only checks CPU and memory
3. **GPU/Extended Resources** - Not checked
4. **Init Containers** - Not included in resource calculation
5. **Overhead** - Doesn't account for node overhead

## Code Flow

```
Pod arrives
    ↓
Calculate pod's resource requests (sum all containers)
    ↓
For each node:
    ↓
    Calculate node's allocated resources (sum all pods)
    ↓
    Calculate available = allocatable - allocated
    ↓
    Check: available >= pod requests?
    ↓
    If YES → Add to available nodes
    If NO  → Filter out
    ↓
Apply carbon-aware scoring to available nodes
    ↓
Select node with lowest carbon intensity
```

## Verification

To verify resource handling works correctly:

```bash
# Create pods with different resource requests
kubectl run small-pod --image=nginx --restart=Never \
  --overrides='{"spec":{"schedulerName":"custom-scheduler","containers":[{"name":"test","image":"nginx","resources":{"requests":{"cpu":"100m","memory":"64Mi"}}}]}}'

kubectl run large-pod --image=nginx --restart=Never \
  --overrides='{"spec":{"schedulerName":"custom-scheduler","containers":[{"name":"test","image":"nginx","resources":{"requests":{"cpu":"2","memory":"4Gi"}}}]}}'

# Check scheduler logs
kubectl logs deployment/custom-scheduler | grep -A 5 "Pod resource requests"
```

**Expected Output:**
```
Pod resource requests: CPU=100m Memory=64Mi  (small-pod)
Pod resource requests: CPU=2 Memory=4Gi      (large-pod)
```

## Summary

- ✅ **No uniform assumption** - Each pod's resources calculated individually
- ✅ **Variable requests** - Handles pods with different CPU/memory requirements
- ✅ **Dynamic tracking** - Tracks actual allocated resources per node
- ✅ **Per-pod filtering** - Checks each pod against each node individually
- ✅ **Carbon-aware selection** - Selects greenest node among those that can fit

The scheduler correctly handles heterogeneous workloads with varying resource requirements.

