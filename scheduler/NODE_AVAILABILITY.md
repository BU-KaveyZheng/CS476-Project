# Node Availability Checks

## Current Implementation

The scheduler currently checks **basic availability** only:

### ✅ What We Check

1. **Node Readiness** (lines 204-214)
   ```go
   // Checks if node.Status.Conditions has NodeReady = True
   ```
   - Ensures node is healthy and ready to accept pods

2. **Node Taints** (lines 216-223)
   ```go
   // Skips nodes with NoSchedule taints
   ```
   - Respects node taints that prevent scheduling

### ❌ What We DON'T Check (Missing)

1. **Resource Availability** ⚠️
   - CPU availability
   - Memory availability
   - Storage availability
   - Pod resource requests vs node capacity

2. **Pod Constraints** ⚠️
   - Node selectors (`nodeSelector`)
   - Node affinity/anti-affinity rules
   - Pod tolerations (only checks taints, not tolerations)

3. **Pod Requirements** ⚠️
   - Required node labels
   - Required node annotations
   - Pod security policies

## How to Check What's Available

### Current Method

```go
// 1. List all nodes
nodes, err := clientset.CoreV1().Nodes().List(context.Background(), metav1.ListOptions{})

// 2. Filter by readiness
if node.Status.Conditions[NodeReady] == True

// 3. Filter by taints
if node.Spec.Taints has NoSchedule → skip
```

### What Kubernetes Default Scheduler Checks

The default Kubernetes scheduler performs **predicates** (filters) and **priorities** (scoring):

**Predicates (Filters):**
- ✅ Node ready
- ✅ Taints/tolerations match
- ✅ **PodFitsResources** (CPU/memory)
- ✅ **PodFitsHostPorts**
- ✅ **HostName** (if specified)
- ✅ **MatchNodeSelector**
- ✅ **MatchInterPodAffinity**

**Priorities (Scoring):**
- **LeastRequestedPriority** (prefer nodes with fewer requested resources)
- **BalancedResourceAllocation** (balance CPU and memory usage)
- **NodePreferAvoidPodsPriority**
- **NodeAffinityPriority**

## Example: What Happens Now

**Scenario:**
- Node A: Ready, 0.1 CPU available, Carbon: 357 g CO2/kWh
- Node B: Ready, 2.0 CPU available, Carbon: 436 g CO2/kWh
- Pod requests: 1.0 CPU

**Current Behavior:**
- ✅ Selects Node A (lowest carbon)
- ❌ **Problem**: Node A doesn't have enough CPU!
- ❌ Pod will fail to start or be evicted

**What Should Happen:**
- ❌ Filter out Node A (insufficient resources)
- ✅ Select Node B (has resources + lowest carbon among available)

## How to Check Resource Availability

### Method 1: Check Node Allocatable Resources

```go
node.Status.Allocatable["cpu"]    // Total allocatable CPU
node.Status.Allocatable["memory"] // Total allocatable memory

// Need to subtract currently allocated resources
```

### Method 2: List Pods on Node

```go
pods, err := clientset.CoreV1().Pods("").List(context.Background(), metav1.ListOptions{
    FieldSelector: "spec.nodeName=" + node.Name,
})
// Sum up resource requests from all pods
```

### Method 3: Use Kubernetes Scheduler Framework

The proper way would be to use Kubernetes Scheduler Framework plugins:
- `NodeResourcesFit` plugin
- `NodeAffinity` plugin
- etc.

## Recommended Enhancement

Add resource checking:

```go
func nodeHasResources(node corev1.Node, pod corev1.Pod) bool {
    // Get pod resource requests
    cpuRequest := pod.Spec.Containers[0].Resources.Requests["cpu"]
    memRequest := pod.Spec.Containers[0].Resources.Requests["memory"]
    
    // Get node allocatable
    cpuAllocatable := node.Status.Allocatable["cpu"]
    memAllocatable := node.Status.Allocatable["memory"]
    
    // Get currently allocated (sum of all pods on node)
    // ... (complex calculation)
    
    // Check if node has enough resources
    return (cpuAllocatable - cpuAllocated) >= cpuRequest &&
           (memAllocatable - memAllocated) >= memRequest
}
```

## Quick Check Commands

**See node resources:**
```bash
kubectl describe nodes
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, cpu: .status.allocatable.cpu, memory: .status.allocatable.memory}'
```

**See pod resource requests:**
```bash
kubectl describe pod <pod-name>
kubectl get pod <pod-name> -o json | jq '.spec.containers[].resources'
```

**See what pods are on a node:**
```bash
kubectl get pods --all-namespaces --field-selector spec.nodeName=<node-name>
```

