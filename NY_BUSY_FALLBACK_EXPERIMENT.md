# NY Node Busy → California Fallback Experiment

## Overview

This experiment demonstrates how the carbon-aware scheduler handles resource constraints when the preferred (lowest-carbon) node is full and cannot accept more pods.

## Experiment Objectives

1. **Demonstrate Resource-Aware Carbon Scheduling**: Show that the scheduler respects resource constraints before applying carbon optimization
2. **Verify Fallback Behavior**: Prove that when the best carbon node is full, the scheduler correctly falls back to alternative nodes
3. **Show Carbon Optimization Among Available Nodes**: Verify that even when falling back, the scheduler still optimizes for carbon among nodes that have resources

## Experimental Setup

### Infrastructure Requirements

- **2 Nodes Required**:
  - **NY Node** (`minikube-m02`): Labeled `carbon-region=US-NY-NYIS`
    - Carbon Intensity: ~334-338 g CO2/kWh (lower carbon - preferred)
  - **California Node** (`minikube`): Labeled `carbon-region=US-CAL-CISO`
    - Carbon Intensity: ~360-367 g CO2/kWh (higher carbon - fallback)

- **Components**:
  - Custom carbon-aware scheduler deployed and running
  - Carbon API poller fetching real-time carbon intensity data
  - Both nodes must be healthy and schedulable

### Node Configuration

```
Node: minikube-m02 (NY)
  Label: carbon-region=US-NY-NYIS
  Carbon Intensity: 338 g CO2/kWh (BEST - lowest carbon)
  Capacity: 8 CPU, ~4GB memory
  Status: Will be filled with busy pods

Node: minikube (California)
  Label: carbon-region=US-CAL-CISO
  Carbon Intensity: 360 g CO2/kWh (FALLBACK - higher carbon)
  Capacity: 8 CPU, ~4GB memory
  Status: Available for fallback
```

## Experimental Methodology

### Phase 1: Fill NY Node (Best Carbon Node)

**Objective**: Consume resources on the NY node to make it unavailable for new pods.

**Procedure**:
1. Calculate NY node capacity (CPU and memory)
2. Create a deployment with pods that consume ~80-90% of NY node's resources
3. Use node selector to force pods to NY node
4. Wait for all pods to be scheduled
5. Verify NY node is now resource-constrained

**Example**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-ny-busy
spec:
  replicas: 6  # Calculated to fill ~80% of node capacity
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: minikube-m02  # Force to NY
      containers:
      - name: busy-container
        image: nginx:latest
        resources:
          requests:
            memory: "256Mi"
            cpu: "1000m"  # 1 CPU per pod
```

**Expected Result**:
- 6 pods scheduled to NY node
- NY node now has ~6 CPU allocated (out of 8 available)
- ~2 CPU remaining (not enough for large pods)

### Phase 2: Attempt to Schedule Large Pod

**Objective**: Try to schedule a pod that requires more resources than NY node has available.

**Procedure**:
1. Create a pod with large resource requests:
   - CPU: 2000m (2 CPU)
   - Memory: 512Mi
2. Use custom carbon-aware scheduler
3. Wait for scheduling decision
4. Observe which node the pod is scheduled to

**Example**:
```yaml
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
        cpu: "2000m"  # 2 CPU - too large for NY node!
```

**Expected Behavior**:
```
Scheduler Decision Process:
  1. Check NY node (minikube-m02):
     - Available CPU: ~700m (only 2 CPU left)
     - Pod needs: 2000m CPU
     - 700m >= 2000m? NO ❌
     - Result: Filtered out (insufficient resources)
  
  2. Check California node (minikube):
     - Available CPU: ~8 CPU (plenty available)
     - Pod needs: 2000m CPU
     - 8000m >= 2000m? YES ✅
     - Result: Available (has resources)
  
  3. Carbon Scoring:
     - Only California node available
     - Carbon: 360 g CO2/kWh
     - Result: Selected (only option)
```

**Expected Result**:
- Pod scheduled to California node (minikube)
- Scheduler logs show: "insufficient resources" for NY node
- Scheduler logs show: "available" for California node

### Phase 3: Verify Scheduler Logs

**Check scheduler decision-making**:
```bash
kubectl logs -l app=custom-scheduler --tail=50 | grep test-fallback-pod
```

**Expected Log Output**:
```
Unscheduled pod detected: default/test-fallback-pod
Pod resource requests: CPU=2 Memory=512Mi
Node minikube: available (passed all checks)
Node minikube-m02: insufficient resources 
  (CPU: 700m/8 available, Pod needs: CPU=2)
Carbon cache loaded: 5 regions, best: US-NY-NYIS
✅ Carbon-aware decision: minikube (region=US-CAL-CISO, Carbon Intensity=360.00 g CO2/kWh)
✅ Pod test-fallback-pod scheduled to minikube
```

## Detailed Results Interpretation

### Success Criteria

✅ **Resource Constraint Detection**:
- Scheduler correctly identifies NY node has insufficient resources
- Logs show: "insufficient resources" message
- NY node is filtered out before carbon scoring

✅ **Fallback to Alternative Node**:
- Pod scheduled to California node (alternative)
- California node has sufficient resources
- Pod successfully runs on fallback node

✅ **Carbon Optimization Maintained**:
- Among available nodes, scheduler still considers carbon
- If multiple nodes had resources, would select lowest-carbon
- In this case, only one node available, so it's selected

### Example Results

```
╔══════════════════════════════════════════════════════════════╗
║                    Scheduling Decision                       ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  Preferred Node (NY):                                       ║
║    • Node: minikube-m02                                     ║
║    • Region: US-NY-NYIS                                     ║
║    • Carbon: 338 g CO2/kWh                                  ║
║    • Status: BUSY (6 pods, insufficient resources)          ║
║                                                              ║
║  Fallback Node (California):                                 ║
║    • Node: minikube                                         ║
║    • Region: US-CAL-CISO                                    ║
║    • Carbon: 360 g CO2/kWh                                  ║
║    • Status: Available (has resources)                      ║
║                                                              ║
║  Pod Scheduled To:                                           ║
║    • Node: minikube (California)                             ║
║    • Region: US-CAL-CISO                                    ║
║    • Carbon: 360 g CO2/kWh                                  ║
║                                                              ║
║  ✅ CORRECT: Pod scheduled to California (fallback)         ║
║     Scheduler correctly handled resource constraints        ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

## Why This Experiment Matters

### Real-World Scenario

In production, this scenario happens frequently:

1. **Best carbon node gets busy**: 
   - Multiple workloads deployed to lowest-carbon region
   - Node resources get consumed
   - New pods need scheduling

2. **Resource constraints override carbon preference**:
   - Scheduler must respect resource limits
   - Cannot schedule pods to nodes without resources
   - Must fall back to alternative nodes

3. **Carbon optimization still applies**:
   - Among nodes with available resources
   - Scheduler selects lowest-carbon option
   - Maintains carbon awareness when possible

### Key Insights

1. **Resource Constraints Come First**:
   - Scheduler checks resources BEFORE carbon scoring
   - Cannot optimize carbon if node can't fit pod
   - Resource availability is a hard requirement

2. **Graceful Degradation**:
   - System doesn't fail when best node is full
   - Falls back to alternative nodes
   - Continues operating (just with higher carbon)

3. **Carbon Optimization Among Available**:
   - When multiple nodes have resources
   - Scheduler selects lowest-carbon among them
   - Still optimizes when possible

## Scheduler Decision Flow

```
Pod Created
    ↓
Scheduler Detects Unscheduled Pod
    ↓
Filter Nodes:
    ├─ Node Ready? ✅
    ├─ No Taints? ✅
    └─ Has Resources? ⚠️ CHECK THIS FIRST
         │
         ├─ NY Node: Has 700m CPU available
         │   Pod needs: 2000m CPU
         │   700m >= 2000m? NO ❌
         │   → FILTERED OUT
         │
         └─ CA Node: Has 8000m CPU available
             Pod needs: 2000m CPU
             8000m >= 2000m? YES ✅
             → AVAILABLE
    ↓
Carbon Scoring (on available nodes only):
    └─ Only CA node available
       → Selected (only option)
    ↓
Schedule Pod to California Node ✅
```

## Comparison: With vs Without Resource Constraints

### Scenario A: Both Nodes Have Resources

```
NY Node: Available (334 g CO2/kWh)
CA Node: Available (360 g CO2/kWh)

Scheduler Decision:
  ✅ Both nodes pass resource check
  ✅ Carbon scoring: NY wins (334 < 360)
  ✅ Pod scheduled to NY node
  
Result: Optimal carbon choice ✅
```

### Scenario B: NY Node Full (This Experiment)

```
NY Node: Full (334 g CO2/kWh) ❌ Filtered out
CA Node: Available (360 g CO2/kWh)

Scheduler Decision:
  ❌ NY node filtered out (no resources)
  ✅ CA node passes resource check
  ✅ Only CA node available
  ✅ Pod scheduled to CA node
  
Result: Fallback to alternative node ✅
Carbon: Higher than optimal, but necessary
```

## Edge Cases Tested

### Edge Case 1: NY Node Almost Full

**Scenario**: NY node has just enough resources for small pod

**Expected**: Small pod scheduled to NY (optimal carbon)

**Test**: Create pod with small resource requests (100m CPU)

### Edge Case 2: NY Node Completely Full

**Scenario**: NY node has zero available resources

**Expected**: Any new pod scheduled to California

**Test**: Fill NY node to 100% capacity

### Edge Case 3: Both Nodes Full

**Scenario**: Both nodes have insufficient resources

**Expected**: Pod remains in Pending state

**Test**: Fill both nodes, then try to schedule large pod

## Metrics and Observations

### Resource Utilization

**Before Filling NY Node**:
- NY Node: ~0-20% CPU allocated
- CA Node: ~0-20% CPU allocated

**After Filling NY Node**:
- NY Node: ~75-90% CPU allocated (busy)
- CA Node: ~0-20% CPU allocated (available)

**After Scheduling Fallback Pod**:
- NY Node: ~75-90% CPU allocated (unchanged)
- CA Node: ~25-30% CPU allocated (fallback pod added)

### Carbon Impact

**Ideal Scenario** (if NY had resources):
- Pod on NY: 338 g CO2/kWh
- Carbon savings: Optimal

**Actual Scenario** (NY full, fallback to CA):
- Pod on CA: 360 g CO2/kWh
- Carbon difference: +22 g CO2/kWh (6.5% higher)
- **Trade-off**: Necessary due to resource constraints

### Scheduler Performance

- **Decision Time**: < 1 second
- **Resource Check**: Accurate (correctly identifies insufficient resources)
- **Fallback**: Successful (schedules to alternative node)
- **Logging**: Clear (shows decision-making process)

## Troubleshooting

### Issue: Pod Still Scheduled to NY Node

**Possible Causes**:
- NY node had more resources than expected
- Pod resource requests too small
- Calculation error in filling NY node

**Solution**:
- Increase pod resource requests
- Fill NY node more aggressively (90%+)
- Check actual node capacity: `kubectl describe node minikube-m02`

### Issue: Pod Stuck in Pending

**Possible Causes**:
- Both nodes full
- No nodes available
- Scheduler not running

**Solution**:
- Check node resources: `kubectl top nodes`
- Check scheduler logs: `kubectl logs -l app=custom-scheduler`
- Verify nodes are ready: `kubectl get nodes`

### Issue: Wrong Node Selected

**Possible Causes**:
- Node labels incorrect
- Carbon cache outdated
- Scheduler not reading cache

**Solution**:
- Verify labels: `kubectl get nodes --show-labels`
- Check cache: `kubectl exec -it <carbon-api-pod> -- cat /cache/carbon_cache.json`
- Check scheduler logs for carbon scoring

## Reproducibility

### Step-by-Step Instructions

1. **Setup Nodes**:
   ```bash
   kubectl label node minikube-m02 carbon-region=US-NY-NYIS
   kubectl label node minikube carbon-region=US-CAL-CISO
   ```

2. **Run Test Script**:
   ```bash
   ./test-ny-busy-fallback.sh
   ```

3. **Verify Results**:
   ```bash
   # Check pod location
   kubectl get pod test-fallback-pod -o wide
   
   # Check scheduler logs
   kubectl logs -l app=custom-scheduler --tail=50 | grep test-fallback-pod
   ```

### Expected Output

- ✅ NY node filled with busy pods
- ✅ Fallback pod scheduled to California
- ✅ Scheduler logs show resource constraint detection
- ✅ Pod successfully running on California node

## Key Takeaways

1. **Resource Constraints Are Hard Requirements**:
   - Scheduler cannot schedule pods to nodes without resources
   - Resource checks happen before carbon scoring
   - This is correct Kubernetes behavior

2. **Graceful Fallback**:
   - System doesn't fail when best node is full
   - Falls back to alternative nodes
   - Continues operating with higher carbon (but still functional)

3. **Carbon Optimization When Possible**:
   - Among nodes with available resources
   - Scheduler selects lowest-carbon option
   - Maintains carbon awareness within constraints

4. **Real-World Applicability**:
   - This scenario happens frequently in production
   - Demonstrates robust resource-aware carbon scheduling
   - Shows system handles edge cases correctly

## Related Experiments

- **Main Experiment** (`test-show-difference.sh`): Compares carbon-aware vs default scheduling
- **Edge Cases** (`test-edge-cases.sh`): Tests various failure modes
- **Rapid Scheduling** (Scenario 6): Tests consistency under load

This experiment complements the main experiment by showing how resource constraints interact with carbon optimization.

