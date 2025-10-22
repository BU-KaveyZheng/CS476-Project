# 🌱 Carbon-Aware Kubernetes Custom Dispatcher & Scheduler

### ✅ Prerequisites
- Docker Desktop open and running
- Minikube installed and running (via `minikube start`)

### 📦 Deployment

1. **Build and deploy all services:**
```bash
   ./start.sh
```
   This script will:
   - Build Docker images in Minikube for all services
   - Deploy them to your local Minikube cluster
   - Start the frontend application

2. **Get the dispatcher service URL:**
```bash
   minikube service dispatcher --url
```

3. **Connect the frontend:**
   - Copy the URL from step 2
   - Paste it into the input field on the frontend interface

To rebuild and redeploy after making changes, simply run `./start.sh` again. 🔄