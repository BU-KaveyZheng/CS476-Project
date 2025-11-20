# Enhanced Carbon-Aware Scheduler Simulator

## Overview

The enhanced simulator provides comprehensive metrics for evaluating carbon-aware scheduling vs other scheduling strategies in real-world scenarios with realistic job scheduling patterns, latency tracking, and turnaround time estimation.

## Features

### ✅ Real-World Job Scheduling
- **Poisson Process Arrivals**: Realistic job arrival patterns
- **Variable Job Durations**: Normal distribution of job execution times
- **Resource Constraints**: CPU and memory requests respected
- **Queueing/Waiting**: Jobs wait when nodes are busy (realistic latency)

### ✅ Multiple Scheduler Comparison
Compares 5 scheduling strategies:
1. **Carbon-Aware**: Lowest carbon intensity
2. **Round-Robin**: Even distribution
3. **Random**: Random selection
4. **Least-Loaded**: Most available resources
5. **Highest-Carbon**: Worst case (for comparison)

### ✅ Comprehensive Metrics

**Carbon Metrics**:
- Average carbon intensity (g CO2/kWh)
- Total carbon emissions
- Carbon reduction percentage
- Carbon by region

**Performance Metrics**:
- Average latency (job creation → start)
- P95 latency (95th percentile)
- Average turnaround time (creation → completion)
- P95 turnaround time
- Throughput (jobs/hour)

**Resource Metrics**:
- Average node utilization
- Per-node utilization breakdown

**Distribution Metrics**:
- Jobs by region
- Jobs by node
- Region distribution patterns

**Reliability Metrics**:
- Total jobs submitted
- Completed jobs
- Failed jobs
- Success rate

## Usage

### Basic Usage

```bash
cd simulator
go run enhanced_simulate.go <cache_file> [duration_hours] [jobs_per_minute]
```

### Examples

```bash
# Default: 1 hour, 5 jobs/minute
go run enhanced_simulate.go test_cache.json

# 2 hours simulation, 10 jobs/minute
go run enhanced_simulate.go test_cache.json 2.0 10.0

# Quick test: 0.5 hours, 20 jobs/minute
go run enhanced_simulate.go test_cache.json 0.5 20.0
```

### Getting Cache File

```bash
# From Kubernetes pod
kubectl exec -it $(kubectl get pods -l app=carbon-api -o jsonpath='{.items[0].metadata.name}') \
  -- cat /cache/carbon_cache.json > test_cache.json

# Or use local cache
cp ../cache/carbon_cache.json test_cache.json
```

## Output Example

```
╔══════════════════════════════════════════════════════════════╗
║     Enhanced Carbon-Aware Scheduler Simulation             ║
╠══════════════════════════════════════════════════════════════╣
║  Duration: 1h0m0s                                            ║
║  Job Arrival Rate: 5.0 jobs/minute                           ║
║  Nodes: 10 across 4 regions                                  ║
╚══════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────┐
│                    SCHEDULER COMPARISON                      │
├──────────────────────────────────────────────────────────────┤
│ Scheduler      │ Jobs │ Avg Carbon │ Avg Latency │ Throughput │
├──────────────────────────────────────────────────────────────┤
│ Carbon-Aware   │  300 │    334.00  │     2.5s    │   300.0    │
│ Round-Robin    │  298 │    350.50  │     3.2s    │   298.0    │
│ Random         │  301 │    352.10  │     3.5s    │   301.0    │
│ Least-Loaded   │  299 │    351.80  │     2.8s    │   299.0    │
│ Highest-Carbon │  297 │    367.00  │     3.8s    │   297.0    │
└──────────────────────────────────────────────────────────────┘

Carbon Reduction: 9.0% vs worst-case
Average Latency: 2.5s
Throughput: 300 jobs/hour
```

## Key Metrics Explained

### Carbon Reduction
**What it shows**: Percentage reduction in carbon emissions vs worst-case scheduler

**Example**: 9.0% reduction means carbon-aware scheduler emits 9% less CO2

**Use case**: Demonstrates environmental impact improvement

### Average Latency
**What it shows**: Time from job creation to job start (scheduling delay)

**Includes**: Queueing/waiting time when nodes are busy

**Use case**: Measures scheduling responsiveness

### Turnaround Time
**What it shows**: Time from job creation to job completion

**Includes**: Latency + execution time

**Use case**: Measures end-to-end job completion time

### Throughput
**What it shows**: Jobs completed per hour

**Use case**: Measures system capacity and efficiency

### Node Utilization
**What it shows**: Percentage of node resources used

**Use case**: Measures resource efficiency

## Real-World Scenarios

### Scenario 1: Normal Load
- **Config**: 5-10 jobs/minute, 10-30 min duration
- **Tests**: Carbon optimization, normal latency, throughput

### Scenario 2: High Load
- **Config**: 20+ jobs/minute, variable duration
- **Tests**: Queueing behavior, resource constraints, fallback

### Scenario 3: Bursty Workload
- **Config**: Variable arrival rate, short durations
- **Tests**: Traffic spike handling, rapid scheduling

## Customization

Edit `SimulationConfig` in `enhanced_simulate.go`:

```go
config := SimulationConfig{
    Duration:          1 * time.Hour,
    JobArrivalRate:    5.0,            // Jobs per minute
    JobDurationMean:   10 * time.Minute,
    JobDurationStd:    5 * time.Minute,
    CPURequestMean:    0.5,            // CPU cores
    CPURequestStd:     0.3,
    MemoryRequestMean: 1.0,            // GB
    MemoryRequestStd:  0.5,
}
```

## Interpreting Results

### Good Results
- ✅ Carbon reduction > 5%
- ✅ Latency < 5 seconds
- ✅ Throughput matches arrival rate
- ✅ Success rate > 95%

### Areas for Improvement
- ⚠️ High latency: May need more nodes or better scheduling
- ⚠️ Low throughput: Resource constraints limiting capacity
- ⚠️ High failure rate: Insufficient resources

## Comparison with Original Simulator

| Feature | Original | Enhanced |
|---------|----------|----------|
| Job Arrivals | Static batch | Poisson process |
| Job Durations | Fixed | Variable (normal dist) |
| Latency Tracking | ❌ | ✅ |
| Turnaround Time | ❌ | ✅ |
| Queueing | ❌ | ✅ |
| Resource Constraints | ❌ | ✅ |
| Multiple Schedulers | 2 | 5 |
| Metrics | Basic | Comprehensive |

## Files

- **`enhanced_simulate.go`**: Main simulator code
- **`SIMULATOR_METRICS.md`**: Detailed metrics documentation
- **`README_ENHANCED.md`**: This file

## Next Steps

1. Run simulations with different configurations
2. Compare results across scenarios
3. Export results for analysis (add JSON export)
4. Visualize metrics (add chart generation)
5. Integrate with real scheduler for validation

