### Start Services
minikube start
minikube image build -t my-node-service:latest .
kubectl apply -f k8s.yaml

### Stop Services
kubectl delete -f k8s.yaml



