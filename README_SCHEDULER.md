# Carbon-Aware Kubernetes Scheduler

A production-ready Kubernetes scheduler that makes pod scheduling decisions based on real-time carbon intensity data from the Electricity Maps API. This scheduler routes workloads to nodes with the lowest carbon footprint, enabling carbon-aware distributed systems.

## 🌱 Overview

This project implements a custom Kubernetes scheduler that:
- Retrieves **real-time carbon intensity data** from Electricity Maps API
- Schedules pods to nodes in zones with the **lowest carbon emissions**
- Gracefully falls back to standard scheduling if carbon data is unavailable
- Supports multiple geographic zones and cloud regions
- Integrates seamlessly with existing Kubernetes clusters

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                      │
│                                                          │
│  ┌──────────────┐                                       │
│  │ Unscheduled  │                                       │
│  │     Pod      │                                       │
│  └──────┬───────┘                                       │
│         │                                               │
│         v                                               │
│  ┌──────────────────────────────────┐                  │
│  │  Carbon-Aware Scheduler          │                  │
│  │  ┌────────────────────────────┐  │                  │
│  │  │  1. Detect unscheduled pod │  │                  │
│  │  │  2. Get carbon intensity   │◄─┼──── Electricity │
│  │  │     for each node zone     │  │     Maps API    │
│  │  │  3. Select lowest carbon   │  │                  │
│  │  │  4. Bind pod to node       │  │                  │
│  │  └────────────────────────────┘  │                  │
│  └──────────┬───────────────────────┘                  │
│             │                                           │
│             v                                           │
│  ┌──────────────────────┐                              │
│  │  Pod running on      │                              │
│  │  lowest-carbon node  │                              │
│  └──────────────────────┘                              │
└─────────────────────────────────────────────────────────┘
```

## ✨ Features

- **Real-Time Carbon Data**: Fetches live carbon intensity from Electricity Maps
- **Intelligent Scheduling**: Routes workloads to cleanest energy zones
- **Fallback Mechanism**: Works even when API is unavailable
- **Zone-Aware**: Supports node labeling with geographic zones
- **Production-Ready**: Includes RBAC, secrets management, error handling
- **Go Implementation**: No Python dependencies for the scheduler
- **API Compatibility**: Free tier API support with graceful degradation

## 📋 Prerequisites

- Kubernetes cluster (minikube, GKE, EKS, AKS, etc.)
- Docker
- kubectl configured to access your cluster
- Electricity Maps API key ([Get one here](https://api-portal.electricitymaps.com/))

## 🚀 Quick Start

### 1. Get API Key

1. Sign up at [Electricity Maps API Portal](https://api-portal.electricitymaps.com/)
2. Select your zone (e.g., New York ISO)
3. Copy your API key

### 2. Configure the Scheduler

Update the zone in `scheduler/k8s.yaml`:

```yaml
env:
- name: DEFAULT_CARBON_ZONE
  value: "US-NY-NYIS"  # Replace with your zone
```

Encode your API key:

```bash
echo -n "your_api_key_here" | base64
```

Update the secret in `scheduler/k8s.yaml`:

```yaml
data:
  api-key: YOUR_BASE64_ENCODED_KEY
```

### 3. Build and Deploy

```bash
# Navigate to scheduler directory
cd scheduler

# Build the Docker image in minikube
eval $(minikube docker-env)
docker build -t carbon-scheduler .

# Deploy to Kubernetes
kubectl apply -f k8s.yaml

# Verify it's running
kubectl get pods -n kube-system | grep carbon
kubectl logs -n kube-system deployment/carbon-aware-scheduler
```

Expected output:
```
Connected to Kubernetes API
Carbon intensity client initialized successfully
```

### 4. Test the Scheduler

Create a test pod using the carbon-aware scheduler:

```bash
kubectl run test-pod --image=nginx --restart=Never \
  --overrides='{"spec":{"schedulerName":"carbon-aware-scheduler"}}'
```

Check the scheduler logs:

```bash
kubectl logs -n kube-system deployment/carbon-aware-scheduler --tail=20
```

Expected output:
```
Unscheduled pod detected: default/test-pod
Selected node minikube in zone US-NY-NYIS with carbon intensity 300.00 gCO₂eq/kWh
Pod test-pod scheduled to minikube
```

## 📁 Project Structure

```
CS476-Project/
├── scheduler/
│   ├── main.go                 # Kubernetes scheduler implementation
│   ├── carbon_client.go        # Electricity Maps API client (Go)
│   ├── Dockerfile              # Container build configuration
│   ├── k8s.yaml                # Kubernetes deployment manifests
│   ├── go.mod                  # Go module dependencies
│   └── build-and-deploy.sh     # Helper build script
├── carbon_intensity_api.py     # Python API client (testing)
├── example_usage.py            # Python examples
├── requirements.txt            # Python dependencies
└── README_CARBON_API.md        # Python client documentation
```

## 🔧 Configuration

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `ELECTRICITY_MAPS_API_KEY` | Your API key (from secret) | `acxh6ftJvjTYpUZvbBKx` |
| `DEFAULT_CARBON_ZONE` | Default zone for nodes without labels | `US-NY-NYIS` |

### Node Labels

You can label nodes with specific zones:

```bash
kubectl label node node1 carbon-zone=US-NY-NYIS
kubectl label node node2 carbon-zone=US-CA-CISO
```

The scheduler will automatically use these labels to fetch appropriate carbon data.

### Supported Zones

Common zone identifiers:
- `US-NY-NYIS` - New York ISO
- `US-CA-CISO` - California ISO
- `US-MISO` - Midwest ISO
- `DE` - Germany
- `FR` - France
- `GB` - Great Britain

[Full zone list](https://api-portal.electricitymaps.com/zones)

## 💻 Development

### Building Locally

```bash
cd scheduler
go build -o carbon-scheduler .
./carbon-scheduler
```

### Running Tests

Test the Python API client:

```bash
export ELECTRICITY_MAPS_API_KEY="your_key"
python3 carbon_intensity_api.py --zone US-NY-NYIS --type latest
```

### Rebuilding and Redeploying

```bash
cd scheduler
eval $(minikube docker-env)
docker build -t carbon-scheduler .
kubectl rollout restart deployment carbon-aware-scheduler -n kube-system
```

## 🔍 How It Works

1. **Pod Detection**: The scheduler watches for unscheduled pods with `schedulerName: carbon-aware-scheduler`

2. **Carbon Intensity Lookup**: For each available node, it:
   - Extracts the zone from node labels (or uses default)
   - Queries Electricity Maps API for current carbon intensity
   - Handles API failures with fallback values

3. **Node Selection**: Sorts nodes by carbon intensity (lowest first)

4. **Pod Binding**: Binds the pod to the node with lowest carbon footprint

5. **Logging**: Records the decision with carbon intensity value

## 📊 Monitoring

### View Scheduler Logs

```bash
kubectl logs -n kube-system deployment/carbon-aware-scheduler -f
```

### Check Scheduled Pods

```bash
kubectl get pods -o wide
```

### View Carbon Decisions

Look for log entries like:
```
Selected node minikube in zone US-NY-NYIS with carbon intensity 300.00 gCO₂eq/kWh
```

## 🛠️ Troubleshooting

### Scheduler Not Starting

```bash
# Check pod status
kubectl get pods -n kube-system | grep carbon

# View detailed events
kubectl describe pod -n kube-system <pod-name>

# Check logs
kubectl logs -n kube-system <pod-name>
```

### API Authentication Errors

```
Error: API request failed with status 401: Request unauthorized
```

**Solutions**:
- Verify API key is correct
- Check zone access (free tier has limited zones)
- Ensure secret is properly base64 encoded

### Pods Not Being Scheduled

**Check**:
1. Pod has `schedulerName: carbon-aware-scheduler` in spec
2. Scheduler is running: `kubectl get pods -n kube-system`
3. Scheduler logs show pod detection

### API Rate Limiting

The scheduler caches carbon intensity data internally. If you hit rate limits:
- Reduce scheduling frequency
- Upgrade API tier
- Implement longer caching (modify `carbon_client.go`)

## 🌍 Real-World Use Cases

### Multi-Region Cloud Deployments

Deploy workloads to regions with cleanest energy:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: batch-job
spec:
  schedulerName: carbon-aware-scheduler
  containers:
  - name: worker
    image: my-batch-job
```

### Time-Shifting Workloads

Schedule non-urgent tasks during low-carbon periods by monitoring intensity over time.

### Carbon Reporting

Track carbon intensity of scheduled workloads for sustainability reporting.

## 🤝 Contributing

This is a CS476 course project. To contribute:

1. Create a feature branch
2. Make your changes
3. Test thoroughly
4. Submit a pull request

## 📝 API Documentation

### Go Carbon Client

```go
// Initialize client
client, err := NewCarbonClient()

// Get latest carbon intensity
data, err := client.GetLatestCarbonIntensity("US-NY-NYIS")

// Get average over time
avg, err := client.GetAverageCarbonIntensity("US-NY-NYIS", 1) // Last hour
```

### Python Testing Client

See [README_CARBON_API.md](README_CARBON_API.md) for Python client documentation.

## 📚 References

- [Electricity Maps API Documentation](https://api-portal.electricitymaps.com/)
- [Kubernetes Scheduler Documentation](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/)
- [Carbon-Aware Computing](https://learn.greensoftware.foundation/)

## 📄 License

This project is part of the CS476 course at Boston University.

## 🙏 Acknowledgments

- Electricity Maps for providing carbon intensity data
- CS476 course staff and collaborators
- Kubernetes community for scheduler documentation

---

**Current Status**: ✅ Deployed and operational with US-NY-NYIS zone, achieving carbon-aware scheduling with real-time data (300 gCO₂eq/kWh)
