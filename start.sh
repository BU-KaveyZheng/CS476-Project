#!/bin/bash

# Build Docker images
echo "🚀 Building and deploying services to minikube..."
minikube image build -t my-node-service:latest ./service-js
minikube image build -t matrix-mult-service:latest ./matrixmult-py
minikube image build -t dispatcher:latest ./dispatcher

# Apply Kubernetes manifests
kubectl apply -f ./service-js/k8s.yaml
kubectl apply -f ./matrixmult-py/k8s.yaml
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