#!/bin/bash
# Verification script for Carbon-Aware Scheduler

set -e

echo "🔍 Carbon-Aware Scheduler Verification"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found${NC}"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Kubernetes cluster accessible${NC}"
echo ""

# 1. Check if scheduler is deployed
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Checking Scheduler Deployment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if kubectl get deployment custom-scheduler &> /dev/null; then
    echo -e "${GREEN}✓ Scheduler deployment found${NC}"
    
    SCHEDULER_POD=$(kubectl get pods -l app=custom-scheduler -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$SCHEDULER_POD" ]; then
        STATUS=$(kubectl get pod "$SCHEDULER_POD" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$STATUS" = "Running" ]; then
            echo -e "${GREEN}✓ Scheduler pod running: $SCHEDULER_POD${NC}"
        else
            echo -e "${YELLOW}⚠ Scheduler pod status: $STATUS${NC}"
        fi
    else
        echo -e "${RED}❌ Scheduler pod not found${NC}"
    fi
else
    echo -e "${RED}❌ Scheduler deployment not found${NC}"
    echo "   Deploy with: kubectl apply -f scheduler/k8s.yaml"
    exit 1
fi

echo ""

# 2. Check scheduler logs for carbon-aware mode
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. Checking Scheduler Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$SCHEDULER_POD" ]; then
    CARBON_MODE=$(kubectl logs "$SCHEDULER_POD" 2>/dev/null | grep -i "carbon-aware" | head -1 || echo "")
    if echo "$CARBON_MODE" | grep -qi "enabled"; then
        echo -e "${GREEN}✓ Carbon-aware mode: ENABLED${NC}"
    elif echo "$CARBON_MODE" | grep -qi "disabled"; then
        echo -e "${YELLOW}⚠ Carbon-aware mode: DISABLED${NC}"
    else
        echo -e "${YELLOW}⚠ Could not determine carbon-aware mode${NC}"
    fi
fi

echo ""

# 3. Check nodes and their labels
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. Checking Node Labels (carbon-region)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
NODE_COUNT=0
LABELED_COUNT=0

for node in $NODES; do
    NODE_COUNT=$((NODE_COUNT + 1))
    REGION=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.carbon-region}' 2>/dev/null || echo "")
    if [ -n "$REGION" ]; then
        echo -e "${GREEN}✓ $node: carbon-region=$REGION${NC}"
        LABELED_COUNT=$((LABELED_COUNT + 1))
    else
        echo -e "${YELLOW}⚠ $node: no carbon-region label${NC}"
    fi
done

if [ $LABELED_COUNT -eq 0 ]; then
    echo ""
    echo -e "${RED}❌ No nodes labeled with carbon-region!${NC}"
    echo "   Label nodes with:"
    echo "   kubectl label nodes <node-name> carbon-region=US-CAL-CISO"
    echo "   kubectl label nodes <node-name> carbon-region=US-TEX-ERCO"
fi

echo ""

# 4. Check carbon cache
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. Checking Carbon Cache"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if carbon-api is running
if kubectl get deployment carbon-api &> /dev/null; then
    CARBON_POD=$(kubectl get pods -l app=carbon-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$CARBON_POD" ]; then
        echo -e "${GREEN}✓ Carbon API pod running: $CARBON_POD${NC}"
        
        # Try to read cache from pod
        if kubectl exec "$CARBON_POD" -- test -f /cache/carbon_cache.json 2>/dev/null; then
            echo -e "${GREEN}✓ Cache file exists${NC}"
            
            # Get cache info
            CACHE_TIMESTAMP=$(kubectl exec "$CARBON_POD" -- cat /cache/carbon_cache.json 2>/dev/null | \
                python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('timestamp','unknown'))" 2>/dev/null || echo "unknown")
            REGION_COUNT=$(kubectl exec "$CARBON_POD" -- cat /cache/carbon_cache.json 2>/dev/null | \
                python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('regions',{}); print(len(r.get('regions',r)))" 2>/dev/null || echo "0")
            
            echo "   Cache timestamp: $CACHE_TIMESTAMP"
            echo "   Regions cached: $REGION_COUNT"
        else
            echo -e "${YELLOW}⚠ Cache file not found${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Carbon API pod not found${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Carbon API not deployed${NC}"
fi

echo ""

# 5. Test scheduling a pod
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. Testing Pod Scheduling"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TEST_POD_NAME="scheduler-test-$(date +%s)"
echo "Creating test pod: $TEST_POD_NAME"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $TEST_POD_NAME
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

echo "Waiting for pod to be scheduled..."
sleep 5

POD_NODE=$(kubectl get pod "$TEST_POD_NAME" -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "")
POD_STATUS=$(kubectl get pod "$TEST_POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

if [ -n "$POD_NODE" ]; then
    echo -e "${GREEN}✓ Pod scheduled to node: $POD_NODE${NC}"
    
    # Check node region
    NODE_REGION=$(kubectl get node "$POD_NODE" -o jsonpath='{.metadata.labels.carbon-region}' 2>/dev/null || echo "")
    if [ -n "$NODE_REGION" ]; then
        echo "   Node region: $NODE_REGION"
        
        # Try to get carbon intensity for this region
        if [ -n "$CARBON_POD" ]; then
            CARBON_INTENSITY=$(kubectl exec "$CARBON_POD" -- cat /cache/carbon_cache.json 2>/dev/null | \
                python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('regions',{}).get('regions',d.get('regions',{})); print(r.get('$NODE_REGION',{}).get('carbonIntensity','N/A'))" 2>/dev/null || echo "N/A")
            echo "   Carbon intensity: $CARBON_INTENSITY g CO2/kWh"
        fi
    else
        echo -e "${YELLOW}⚠ Node has no carbon-region label${NC}"
    fi
    
    echo "   Pod status: $POD_STATUS"
else
    echo -e "${RED}❌ Pod not scheduled yet (status: $POD_STATUS)${NC}"
    echo "   Check scheduler logs: kubectl logs -f deployment/custom-scheduler"
fi

echo ""

# 6. Check scheduler logs for decision
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. Checking Scheduler Decision Logs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$SCHEDULER_POD" ]; then
    echo "Recent scheduler logs for pod $TEST_POD_NAME:"
    kubectl logs "$SCHEDULER_POD" --tail=20 2>/dev/null | grep -i "$TEST_POD_NAME" || echo "   (no logs found for test pod)"
fi

echo ""

# 7. Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Verification Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$POD_NODE" ] && [ "$POD_STATUS" != "Pending" ]; then
    echo -e "${GREEN}✓ Scheduler appears to be working${NC}"
    echo ""
    echo "To verify carbon-aware decisions:"
    echo "  1. Check scheduler logs: kubectl logs -f deployment/custom-scheduler"
    echo "  2. Look for 'Carbon-aware decision' messages"
    echo "  3. Verify pods are scheduled to nodes with lowest carbon intensity"
else
    echo -e "${YELLOW}⚠ Scheduler may not be working correctly${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check scheduler logs: kubectl logs deployment/custom-scheduler"
    echo "  2. Verify scheduler is running: kubectl get pods -l app=custom-scheduler"
    echo "  3. Check pod events: kubectl describe pod $TEST_POD_NAME"
fi

echo ""
echo "Cleaning up test pod..."
kubectl delete pod "$TEST_POD_NAME" --ignore-not-found=true &> /dev/null

echo ""
echo "Done! ✅"

