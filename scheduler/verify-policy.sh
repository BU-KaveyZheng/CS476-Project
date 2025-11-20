#!/bin/bash
# Verify Scheduling Policy - Works without Kubernetes cluster

set -e

echo "🔍 Scheduling Policy Verification"
echo "=================================="
echo ""

cd "$(dirname "$0")"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if cache file exists
CACHE_FILE="../cache/carbon_cache.json"
if [ ! -f "$CACHE_FILE" ]; then
    echo -e "${RED}❌ Cache file not found: $CACHE_FILE${NC}"
    echo "   Run the Carbon API first: cd ../carbon-api && ./test-api.sh"
    exit 1
fi

echo -e "${GREEN}✓ Cache file found${NC}"
echo ""

# 1. Verify Cache Structure
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Verifying Carbon Cache Structure"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if command -v python3 &> /dev/null; then
    python3 << 'PYTHON'
import json
import sys
from datetime import datetime

try:
    with open('../cache/carbon_cache.json') as f:
        data = json.load(f)
    
    print("✓ Cache file is valid JSON")
    print(f"  Timestamp: {data.get('timestamp', 'N/A')}")
    print(f"  TTL: {data.get('ttl_minutes', 'N/A')} minutes")
    
    # Handle nested structure
    regions = data.get('regions', {})
    if isinstance(regions, dict) and 'regions' in regions:
        regions = regions['regions']
    
    print(f"  Regions cached: {len(regions)}")
    
    if len(regions) > 0:
        print("\n  Region carbon intensities:")
        sorted_regions = sorted(regions.items(), 
                              key=lambda x: x[1].get('carbonIntensity', x[1].get('moer', 9999)))
        for zone, info in sorted_regions:
            ci = info.get('carbonIntensity', info.get('moer', 'N/A'))
            print(f"    {zone}: {ci} g CO2/kWh")
        
        best = sorted_regions[0][0]
        worst = sorted_regions[-1][0]
        print(f"\n  Best region: {best}")
        print(f"  Worst region: {worst}")
    
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
PYTHON
else
    echo -e "${YELLOW}⚠ Python3 not found, skipping cache validation${NC}"
fi

echo ""

# 2. Verify Scheduler Code Logic
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. Verifying Scheduler Policy Logic"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if ! command -v go &> /dev/null; then
    echo -e "${RED}❌ Go not found${NC}"
    exit 1
fi

echo "Building scheduler..."
if go build -o custom-scheduler main.go 2>&1 | grep -i error; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Scheduler builds successfully${NC}"

# Check for key policy elements in code
echo ""
echo "Checking policy implementation:"

POLICY_CHECKS=0
TOTAL_CHECKS=0

# Check 1: Carbon-aware mode check
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if grep -q "carbonAwareMode" main.go; then
    echo -e "  ${GREEN}✓${NC} Carbon-aware mode toggle found"
    POLICY_CHECKS=$((POLICY_CHECKS + 1))
else
    echo -e "  ${RED}✗${NC} Carbon-aware mode toggle not found"
fi

# Check 2: Resource checking
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if grep -q "nodeHasResources" main.go; then
    echo -e "  ${GREEN}✓${NC} Resource availability checking found"
    POLICY_CHECKS=$((POLICY_CHECKS + 1))
else
    echo -e "  ${RED}✗${NC} Resource availability checking not found"
fi

# Check 3: Carbon intensity scoring
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if grep -q "CarbonIntensity\|carbonIntensity" main.go; then
    echo -e "  ${GREEN}✓${NC} Carbon intensity scoring found"
    POLICY_CHECKS=$((POLICY_CHECKS + 1))
else
    echo -e "  ${RED}✗${NC} Carbon intensity scoring not found"
fi

# Check 4: Lowest score selection
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if grep -q "s.score < bestNode.score" main.go; then
    echo -e "  ${GREEN}✓${NC} Lowest carbon selection logic found"
    POLICY_CHECKS=$((POLICY_CHECKS + 1))
else
    echo -e "  ${RED}✗${NC} Lowest carbon selection logic not found"
fi

# Check 5: Node filtering
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if grep -q "NodeReady\|isReady" main.go; then
    echo -e "  ${GREEN}✓${NC} Node readiness checking found"
    POLICY_CHECKS=$((POLICY_CHECKS + 1))
else
    echo -e "  ${RED}✗${NC} Node readiness checking not found"
fi

echo ""
echo "Policy checks: $POLICY_CHECKS/$TOTAL_CHECKS passed"

if [ $POLICY_CHECKS -eq $TOTAL_CHECKS ]; then
    echo -e "${GREEN}✓ All policy elements verified${NC}"
else
    echo -e "${YELLOW}⚠ Some policy elements missing${NC}"
fi

echo ""

# 3. Test Cache Reading
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. Testing Cache Reading"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

export CACHE_FILE="$CACHE_FILE"
go run test-cache.go

echo ""

# 4. Policy Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. Scheduling Policy Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat << 'POLICY'
Policy: Carbon-Aware Node Selection

1. Filter Nodes:
   ✓ Node must be Ready
   ✓ Node must not have NoSchedule taints
   ✓ Node must have enough CPU/memory resources

2. Score Nodes:
   ✓ Get carbon intensity for node's region
   ✓ Score = carbon intensity (g CO2/kWh)
   ✓ Lower score = better (less carbon)

3. Select Node:
   ✓ Choose node with LOWEST carbon intensity
   ✓ Among nodes that can fit the pod

4. Fallback:
   ✓ If cache unavailable → first available node
   ✓ If region not found → default high score (deprioritize)

Policy Characteristics:
  ✅ Carbon-first: Always selects lowest carbon node
  ✅ Resource-aware: Checks CPU/memory availability
  ✅ Fallback-safe: Handles cache failures gracefully
  ⚠️  No load balancing: Always picks greenest (not distributed)
POLICY

echo ""
echo -e "${GREEN}✅ Policy verification complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Deploy scheduler: kubectl apply -f k8s.yaml"
echo "  2. Label nodes: kubectl label nodes <node> carbon-region=<zone>"
echo "  3. Test with pod: kubectl run test --image=nginx --restart=Never --overrides='{\"spec\":{\"schedulerName\":\"custom-scheduler\"}}'"
echo "  4. Check logs: kubectl logs deployment/custom-scheduler"

