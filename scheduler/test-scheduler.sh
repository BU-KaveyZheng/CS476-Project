#!/bin/bash
# Test script for the Carbon-Aware Scheduler

cd "$(dirname "$0")"

echo "🧪 Testing Carbon-Aware Scheduler"
echo "================================="
echo ""

# Check if cache file exists
CACHE_FILE="../cache/carbon_cache.json"
if [ ! -f "$CACHE_FILE" ]; then
    echo "❌ ERROR: Cache file not found at $CACHE_FILE"
    echo ""
    echo "Please run the Carbon API first to generate the cache file:"
    echo "  cd ../carbon-api"
    echo "  ./test-api.sh"
    exit 1
fi

echo "✓ Cache file found: $CACHE_FILE"
echo ""

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo "❌ ERROR: Go is not installed"
    echo "Please install Go: https://golang.org/dl/"
    exit 1
fi

echo "✓ Go is installed: $(go version)"
echo ""

# Build the scheduler
echo "🔨 Building scheduler..."
if go build -o custom-scheduler main.go; then
    echo "✓ Build successful"
else
    echo "❌ Build failed"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing Cache Reading"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test cache reading
export CACHE_FILE="$CACHE_FILE"
go run test-cache.go

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Scheduler Binary Created"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✓ Scheduler binary: ./custom-scheduler"
echo ""
echo "To test with Kubernetes:"
echo "  1. Build Docker image:"
echo "     eval \$(minikube docker-env)"
echo "     docker build -t custom-scheduler:latest ."
echo ""
echo "  2. Deploy to Kubernetes:"
echo "     kubectl apply -f k8s.yaml"
echo ""
echo "  3. Create a test pod:"
echo "     kubectl run test-pod --image=nginx --restart=Never \\"
echo "       --overrides='{\"spec\":{\"schedulerName\":\"custom-scheduler\"}}'"
echo ""
echo "  4. Check scheduler logs:"
echo "     kubectl logs -f deployment/custom-scheduler"

