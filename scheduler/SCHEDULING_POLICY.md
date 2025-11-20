# Carbon-Aware Scheduling Policy

## Overview

The carbon-aware scheduler makes scheduling decisions based on real-time carbon intensity data from the Electricity Maps API. It selects nodes in regions with the **lowest carbon intensity** (g CO2/kWh) to minimize the carbon footprint of workloads.

## Scheduling Algorithm

### Step 1: Filter Available Nodes

The scheduler filters nodes based on Kubernetes constraints:

1. **Node Readiness**: Only considers nodes with `NodeReady` condition = `True`
2. **Taints**: Skips nodes with `NoSchedule` taints
3. **Resource Availability**: ✅ **NEW** Checks if node has enough CPU and memory
   - Calculates available resources = allocatable - allocated
   - Compares with pod resource requests
   - Filters out nodes that can't fit the pod
4. **Availability**: Only considers schedulable nodes that pass all checks

### Step 2: Carbon-Aware Scoring (if enabled)

When `CARBON_AWARE_MODE=true` (default):

1. **Read Carbon Cache**: Loads carbon intensity data from cache file
2. **Map Nodes to Regions**: 
   - Checks node labels in priority order:
     - `carbon-region` (primary)
     - `region` (fallback)
     - `topology.kubernetes.io/zone` (secondary fallback)
3. **Score Each Node**:
   - Looks up carbon intensity (g CO2/kWh) for the node's region
   - Uses `carbonIntensity` field (Electricity Maps) or `moer` (WattimeAPI fallback)
   - Default score: 1000 g CO2/kWh if region not found in cache
4. **Select Best Node**: 
   - Chooses the node with the **lowest carbon intensity score**
   - Lower score = lower carbon emissions = better choice

### Step 3: Fallback Behavior

- **Cache unavailable**: Falls back to first available node
- **Region not found**: Uses default high score (1000), effectively deprioritizing that node
- **Non-carbon-aware mode**: Simply selects first available node (round-robin)

## Example Decision Flow

```
Pod arrives → Filter nodes:
              - Ready?
              - No NoSchedule taints?
              - Has enough CPU/memory? ✅ NEW
              ↓
         Carbon-aware mode?
              ↓
         YES → Read cache → Map nodes to regions
              ↓
         Score nodes by carbon intensity
              ↓
         Select node with LOWEST carbon intensity
              ↓
         Schedule pod to that node
```

## Example Scenario

**Available Nodes:**
- `node-california` → Label: `carbon-region=US-CAL-CISO` → Carbon: 357 g CO2/kWh
- `node-texas` → Label: `carbon-region=US-TEX-ERCO` → Carbon: 436 g CO2/kWh  
- `node-midwest` → Label: `carbon-region=US-MIDW-MISO` → Carbon: 601 g CO2/kWh

**Decision:** Schedule to `node-california` (lowest carbon: 357 g CO2/kWh)

## Configuration

### Environment Variables

- `CARBON_AWARE_MODE`: Enable/disable carbon-aware scheduling (default: `true`)
- `CACHE_FILE`: Path to carbon cache file (default: `/cache/carbon_cache.json`)

### Node Labels Required

Nodes must be labeled with their region:

```bash
kubectl label nodes <node-name> carbon-region=US-CAL-CISO
kubectl label nodes <node-name> carbon-region=US-TEX-ERCO
```

## Comparison: Carbon-Aware vs Non-Carbon-Aware

### Carbon-Aware Mode (`CARBON_AWARE_MODE=true`)
- ✅ Considers carbon intensity when scheduling
- ✅ Minimizes carbon footprint
- ✅ Prioritizes green energy regions
- ⚠️ Requires cache file and node labels

### Non-Carbon-Aware Mode (`CARBON_AWARE_MODE=false`)
- ✅ Simple round-robin scheduling
- ✅ No dependencies on cache
- ❌ Ignores carbon intensity
- ❌ May schedule to high-carbon regions

## Carbon Savings

Based on simulation results, carbon-aware scheduling typically achieves:
- **20-50% reduction** in carbon emissions
- By routing workloads to regions with lower carbon intensity
- Especially effective when there's significant variation between regions

## Limitations

1. **Cache Dependency**: Requires carbon cache file to be up-to-date
2. **Node Labels**: Nodes must be properly labeled with regions
3. **Region Mapping**: Only works if node regions match Electricity Maps zone codes
4. ✅ **Resource Awareness**: Now checks CPU/memory availability before scheduling
5. **No Load Balancing**: Always selects lowest carbon among available nodes (doesn't distribute load)
6. **No Node Selectors/Affinity**: Doesn't check pod `nodeSelector` or affinity rules yet

## Future Enhancements

Potential improvements:
- **Hybrid Scoring**: Combine carbon intensity with resource availability
- **Load Balancing**: Distribute pods across low-carbon nodes
- **Forecast-Based**: Use carbon intensity forecasts for better decisions
- **Cost-Aware**: Consider both carbon and cost factors
- **Resource Constraints**: Factor in CPU/memory availability

