# 🌱 Carbon-Aware Kubernetes Custom Dispatcher & Scheduler

### ✅ Prerequisites
- Docker Desktop installed and running
- Minikube installed and running (via `minikube start`)
- Make a `.edu` account for `https://www.electricitymaps.com/`
   -  In terminal
      ```bash
      kubectl create secret generic electricity-maps-secret --from-literal=api-key=YOUR_API_KEY
      ```

### 📦 Deployment

1. **Build and deploy all services:**
```bash
   ./start.sh
```
   This script will:
   - Build Docker images in Minikube for all services
   - Deploy them to your local Minikube cluster
   - Start the frontend application

2. **Get the dispatcher service URL:** *(in a separate terminal)*
```bash
   minikube service dispatcher --url
```

3. **Connect the frontend:**
   - Copy the URL from step 2
   - Paste it into the input field on the frontend interface

4. **View dispatcher logs** *(in a separate terminal)*
```bash
   kubectl logs -f deployment/dispatcher
```
   - This allows you to view incoming requests and dispatcher logic for critical & non-critical workloads made from the frontend

5. **Clean Up**
```bash
   ./cleanup-regions.sh
   kubectl delete -f ./service-js/k8s.yaml
   kubectl delete -f ./dispatcher/k8s.yaml
```