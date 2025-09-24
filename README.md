### Start Services
```bash
minikube start
minikube image build -t my-node-service:latest .
kubectl apply -f k8s.yaml
```

### Restart Service After Changes
```bash
minikube image build -t my-node-service:latest . (rebuild)
kubectl rollout restart deployment my-node-deployment (restart)
```

### Stop Services
```bash
kubectl delete -f k8s.yaml
```




