#!/bin/bash

# ============================================================================
# SETUP INSTRUCTIONS - READ BEFORE RUNNING
# ============================================================================
# 
# This script requires the Electricity Maps API key to be set up before running.
# 
# Option 1: Using Kubernetes Secret (Recommended for production)
#   kubectl create secret generic electricity-maps-secret \
#     --from-literal=api-key=YOUR_API_KEY_HERE
# 
# Option 2: Using .env file (For local development)
#   Create a .env file in the dispatcher/ directory with:
#   ELECTRICITY_MAPS_API_KEY=your-api-key-here
#   Note: The .env file is gitignored and won't be committed.
# 
# Option 3: Direct environment variable (For testing)
#   Edit dispatcher/k8s.yaml and uncomment the direct value option,
#   then set your API key there (NOT recommended for production).
# 
# Get your API key from: https://www.electricitymaps.com/
# ============================================================================

# Build Docker images
echo "🚀 Building and deploying services to minikube..."
minikube image build -t custom-scheduler:latest ./scheduler
minikube image build -t my-node-service:latest ./service-js
minikube image build -t dispatcher:latest ./dispatcher

# Delete old matrix-mult-service if it exists (to avoid conflicts)
echo "🧹 Cleaning up old matrix-mult-service..."
kubectl delete -f ./matrixmult-py/k8s.yaml 2>/dev/null || echo "  (No old service to delete)"

# Deploy region-specific matrix-mult-service instances
REGIONS=("US-NY-NYIS" "US-MIDA-PJM" "US-NW-PACW" "US-CAL-CISO")

echo "🌍 Building and deploying matrix-mult-service for each region..."
for region in "${REGIONS[@]}"; do
  # Convert region to lowercase for Docker image name (Docker requires lowercase)
  region_lower=$(echo "$region" | tr '[:upper:]' '[:lower:]')
  
  echo "  Building image for region: $region (image: matrix-mult-service-$region_lower:latest)"
  minikube image build -t matrix-mult-service-$region_lower:latest ./matrixmult-py
  
  echo "  Deploying service for region: $region"
  # Replace {{REGION}} with actual region (uppercase for labels), {{REGION_LOWER}} with lowercase (for names)
  sed "s/{{REGION}}/$region/g" ./matrixmult-py/k8s-template.yaml | \
    sed "s/{{REGION_LOWER}}/$region_lower/g" | \
    kubectl apply -f -
done

# Apply Kubernetes manifests for other services
kubectl apply -f ./scheduler/k8s.yaml
kubectl apply -f ./service-js/k8s.yaml
kubectl apply -f ./dispatcher/k8s.yaml

# Start frontend dev server
echo "🎉 Deployment complete! Starting frontend dev server..."
cd frontend
npm run dev

# URL for Dispatcher
# minikube service dispatcher --url

# Stop and Delete Services
# kubectl delete -f ./service-js/k8s.yaml
# kubectl delete -f ./matrixmult-py/k8s.yaml
# kubectl delete -f ./dispatcher/k8s.yaml
# ./cleanup-regions.sh

# View Container STD Output 
# kubectl get pods 
# kubectl logs -f NAME

# Rebuild
# kubectl get svc
# minikube image build -t my-node-service:latest ./service-js
# minikube image build -t dispatcher:latest ./dispatcher

# Restart
# kubectl get deployments
# kubectl rollout restart deployment my-node-deployment 
# kubectl rollout restart deployment dispatcher