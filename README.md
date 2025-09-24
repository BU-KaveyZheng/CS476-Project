### Start Services
minikube start
minikube image build -t my-node-service:latest .
kubectl apply -f k8s.yaml

## Restart Service After Changes
minikube image build -t my-node-service:latest . (rebuild)
kubectl rollout restart deployment my-node-deployment (restart)

### Stop Services
kubectl delete -f k8s.yaml




