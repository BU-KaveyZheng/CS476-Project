# Testing Guide

This guide covers testing the Carbon API, Scheduler, and Simulation components.

## Prerequisites

- Python 3.11+ installed
- Go 1.21+ installed
- Kubernetes cluster (Minikube) running
- Electricity Maps API key configured

## 1. Testing the Carbon API (Python)

### Local Testing

```bash
cd carbon-api

# Create virtual environment (first time only)
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export ELECTRICITY_MAPS_API_KEY="your-api-key-here"
export POLL_INTERVAL_MINUTES=1  # Test with 1 minute for faster results
export CACHE_TTL_MINUTES=10
# Cache file defaults to ../cache/carbon_cache.json (project folder)
# Or set explicitly: export CACHE_FILE="../cache/carbon_cache.json"
export ZONES="US-CAL-CISO,US-TEX-ERCO,US-NY-NYIS,US-MIDA-PJM,US-MIDW-MISO"

# Run the poller (make sure venv is activated)
python carbon_poller.py

# When done, deactivate virtual environment
deactivate
```

**Expected Output:**
```
2024-01-01 12:00:00 - __main__ - INFO - Starting Carbon Intensity API Poller (Electricity Maps)
2024-01-01 12:00:00 - __main__ - INFO - Poll interval: 1 minutes
2024-01-01 12:00:00 - __main__ - INFO - Polling carbon intensity for 5 zones: ['US-CAL-CISO', 'US-TEX-ERCO', ...]
2024-01-01 12:00:00 - __main__ - INFO - Fetching data for US-CAL-CISO...
2024-01-01 12:00:00 - __main__ - INFO - US-CAL-CISO: Carbon Intensity = 250.5 g CO2/kWh
...
2024-01-01 12:00:00 - __main__ - INFO - Cache updated. Best zone: US-NY-NYIS
```

**Verify Cache File:**
```bash
# Check the cache file was created (in project cache/ folder)
cat ../cache/carbon_cache.json | jq .
# Or if you set CACHE_FILE explicitly:
cat $CACHE_FILE | jq .

# Should show:
# {
#   "timestamp": "2024-01-01T12:00:00",
#   "ttl_minutes": 10,
#   "regions": {
#     "US-CAL-CISO": { ... },
#     ...
#   },
#   "sorted_by_carbon": [...],
#   "best_region": "US-NY-NYIS",
#   "worst_region": "..."
# }
```

### Docker Testing

```bash
cd carbon-api

# Build the image
docker build -t carbon-api:latest .

# Run container
docker run -it --rm \
  -e ELECTRICITY_MAPS_API_KEY="your-api-key" \
  -e POLL_INTERVAL_MINUTES=1 \
  -v /tmp:/cache \
  carbon-api:latest
```

### Kubernetes Testing

```bash
# Make sure your API key is set in k8s.yaml secret
# Then deploy:
kubectl apply -f carbon-api/k8s.yaml

# Check pod status
kubectl get pods -l app=carbon-api

# View logs
kubectl logs -f deployment/carbon-api

# Check cache file (if using PVC)
kubectl exec -it deployment/carbon-api -- cat /cache/carbon_cache.json | jq .
```

## 2. Testing the Scheduler (Go)

### Local Testing (without Kubernetes)

First, ensure the cache file exists from the API test:

```bash
# Make sure cache file exists (in project cache/ folder)
ls -la ../cache/carbon_cache.json

# Or copy from Kubernetes pod if testing there:
# kubectl cp <pod-name>:/cache/carbon_cache.json cache/carbon_cache.json
```

### Build and Test Locally

```bash
cd scheduler

# Set environment variables
# Cache file defaults to ../cache/carbon_cache.json (project folder)
# Or set explicitly: export CACHE_FILE="../cache/carbon_cache.json"
export CARBON_AWARE_MODE="true"

# Build
go build -o custom-scheduler main.go

# Test cache reading (create a simple test)
go run -exec ./custom-scheduler <<EOF
package main
import (
    "fmt"
    "os"
    "encoding/json"
    "io/ioutil"
)
func main() {
    data, _ := ioutil.ReadFile(os.Getenv("CACHE_FILE"))
    var cache CarbonCache
    json.Unmarshal(data, &cache)
    fmt.Printf("Best region: %s\n", cache.BestRegion)
    fmt.Printf("Regions: %d\n", len(cache.Regions))
}
EOF
```

### Kubernetes Testing

```bash
cd scheduler

# Build Docker image (in Minikube)
eval $(minikube docker-env)
docker build -t custom-scheduler:latest .

# Deploy scheduler
kubectl apply -f scheduler/k8s.yaml

# Check scheduler pod
kubectl get pods -l app=custom-scheduler

# View scheduler logs
kubectl logs -f deployment/custom-scheduler

# Test with a sample pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-carbon-aware
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

# Watch the pod get scheduled
kubectl get pod test-pod-carbon-aware -o wide

# Check scheduler logs to see decision
kubectl logs -f deployment/custom-scheduler | grep "test-pod-carbon-aware"

# Clean up test pod
kubectl delete pod test-pod-carbon-aware
```

### Test Non-Carbon-Aware Mode

```bash
# Update scheduler config
kubectl set env deployment/custom-scheduler CARBON_AWARE_MODE=false

# Restart scheduler
kubectl rollout restart deployment/custom-scheduler

# Create test pod
kubectl run test-pod-non-carbon --image=nginx --restart=Never --overrides='{"spec":{"schedulerName":"custom-scheduler"}}'

# Check logs - should see "Non-carbon-aware: scheduling to..."
kubectl logs deployment/custom-scheduler | tail -20
```

## 3. Testing the Simulation

### Run Simulation

```bash
cd simulator

# First, ensure you have a cache file
# Either from local API test (in cache/ folder) or copy from Kubernetes pod:
# kubectl cp <carbon-api-pod>:/cache/carbon_cache.json cache/carbon_cache.json

# Run simulation with default values (100 pods, 0.5 kWh each)
go run simulate.go ../cache/carbon_cache.json

# Run with custom parameters
go run simulate.go ../cache/carbon_cache.json 500 1.0
# This simulates 500 pods with 1.0 kWh energy consumption each
```

**Expected Output:**
```
Running simulation with 100 pods, 0.50 kWh per pod
==============================================================

Non-Carbon-Aware          | Carbon-Aware
-------------------------------------------------------------
Total Pods: 100           | Total Pods: 100
Total Carbon: 35000.00 g CO2 | Total Carbon: 20000.00 g CO2
Avg per Pod: 350.00 g CO2 | Avg per Pod: 200.00 g CO2

Region Distribution:
Region               | Non-Carbon-Aware    | Carbon-Aware
-------------------------------------------------------------
US-CAL-CISO          | 20                  | 0
US-TEX-ERCO          | 20                  | 0
US-NY-NYIS           | 20                  | 100
US-MIDA-PJM          | 20                  | 0
US-MIDW-MISO         | 20                  | 0

==============================================================
CARBON SAVINGS: 15000.00 g CO2 (42.86% reduction)
==============================================================
```

### Build Simulation Binary

```bash
cd simulator
go build -o simulate simulate.go

# Run the binary
./simulate /tmp/carbon_cache.json 200 0.75
```

## 4. End-to-End Testing

### Complete Test Flow

```bash
# Step 1: Start Carbon API (in one terminal)
cd carbon-api
export ELECTRICITY_MAPS_API_KEY="your-key"
export CACHE_FILE="/tmp/carbon_cache.json"
python carbon_poller.py &
API_PID=$!

# Wait for first poll (adjust sleep time based on POLL_INTERVAL_MINUTES)
sleep 70  # Wait for first poll + buffer

# Step 2: Verify cache exists
cat /tmp/carbon_cache.json | jq '.best_region'

# Step 3: Run simulation
cd ../simulator
go run simulate.go /tmp/carbon_cache.json

# Step 4: Test scheduler (if Kubernetes is available)
cd ../scheduler
# Deploy and test as shown above

# Step 5: Cleanup
kill $API_PID
```

## 5. Troubleshooting

### Carbon API Issues

**Problem**: "Zone not found" errors
```bash
# Verify zone codes
curl -H "auth-token: YOUR_API_KEY" https://api.electricitymap.org/v3/zones | jq 'keys | .[]' | grep US

# Check your zones match available zones
```

**Problem**: API rate limiting
```bash
# Increase poll interval
export POLL_INTERVAL_MINUTES=10
```

**Problem**: Cache not updating
```bash
# Check logs for errors
kubectl logs deployment/carbon-api

# Verify API key is correct
kubectl get secret carbon-api-secret -o jsonpath='{.data.ELECTRICITY_MAPS_API_KEY}' | base64 -d
```

### Scheduler Issues

**Problem**: Scheduler can't read cache
```bash
# Verify cache file exists and is readable
kubectl exec deployment/custom-scheduler -- ls -la /cache/
kubectl exec deployment/custom-scheduler -- cat /cache/carbon_cache.json

# Check PVC is mounted correctly
kubectl describe pod -l app=custom-scheduler | grep -A 5 "Mounts:"
```

**Problem**: Pods not scheduling
```bash
# Check scheduler is running
kubectl get pods -l app=custom-scheduler

# Check scheduler logs
kubectl logs deployment/custom-scheduler

# Verify pod has correct schedulerName
kubectl get pod <pod-name> -o jsonpath='{.spec.schedulerName}'
```

**Problem**: Nodes not labeled
```bash
# List nodes and their labels
kubectl get nodes --show-labels

# Label nodes with zones
kubectl label nodes <node-name> carbon-region=US-CAL-CISO
kubectl label nodes <node-name> carbon-region=US-TEX-ERCO
# etc.
```

### Simulation Issues

**Problem**: "Cache file not found"
```bash
# Ensure cache file exists
ls -la /tmp/carbon_cache.json

# Or specify full path
go run simulate.go /full/path/to/carbon_cache.json
```

**Problem**: Invalid cache format
```bash
# Validate JSON
cat /tmp/carbon_cache.json | jq .

# Check cache has required fields
jq '.regions | keys' /tmp/carbon_cache.json
```

## 6. Quick Test Script

Create a test script `test-all.sh`:

```bash
#!/bin/bash
set -e

echo "=== Testing Carbon API ==="
cd carbon-api
export ELECTRICITY_MAPS_API_KEY="${ELECTRICITY_MAPS_API_KEY:-your-key}"
export CACHE_FILE="/tmp/carbon_cache.json"
export POLL_INTERVAL_MINUTES=1
timeout 120 python carbon_poller.py &
API_PID=$!
sleep 70  # Wait for first poll
kill $API_PID 2>/dev/null || true

if [ -f /tmp/carbon_cache.json ]; then
    echo "✓ Cache file created"
    jq -r '.best_region' /tmp/carbon_cache.json
else
    echo "✗ Cache file not created"
    exit 1
fi

echo ""
echo "=== Testing Simulation ==="
cd ../simulator
go run simulate.go /tmp/carbon_cache.json 10 0.5

echo ""
echo "=== All tests passed! ==="
```

Make it executable and run:
```bash
chmod +x test-all.sh
./test-all.sh
```

