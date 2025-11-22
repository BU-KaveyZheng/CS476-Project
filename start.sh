#!/bin/bash

# Build Docker images
echo "🚀 Building and deploying services to minikube..."
minikube image build -t my-node-service:latest ./service-js
# minikube image build -t matrix-mult-service:latest ./matrixmult-py
minikube image build -t dispatcher:latest ./dispatcher

REGIONS=("us-east" "us-west" "eu-central" "sa-south")
for region in "${REGIONS[@]}"; do
  minikube image build -t matrix-mult-service-$region:latest ./matrixmult-py
  sed "s/{{REGION}}/$region/g" ./matrixmult-py/k8s-template.yaml | kubectl apply -f -
done

# Apply Kubernetes manifests
kubectl apply -f ./service-js/k8s.yaml
# kubectl apply -f ./matrixmult-py/k8s.yaml
kubectl apply -f ./dispatcher/k8s.yaml

# Start frontend dev server
echo "🎉 Deployment complete! Starting frontend dev server..."
cd frontend
npm run dev

# URL for Dispatcher
# minikube service dispatcher --url

# Stop and Delete Services
# for region in "${REGIONS[@]}"; do
#   kubectl delete deployment matrix-mult-$region --ignore-not-found
#   kubectl delete service matrix-mult-$region --ignore-not-found
# done

# kubectl delete -f ./service-js/k8s.yaml
# kubectl delete -f ./matrixmult-py/k8s.yaml
# kubectl delete -f ./dispatcher/k8s.yaml

# View Container STD Output 
# kubectl get pods 
# kubectl logs -f NAME

# Rebuild
# kubectl get svc
# minikube image build -t my-node-service:latest ./service-js
# minikube image build -t matrixmult-py:latest ./matrixmult-py
# minikube image build -t dispatcher:latest ./dispatcher

# Restart
# kubectl get deployments
# kubectl rollout restart deployment my-node-deployment 
# kubectl rollout restart deployment dispatcher