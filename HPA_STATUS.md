# HPA (Horizontal Pod Autoscaler) Status

## Current Status: **NOT IMPLEMENTED** ❌

HPA is **not currently implemented** in this codebase. However, it's **compatible** with our carbon-aware scheduler and can be configured separately.

---

## What is HPA?

**Horizontal Pod Autoscaler (HPA)** is a Kubernetes feature that automatically scales the number of pods in a deployment based on observed metrics (CPU, memory, custom metrics).

### How HPA Works

1. **Monitors Metrics**: Watches CPU/memory usage or custom metrics
2. **Scales Up**: Creates more pods when load is high
3. **Scales Down**: Deletes pods when load is low
4. **Uses Scheduler**: New pods created by HPA are scheduled by our carbon-aware scheduler!

---

## Why HPA is Compatible

### The Flow

```
1. HPA detects high load
   ↓
2. HPA creates new pods (via Deployment)
   ↓
3. New pods are unscheduled (no node assigned)
   ↓
4. Our carbon-aware scheduler picks them up
   ↓
5. Scheduler selects lowest-carbon node
   ↓
6. Pods run on green nodes ✅
```

**Key Point**: HPA creates pods, but our scheduler decides WHERE they run!

---

## How to Add HPA

### Step 1: Create HPA Resource

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app-deployment
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### Step 2: Ensure Deployment Uses Custom Scheduler

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app-deployment
spec:
  replicas: 2
  template:
    spec:
      schedulerName: custom-scheduler  # ← Important!
      containers:
      - name: app
        image: my-app:latest
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
```

### Step 3: Deploy Both

```bash
kubectl apply -f deployment.yaml
kubectl apply -f hpa.yaml
```

---

## Example: HPA + Carbon-Aware Scheduler

### Scenario: High Load Detected

```
Initial State:
  Deployment: 2 replicas
  Pods: pod-1, pod-2 (both on NY node - best carbon)
  CPU Usage: 85% (high!)

HPA Detects High Load:
  → Creates pod-3
  → Creates pod-4
  
Scheduler Decisions:
  pod-3 → NY node (334 g CO2/kWh) ✅
  pod-4 → NY node (334 g CO2/kWh) ✅
  
Result:
  ✅ Load distributed across 4 pods
  ✅ All pods on lowest-carbon node
  ✅ CPU usage drops to ~42%
```

### Scenario: NY Node Full, HPA Creates More Pods

```
State:
  NY Node: Full (no resources)
  CA Node: Available
  
HPA Creates New Pods:
  → pod-5 needs scheduling
  
Scheduler Decision:
  ✅ Checks NY node: No resources → Filtered out
  ✅ Checks CA node: Has resources → Selected
  ✅ pod-5 → CA node (360 g CO2/kWh)
  
Result:
  ✅ Pod scheduled (resource constraint respected)
  ✅ Best carbon node selected among available nodes
```

---

## Benefits of Adding HPA

### 1. Automatic Scaling
- Scales up when busy
- Scales down when idle
- Reduces manual intervention

### 2. Works with Carbon-Aware Scheduler
- HPA creates pods
- Scheduler places them on green nodes
- Best of both worlds!

### 3. Handles Request Load
- When pods get busy handling requests
- HPA creates more pods
- Load distributed across more pods
- Better than just queuing requests

---

## Current System Without HPA

### What Happens Now

```
High Load Scenario:
  Pod 1: Handling 100 requests/sec (busy)
  Pod 2: Handling 100 requests/sec (busy)
  
New Request Arrives:
  → Service routes to Pod 1 (round-robin)
  → Request may queue/wait
  → Response time increases
```

### With HPA (Future)

```
High Load Detected:
  → HPA creates Pod 3, Pod 4
  
New Request Arrives:
  → Service routes to Pod 3 (less busy)
  → Faster response time
  → All pods on green nodes (scheduler's job)
```

---

## Implementation Status

### ✅ What We Have
- Carbon-aware scheduler (decides WHERE pods run)
- Resource-aware scheduling (checks CPU/memory)
- Works with any pod creation mechanism

### ❌ What We Don't Have
- HPA configuration files
- HPA examples in documentation
- HPA test scenarios

### ✅ What We Can Add
- HPA YAML examples
- HPA test scenarios
- Documentation on HPA + scheduler integration

---

## Recommendation

**HPA should be added** as a complementary feature:

1. **HPA handles scaling** (how many pods)
2. **Scheduler handles placement** (where pods run)
3. **Together**: Auto-scale + carbon-aware placement

### Next Steps

1. Create HPA example configurations
2. Add HPA test scenarios
3. Document HPA + scheduler integration
4. Test HPA with carbon-aware scheduler

---

## Summary

- **HPA Status**: Not implemented, but compatible
- **Can be added**: Yes, as separate Kubernetes resource
- **Works with scheduler**: Yes, HPA creates pods, scheduler places them
- **Recommended**: Add HPA for complete solution

**Key Point**: HPA and our scheduler are complementary - HPA decides HOW MANY pods, scheduler decides WHERE they run!

