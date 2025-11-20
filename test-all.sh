#!/bin/bash
set -e

echo "🧪 Carbon-Aware Scheduler Testing Suite"
echo "========================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo "📋 Checking prerequisites..."
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ Python 3 not found${NC}"
    exit 1
fi
if ! command -v go &> /dev/null; then
    echo -e "${RED}✗ Go not found${NC}"
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠ jq not found (optional, for JSON parsing)${NC}"
fi
echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# Set up test environment
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
CACHE_FILE="$PROJECT_ROOT/cache/carbon_cache.json"
mkdir -p "$PROJECT_ROOT/cache"
export CACHE_FILE

# Test 1: Carbon API
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Carbon API Poller"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -z "$ELECTRICITY_MAPS_API_KEY" ]; then
    echo -e "${YELLOW}⚠ ELECTRICITY_MAPS_API_KEY not set${NC}"
    echo "   Set it with: export ELECTRICITY_MAPS_API_KEY='your-key'"
    echo "   Skipping API test..."
else
    cd carbon-api
    
    # Install dependencies if needed
    if [ ! -d "venv" ]; then
        echo "Creating virtual environment..."
        python3 -m venv venv
    fi
    source venv/bin/activate
    pip install -q -r requirements.txt
    
    # Set test environment
    export POLL_INTERVAL_MINUTES=1
    export CACHE_TTL_MINUTES=10
    export ZONES="US-CAL-CISO,US-TEX-ERCO,US-NY-NYIS,US-MIDA-PJM,US-MIDW-MISO"
    
    echo "Starting API poller (will run for 70 seconds)..."
    timeout 70 python3 carbon_poller.py &
    API_PID=$!
    
    sleep 70
    
    # Check if process is still running
    if kill -0 $API_PID 2>/dev/null; then
        kill $API_PID 2>/dev/null || true
    fi
    
    wait $API_PID 2>/dev/null || true
    
    if [ -f "$CACHE_FILE" ]; then
        echo -e "${GREEN}✓ Cache file created${NC}"
        if command -v jq &> /dev/null; then
            BEST_REGION=$(jq -r '.best_region' "$CACHE_FILE" 2>/dev/null || echo "unknown")
            REGION_COUNT=$(jq '.regions | length' "$CACHE_FILE" 2>/dev/null || echo "0")
            echo "   Best region: $BEST_REGION"
            echo "   Zones cached: $REGION_COUNT"
        fi
    else
        echo -e "${RED}✗ Cache file not created${NC}"
        exit 1
    fi
    
    deactivate
    cd ..
fi

echo ""

# Test 2: Simulation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Simulation Tool"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -f "$CACHE_FILE" ]; then
    echo -e "${YELLOW}⚠ Cache file not found, using mock data${NC}"
    # Create a simple mock cache for testing
    cat > "$CACHE_FILE" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S)",
  "ttl_minutes": 10,
  "regions": {
    "US-CAL-CISO": {"zone": "US-CAL-CISO", "carbonIntensity": 250.0},
    "US-TEX-ERCO": {"zone": "US-TEX-ERCO", "carbonIntensity": 450.0},
    "US-NY-NYIS": {"zone": "US-NY-NYIS", "carbonIntensity": 200.0},
    "US-MIDA-PJM": {"zone": "US-MIDA-PJM", "carbonIntensity": 350.0},
    "US-MIDW-MISO": {"zone": "US-MIDW-MISO", "carbonIntensity": 500.0}
  },
  "sorted_by_carbon": ["US-NY-NYIS", "US-CAL-CISO", "US-MIDA-PJM", "US-TEX-ERCO", "US-MIDW-MISO"],
  "best_region": "US-NY-NYIS",
  "worst_region": "US-MIDW-MISO"
}
EOF
fi

cd simulator
echo "Running simulation with 50 pods, 0.5 kWh each..."
go run simulate.go "$CACHE_FILE" 50 0.5
cd ..

echo ""

# Test 3: Scheduler (if Kubernetes available)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Scheduler (Kubernetes)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
    echo "Kubernetes cluster detected"
    
    # Check if scheduler is deployed
    if kubectl get deployment custom-scheduler &> /dev/null; then
        echo -e "${GREEN}✓ Scheduler deployment found${NC}"
        
        # Check scheduler pod status
        SCHEDULER_POD=$(kubectl get pods -l app=custom-scheduler -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$SCHEDULER_POD" ]; then
            echo "   Pod: $SCHEDULER_POD"
            STATUS=$(kubectl get pod "$SCHEDULER_POD" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            echo "   Status: $STATUS"
            
            if [ "$STATUS" = "Running" ]; then
                echo -e "${GREEN}✓ Scheduler is running${NC}"
                
                # Show recent logs
                echo ""
                echo "Recent scheduler logs:"
                kubectl logs "$SCHEDULER_POD" --tail=5 2>/dev/null || echo "   (no logs available)"
            else
                echo -e "${YELLOW}⚠ Scheduler pod not running${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ Scheduler pod not found${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Scheduler not deployed${NC}"
        echo "   Deploy with: kubectl apply -f scheduler/k8s.yaml"
    fi
else
    echo -e "${YELLOW}⚠ Kubernetes not available (skipping)${NC}"
    echo "   To test scheduler:"
    echo "   1. Start minikube: minikube start"
    echo "   2. Build image: eval \$(minikube docker-env) && docker build -t custom-scheduler:latest scheduler/"
    echo "   3. Deploy: kubectl apply -f scheduler/k8s.yaml"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Testing complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Review cache file: cat $CACHE_FILE | jq ."
echo "  2. Test scheduler with a pod:"
echo "     kubectl run test-pod --image=nginx --restart=Never --overrides='{\"spec\":{\"schedulerName\":\"custom-scheduler\"}}'"
echo "  3. Check scheduler logs: kubectl logs -f deployment/custom-scheduler"

