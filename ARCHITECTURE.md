# System Architecture: Dispatcher & Scheduler Integration

## Overview

This system has **two separate but complementary components**:

1. **Dispatcher** - HTTP proxy/gateway for routing requests (application layer)
2. **Scheduler** - Kubernetes scheduler for pod placement (infrastructure layer)

They operate at **different layers** but work together to create a carbon-aware system.

## Component Roles

### 1. Dispatcher (`dispatcher/index.js`)

**Purpose**: HTTP request routing/gateway

**What it does**:
- Receives HTTP requests from frontend
- Routes requests to backend services based on `service` query parameter
- Acts as a reverse proxy/gateway

**Code Flow**:
```javascript
Frontend Request → Dispatcher (/proxy?service=my-node-service)
                  ↓
           Proxy Middleware
                  ↓
           Routes to: http://my-node-service:3000
```

**Key Code**:
```javascript
function targetForRequest(req) {
  const service = req.query.service;  // e.g., "my-node-service"
  return `http://${service}:${port}`;
}
```

### 2. Scheduler (`scheduler/main.go`)

**Purpose**: Kubernetes pod placement decision maker

**What it does**:
- Watches for unscheduled pods
- Decides **which node** a pod should run on
- Uses carbon intensity data to select the "greenest" node

**Code Flow**:
```
Pod Created → Scheduler watches for unscheduled pods
              ↓
         Checks: Ready? Resources? Carbon intensity?
              ↓
         Selects best node (lowest carbon)
              ↓
         Binds pod to node
```

**Key Code**:
```go
// Watch for unscheduled pods
watchlist := cache.NewListWatchFromClient(..., 
    fields.OneTermEqualSelector("spec.nodeName", ""))

// When pod detected:
nodeName := findBestNodeForPod(pod, clientset)  // Carbon-aware decision
schedulePodToNode(pod, nodeName, clientset)    // Bind to node
```

## How They Work Together

### The Connection Point

The dispatcher **uses** the scheduler when it's deployed:

```yaml
# dispatcher/k8s.yaml
spec:
  template:
    spec:
      schedulerName: custom-scheduler  # ← Uses our scheduler!
```

### Complete Flow

```
┌─────────────┐
│  Frontend   │
└──────┬──────┘
       │ HTTP Request: /proxy?service=my-node-service
       ↓
┌─────────────────────────────────────────────────────────┐
│  Kubernetes Cluster                                     │
│                                                         │
│  ┌──────────────┐                                       │
│  │  Dispatcher  │ ← Scheduled by custom-scheduler      │
│  │   Pod        │   (carbon-aware placement)           │
│  └──────┬───────┘                                       │
│         │ Routes to service                             │
│         ↓                                                │
│  ┌──────────────┐                                       │
│  │ Backend      │ ← Also scheduled by custom-scheduler │
│  │ Service Pods │   (carbon-aware placement)           │
│  └──────────────┘                                       │
│                                                         │
│  ┌──────────────┐                                       │
│  │ Custom       │ Watches for pods, makes decisions    │
│  │ Scheduler    │                                       │
│  └──────────────┘                                       │
└─────────────────────────────────────────────────────────┘
```

### Step-by-Step Execution

1. **Deployment Phase**:
   ```bash
   kubectl apply -f dispatcher/k8s.yaml
   ```
   - Kubernetes creates dispatcher pod
   - Pod has `schedulerName: custom-scheduler`
   - **Scheduler** watches for this pod
   - **Scheduler** selects node based on carbon intensity
   - Pod gets scheduled to greenest node

2. **Runtime Phase**:
   ```bash
   # Frontend makes request
   GET /proxy?service=my-node-service
   ```
   - Request goes to **Dispatcher** pod
   - **Dispatcher** routes to backend service
   - Backend service pods were also scheduled by **Scheduler**

## Key Differences

| Aspect | Dispatcher | Scheduler |
|--------|-----------|-----------|
| **Layer** | Application (HTTP) | Infrastructure (Kubernetes) |
| **When Active** | Runtime (handling requests) | Deployment (placing pods) |
| **Language** | JavaScript/Node.js | Go |
| **Purpose** | Route HTTP requests | Place pods on nodes |
| **Input** | HTTP requests | Pod creation events |
| **Output** | Proxied HTTP responses | Node assignments |

## Carbon-Aware Integration

### How Carbon Awareness Works

1. **Carbon API** polls Electricity Maps API
2. **Carbon API** writes cache file
3. **Scheduler** reads cache when scheduling pods
4. **Scheduler** selects nodes in low-carbon regions
5. **Dispatcher** and **backend services** get placed on green nodes

### Example Scenario

```
1. Carbon API updates cache:
   - US-CAL-CISO: 357 g CO2/kWh (best)
   - US-TEX-ERCO: 436 g CO2/kWh
   - US-MIDW-MISO: 601 g CO2/kWh (worst)

2. Dispatcher pod created:
   - Scheduler reads cache
   - Finds nodes labeled carbon-region=US-CAL-CISO
   - Schedules dispatcher to California node (357 g CO2/kWh)

3. Backend service pod created:
   - Scheduler reads cache
   - Schedules to California node (lowest carbon)

4. Frontend makes request:
   - Goes to dispatcher (on green node)
   - Dispatcher routes to backend (on green node)
   - All traffic runs on low-carbon infrastructure
```

## Configuration

### Dispatcher Configuration

**Uses scheduler via**:
```yaml
# dispatcher/k8s.yaml
spec:
  schedulerName: custom-scheduler  # Use our scheduler
```

**Does NOT need**:
- Direct access to carbon cache
- Carbon intensity logic
- Node selection logic

### Scheduler Configuration

**Needs**:
- Access to Kubernetes API
- Access to carbon cache file
- Node labels (carbon-region)

**Does NOT need**:
- HTTP server
- Request routing logic
- Service discovery

## Why This Separation?

### Benefits

1. **Separation of Concerns**:
   - Dispatcher = application logic (routing)
   - Scheduler = infrastructure logic (placement)

2. **Independent Scaling**:
   - Dispatcher scales based on HTTP traffic
   - Scheduler runs once per cluster

3. **Different Lifecycles**:
   - Dispatcher restarts with deployments
   - Scheduler runs continuously

4. **Technology Flexibility**:
   - Dispatcher can be any language/framework
   - Scheduler uses Kubernetes APIs (Go)

## Current Limitations

1. **Backend Services**: Not all services use custom scheduler yet
   - Only dispatcher explicitly uses it
   - Other services (service-js, matrixmult-py) use default scheduler
   - **Fix**: Add `schedulerName: custom-scheduler` to their k8s.yaml

2. **No Request-Level Carbon Awareness**:
   - Dispatcher routes based on service name only
   - Doesn't consider carbon intensity per request
   - **Future**: Could add carbon-aware load balancing

## Summary

- **Dispatcher** = "Where should this HTTP request go?" (runtime routing)
- **Scheduler** = "Where should this pod run?" (deployment placement)

They work together because:
- Scheduler places dispatcher pod on green node
- Scheduler places backend pods on green nodes  
- Dispatcher routes requests between services
- All traffic runs on carbon-optimized infrastructure

The scheduler ensures **infrastructure is green**, while the dispatcher ensures **requests are routed correctly**.

