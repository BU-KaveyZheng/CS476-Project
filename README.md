# Carbon-Aware Kubernetes Scheduler

A custom Kubernetes scheduler that optimizes pod placement based on real-time carbon intensity data from the Electricity Maps API, reducing carbon emissions by scheduling workloads to regions with lower carbon intensity.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Components](#components)
- [Experiments & Testing](#experiments--testing)
- [Documentation](#documentation)

## Overview

This project implements a carbon-aware Kubernetes scheduler that:

- **Monitors Carbon Intensity**: Polls Electricity Maps API for real-time carbon intensity data across multiple regions
- **Optimizes Scheduling**: Selects nodes in regions with lowest carbon intensity (g CO2/kWh)
- **Respects Constraints**: Handles resource availability, node readiness, and taints
- **Simulates Performance**: Includes comprehensive simulation tools to evaluate carbon reduction

### Key Features

✅ **Real-Time Carbon Data**: Integrates with Electricity Maps API for accurate carbon intensity  
✅ **Resource-Aware**: Checks CPU/memory availability before scheduling  
✅ **Global Regions**: Supports US and international regions with diverse energy mixes  
✅ **Comprehensive Metrics**: Tracks carbon reduction, latency, throughput, and utilization  
✅ **Simulation Tools**: Evaluate scheduling strategies without deploying to Kubernetes  

## Architecture

### System Components

```
┌─────────────────┐
│  Carbon API     │  Polls Electricity Maps API
│  (Python)       │  Writes to shared cache
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Carbon Cache   │  JSON file (shared storage)
│  (JSON)         │  Contains carbon intensity + TTL
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Custom         │  Reads cache, schedules pods
│  Scheduler      │  Optimizes for carbon intensity
│  (Go)           │
└─────────────────┘
```

### How It Works

1. **Carbon API Poller** (Python):
   - Polls Electricity Maps API every 5 minutes
   - Fetches carbon intensity for configured zones
   - Writes data to shared cache (`carbon_cache.json`)
   - Includes timestamp and TTL for freshness

2. **Custom Scheduler** (Go):
   - Watches for unscheduled pods
   - Reads carbon cache
   - Filters nodes (readiness, taints, resources)
   - Scores nodes by carbon intensity
   - Binds pod to lowest-carbon node

3. **Dispatcher** (Node.js):
   - Routes HTTP requests to Kubernetes Services
   - Services handle pod selection (round-robin)
   - Works independently of scheduler

## Quick Start

### Prerequisites

- Kubernetes cluster (Minikube recommended)
- Go 1.23+
- Python 3.8+
- Docker
- Electricity Maps API key

### Setup

1. **Get API Key**:
   ```bash
   # Sign up at https://www.electricitymaps.com/
   # Get your API key
   export ELECTRICITY_MAPS_API_KEY="your-api-key"
   ```

2. **Configure Carbon API**:
   ```bash
   cd carbon-api
   cp env.example .env
   # Edit .env with your API key
   ```

3. **Deploy Carbon API**:
   ```bash
   # Update secret with your API key
   kubectl create secret generic carbon-api-secret \
     --from-literal=ELECTRICITY_MAPS_API_KEY=$ELECTRICITY_MAPS_API_KEY \
     --dry-run=client -o yaml | kubectl apply -f -
   
   kubectl apply -f carbon-api/k8s.yaml
   ```

4. **Deploy Custom Scheduler**:
   ```bash
   kubectl apply -f scheduler/k8s.yaml
   ```

5. **Label Nodes**:
   ```bash
   kubectl label node <node-name> carbon-region=US-CAL-CISO
   kubectl label node <node-name> carbon-region=US-NY-NYIS
   ```

6. **Test Scheduling**:
   ```bash
   kubectl run test-pod --image=nginx --scheduler-name=custom-scheduler
   ```

## Components

### Carbon API (`carbon-api/`)

Python service that polls Electricity Maps API and writes carbon intensity data to a shared cache.

**Key Files**:
- `carbon_poller.py`: Main polling script
- `k8s.yaml`: Kubernetes deployment manifests
- `requirements.txt`: Python dependencies

**Configuration**:
- `POLL_INTERVAL_MINUTES`: How often to poll API (default: 5)
- `CACHE_TTL_MINUTES`: Cache expiration time (default: 10)
- `ZONES`: Comma-separated list of Electricity Maps zones

**See**: `carbon-api/README.md` for detailed documentation

### Custom Scheduler (`scheduler/`)

Go-based Kubernetes scheduler that reads carbon cache and schedules pods to lowest-carbon nodes.

**Key Files**:
- `main.go`: Scheduler implementation
- `k8s.yaml`: Kubernetes deployment manifests
- `Dockerfile`: Container image build

**Scheduling Policy**:
1. Filter nodes (readiness, taints, resources)
2. Score by carbon intensity (lowest = best)
3. Select best node
4. Bind pod

**See**: `scheduler/SCHEDULING_POLICY.md` for detailed policy documentation

### Simulator (`simulator/`)

Comprehensive simulation tool to evaluate carbon-aware scheduling vs other strategies.

**Key Files**:
- `enhanced_simulate.go`: Enhanced simulator with metrics
- `simulate.go`: Original simple simulator
- `SIMULATION_EXPERIMENT.md`: Detailed experiment documentation

**Usage**:
```bash
cd simulator
go run enhanced_simulate.go ../cache/carbon_cache.json 0.5 15.0 0.8
```

**See**: `simulator/SIMULATION_EXPERIMENT.md` for detailed documentation

## Experiments & Testing

### Main Experiment: Carbon-Aware vs Default Scheduling

**Script**: `test-show-difference.sh`

Demonstrates carbon reduction by comparing carbon-aware scheduling to forced-distribution default scheduling.

**Setup**:
- 2 nodes: NY (low carbon) and California (higher carbon)
- Creates pods with both schedulers
- Measures carbon intensity difference

**See**: `EXPERIMENT_DETAILS.md` for comprehensive documentation

### Edge Case Testing

**Script**: `test-edge-cases.sh`

Tests various edge cases:
- Resource constraints
- Missing labels
- Stale cache
- High load scenarios

**See**: `EDGE_CASES.md` for detailed scenarios

### NY Busy → California Fallback

**Script**: `test-ny-busy-fallback.sh`

Tests resource-aware fallback:
- Fills NY node (low carbon) with pods
- Attempts to schedule new pod
- Verifies fallback to California (higher carbon)

**See**: `NY_BUSY_FALLBACK_EXPERIMENT.md` for detailed documentation

### Simulation Experiments

**Enhanced Simulator**: `simulator/enhanced_simulate.go`

Comprehensive simulation with:
- 20+ global regions (25-900 g CO2/kWh range)
- 5 scheduling strategies
- Real-world job patterns (compute-intensive, I/O-bound)
- Comprehensive metrics (carbon, latency, throughput)

**See**: `simulator/SIMULATION_EXPERIMENT.md` for detailed documentation

## Documentation

### Core Documentation

- **`ARCHITECTURE.md`**: System architecture and component interactions
- **`SCHEDULING_POLICY.md`**: Detailed scheduling policy explanation
- **`RESOURCE_HANDLING.md`**: How resource requests are handled
- **`NODE_AVAILABILITY.md`**: How node availability is determined

### Experiment Documentation

- **`EXPERIMENT_DETAILS.md`**: Main carbon-aware vs default experiment
- **`NY_BUSY_FALLBACK_EXPERIMENT.md`**: Resource constraint fallback experiment
- **`simulator/SIMULATION_EXPERIMENT.md`**: Comprehensive simulation experiment

### Component Documentation

- **`carbon-api/README.md`**: Carbon API poller documentation
- **`scheduler/SCHEDULING_POLICY.md`**: Scheduler policy details
- **`simulator/README_ENHANCED.md`**: Enhanced simulator usage

### Testing Documentation

- **`TESTING.md`**: Testing guide for all components
- **`EDGE_CASES.md`**: Edge case testing scenarios
- **`METRICS_ANALYSIS.md`**: Metrics interpretation guide

### Clarification Documents

- **`DISPATCHER_ROUTING.md`**: How dispatcher routes requests
- **`CLARIFICATION.md`**: Roles of scheduler, dispatcher, and services
- **`KUBERNETES_NODES.md`**: What Kubernetes nodes are
- **`BUSY_NODES.md`**: What happens when nodes are busy
- **`WHY_FORCE_DISTRIBUTION.md`**: Why default scheduler uses forced distribution

## Key Metrics

### Carbon Metrics

- **Average Carbon Intensity**: Mean carbon intensity across scheduled pods
- **Carbon Reduction**: Percentage reduction vs worst-case scheduler
- **Total Carbon Saved**: Absolute carbon savings (g CO2/kWh)

### Performance Metrics

- **Average Latency**: Time from pod creation to start
- **P95 Latency**: 95th percentile latency
- **Average Turnaround**: Time from creation to completion
- **Throughput**: Pods scheduled per hour

### Resource Metrics

- **Node Utilization**: Average CPU/memory utilization
- **Queue Length**: Jobs waiting per node
- **Success Rate**: Percentage of pods successfully scheduled

## Expected Results

### Real-World Deployment

- **Carbon Reduction**: 5-15% vs default scheduling
- **Latency Impact**: Minimal (< 5 seconds)
- **Throughput**: Similar to default scheduler

### Simulation (High Load)

- **Carbon Reduction**: 8-12% vs worst-case scheduler
- **Average Carbon**: 350-400 g CO2/kWh (carbon-aware)
- **Worst-Case Carbon**: 420-450 g CO2/kWh
- **Latency**: 30-50 minutes (due to resource constraints)

## Troubleshooting

### Scheduler Not Scheduling Pods

1. Check scheduler is running: `kubectl get pods -l app=custom-scheduler`
2. Check scheduler logs: `kubectl logs -l app=custom-scheduler`
3. Verify node labels: `kubectl get nodes --show-labels`
4. Check carbon cache: `kubectl exec -it <carbon-api-pod> -- cat /cache/carbon_cache.json`

### Carbon API Not Fetching Data

1. Check API key: `kubectl get secret carbon-api-secret -o yaml`
2. Check API logs: `kubectl logs -l app=carbon-api`
3. Verify API key is valid: Test with `curl`

### Pods Stuck in Pending

1. Check node resources: `kubectl describe node <node-name>`
2. Check node readiness: `kubectl get nodes`
3. Check taints: `kubectl describe node <node-name> | grep Taints`

## Contributing

This is a research project for demonstrating carbon-aware scheduling in Kubernetes.

## License

[Add your license here]

## References

- [Electricity Maps API](https://www.electricitymaps.com/)
- [Kubernetes Scheduler Extensions](https://kubernetes.io/docs/concepts/scheduling-eviction/scheduling-framework/)
- [Carbon-Aware Computing](https://github.com/Green-Software-Foundation)
