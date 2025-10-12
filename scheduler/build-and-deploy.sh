#!/bin/bash

echo "Building carbon-aware scheduler..."

# Build the Go binary
echo "Compiling Go binary..."
go build -o carbon-scheduler .

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    
    # Check if minikube is running
    if minikube status | grep -q "Running"; then
        echo "Minikube is running. You can now:"
        echo "1. Copy the binary to minikube: minikube cp carbon-scheduler /tmp/carbon-scheduler"
        echo "2. Or deploy using kubectl apply -f k8s.yaml (if you have the image built)"
    else
        echo "Minikube is not running. To start it:"
        echo "minikube start"
        echo ""
        echo "Then you can deploy with:"
        echo "kubectl apply -f k8s.yaml"
    fi
else
    echo "❌ Build failed!"
    exit 1
fi
