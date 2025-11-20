# Scheduler Policy Validation Guide

## Overview

This guide helps you verify that the carbon-aware scheduler is working correctly and making accurate scheduling decisions based on carbon intensity.

## Quick Verification

Run the automated verification script:

```bash
cd scheduler
./verify-scheduler.sh
```

This script checks:
1. ✅ Scheduler deployment status
2. ✅ Carbon-aware mode configuration
3. ✅ Node labels (carbon-region)
4. ✅ Carbon cache availability
5. ✅ Pod scheduling test
6. ✅ Scheduler decision logs

## Manual Verification Steps

### 1. Verify Scheduler is Running

```bash
# Check scheduler pod
kubectl get pods -l app=custom-scheduler

# Check scheduler logs
kubectl logs -f deployment/custom-scheduler
```

**Expected Output:**
```
Connected to Kubernetes API
Carbon-aware scheduling ENABLED (cache: /cache/carbon_cache.json)
```

### 2. Verify Carbon Cache is Available

```bash
# Check carbon-api pod
kubectl get pods -l app=carbon-api

# View cache contents
kubectl exec -it deployment/carbon-api -- cat /cache/carbon_cache.json | jq .

# Verify cache is recent (within TTL)
kubectl exec -it deployment/carbon-api -- cat /cache/carbon_cache.json | \
  jq -r '.timestamp'
```

**Expected:**
- Cache file exists
- Timestamp is recent (< 10 minutes old)
- Contains region data with carbon intensity

### 3. Verify Node Labels

```bash
# List all nodes with their carbon-region labels
kubectl get nodes --show-labels | grep carbon-region

# Or get specific label
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, region: .metadata.labels["carbon-region"]}'
```

**Expected:**
- All nodes should have `carbon-region` labels
- Labels should match zones in carbon cache (e.g., `US-CAL-CISO`, `US-TEX-ERCO`)

**If missing, label nodes:**
```bash
kubectl label nodes <node-name> carbon-region=US-CAL-CISO
kubectl label nodes <node-name> carbon-region=US-TEX-ERCO
```

### 4. Test Pod Scheduling

**Create a test pod:**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: scheduler-test-pod
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
```

**Watch the scheduling:**
```bash
# Watch pod status
kubectl get pod scheduler-test-pod -w

# Check which node it was scheduled to
kubectl get pod scheduler-test-pod -o jsonpath='{.spec.nodeName}'

# Check scheduler logs for decision
kubectl logs deployment/custom-scheduler | grep scheduler-test-pod
```

**Expected in logs:**
```
Unscheduled pod detected: default/scheduler-test-pod
Node node-a: region=US-CAL-CISO, Carbon Intensity=357.00 g CO2/kWh
Node node-b: region=US-TEX-ERCO, Carbon Intensity=436.00 g CO2/kWh
Carbon-aware decision: node-a (region=US-CAL-CISO, Carbon Intensity=357.00 g CO2/kWh)
Pod scheduler-test-pod scheduled to node-a
```

### 5. Verify Carbon-Aware Decision Logic

**Check scheduler logs for decision process:**
```bash
kubectl logs deployment/custom-scheduler | tail -50
```

**Look for:**
- ✅ "Carbon cache loaded" message
- ✅ Node scoring with carbon intensity values
- ✅ "Carbon-aware decision" with selected node
- ✅ Selected node should have LOWEST carbon intensity

**Example good output:**
```
Carbon cache loaded: 4 regions, best: US-CAL-CISO
Node node-california: region=US-CAL-CISO, Carbon Intensity=357.00 g CO2/kWh
Node node-texas: region=US-TEX-ERCO, Carbon Intensity=436.00 g CO2/kWh
Node node-midwest: region=US-MIDW-MISO, Carbon Intensity=601.00 g CO2/kWh
Carbon-aware decision: node-california (region=US-CAL-CISO, Carbon Intensity=357.00 g CO2/kWh)
```

### 6. Compare Carbon-Aware vs Non-Carbon-Aware

**Test 1: Carbon-Aware Mode (default)**
```bash
# Ensure carbon-aware is enabled
kubectl set env deployment/custom-scheduler CARBON_AWARE_MODE=true
kubectl rollout restart deployment/custom-scheduler

# Create test pod
kubectl run test-carbon-aware --image=nginx --restart=Never \
  --overrides='{"spec":{"schedulerName":"custom-scheduler"}}'

# Check which node it went to
kubectl get pod test-carbon-aware -o jsonpath='{.spec.nodeName}'
```

**Test 2: Non-Carbon-Aware Mode**
```bash
# Disable carbon-aware
kubectl set env deployment/custom-scheduler CARBON_AWARE_MODE=false
kubectl rollout restart deployment/custom-scheduler

# Create test pod
kubectl run test-non-carbon --image=nginx --restart=Never \
  --overrides='{"spec":{"schedulerName":"custom-scheduler"}}'

# Check which node it went to
kubectl get pod test-non-carbon -o jsonpath='{.spec.nodeName}'
```

**Compare:**
- Carbon-aware: Should go to node with lowest carbon intensity
- Non-carbon-aware: Should go to first available node (may be different)

### 7. Verify Resource Checking

**Test with resource constraints:**
```bash
# Create pod with large resource requests
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: resource-test-pod
spec:
  schedulerName: custom-scheduler
  containers:
  - name: test-container
    image: nginx:latest
    resources:
      requests:
        memory: "8Gi"  # Large request
        cpu: "4"
EOF
```

**Check scheduler logs:**
```bash
kubectl logs deployment/custom-scheduler | grep resource-test-pod
```

**Expected:**
- Nodes without enough resources should be filtered out
- Logs should show "insufficient resources" messages
- Only nodes with enough resources should be considered for carbon-aware selection

## Validation Checklist

- [ ] Scheduler pod is running
- [ ] Carbon-aware mode is enabled in logs
- [ ] Carbon cache file exists and is recent
- [ ] Nodes are labeled with carbon-region
- [ ] Test pods are scheduled successfully
- [ ] Scheduler logs show carbon intensity values
- [ ] Selected node has lowest carbon intensity among available nodes
- [ ] Resource checking filters out nodes without capacity
- [ ] Non-carbon-aware mode selects different nodes

## Common Issues

### Issue: Pods not scheduling

**Check:**
```bash
# Check pod events
kubectl describe pod <pod-name>

# Check scheduler logs
kubectl logs deployment/custom-scheduler

# Verify scheduler name matches
kubectl get pod <pod-name> -o jsonpath='{.spec.schedulerName}'
```

**Solutions:**
- Ensure `schedulerName: custom-scheduler` in pod spec
- Check scheduler pod is running
- Verify scheduler has proper RBAC permissions

### Issue: All pods go to same node

**Check:**
```bash
# Verify multiple nodes exist
kubectl get nodes

# Check node labels
kubectl get nodes --show-labels

# Check carbon cache has multiple regions
kubectl exec deployment/carbon-api -- cat /cache/carbon_cache.json | jq '.regions | keys'
```

**Solutions:**
- Label nodes with different regions
- Ensure carbon cache has data for all regions
- Check if nodes have different carbon intensities

### Issue: Scheduler selects high-carbon node

**Check:**
```bash
# Verify carbon cache is up-to-date
kubectl exec deployment/carbon-api -- cat /cache/carbon_cache.json | jq '.timestamp'

# Check if cache is expired
kubectl logs deployment/custom-scheduler | grep "cache expired"

# Verify node labels match cache regions
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, region: .metadata.labels["carbon-region"]}'
```

**Solutions:**
- Ensure carbon-api is polling regularly
- Verify node labels match cache zone codes exactly
- Check cache TTL hasn't expired

## Advanced Validation

### Monitor Multiple Pods

```bash
# Create multiple test pods
for i in {1..5}; do
  kubectl run test-pod-$i --image=nginx --restart=Never \
    --overrides='{"spec":{"schedulerName":"custom-scheduler"}}'
done

# Check distribution
kubectl get pods -o wide | grep test-pod

# Analyze node distribution
kubectl get pods -o json | jq '.items[] | {name: .metadata.name, node: .spec.nodeName}' | \
  jq -s 'group_by(.node) | map({node: .[0].node, count: length})'
```

### Verify Carbon Savings

Use the simulator to estimate savings:
```bash
cd simulator
go run simulate.go ../cache/carbon_cache.json 100 0.5
```

Compare actual pod distribution vs expected carbon-aware distribution.

## Continuous Monitoring

**Watch scheduler logs:**
```bash
kubectl logs -f deployment/custom-scheduler
```

**Monitor pod scheduling:**
```bash
watch kubectl get pods -o wide
```

**Check cache freshness:**
```bash
watch -n 60 'kubectl exec deployment/carbon-api -- cat /cache/carbon_cache.json | jq -r .timestamp'
```

