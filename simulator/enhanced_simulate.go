package main

import (
	"encoding/json"
	"fmt"
	"math"
	"math/rand"
	"os"
	"sort"
	"time"
)

// Enhanced simulation with comprehensive metrics

type CarbonCache struct {
	Timestamp      string            `json:"timestamp"`
	TTLMinutes     int               `json:"ttl_minutes"`
	Regions        map[string]Region `json:"regions"`
	SortedByCarbon []string          `json:"sorted_by_carbon"`
	BestRegion     string            `json:"best_region"`
	WorstRegion    string            `json:"worst_region"`
}

type Region struct {
	Zone              string  `json:"zone"`
	CarbonIntensity   float64 `json:"carbonIntensity"`
	MOER              float64 `json:"moer"`
	Datetime          string  `json:"datetime"`
	UpdatedAt         string  `json:"updatedAt"`
	CreatedAt         string  `json:"createdAt"`
	EmissionFactorType string  `json:"emissionFactorType"`
	IsEstimated       bool    `json:"isEstimated"`
	EstimationMethod  string  `json:"estimationMethod"`
	Timestamp         string  `json:"timestamp"`
}

// JobType represents different workload characteristics
type JobType int

const (
	ComputeIntensive JobType = iota // Matrix multiplication, ML training (CPU-bound, blocking)
	IOBound                         // Data processing, file operations (I/O-bound, less blocking)
	Mixed                           // Web services, APIs (mixed workload)
	Batch                           // Batch processing (long-running, blocking)
)

// Job represents a workload/job to be scheduled
type Job struct {
	ID              string
	Type            JobType
	CPURequest      float64 // CPU cores
	MemoryRequest   float64 // GB
	Duration        time.Duration // How long job runs
	BlockingTime    time.Duration // Time job blocks resources (compute phase)
	CreatedAt       time.Time
	ScheduledAt     time.Time
	StartedAt       time.Time // When job actually starts executing
	CompletedAt     time.Time
	Node            string
	Region          string
	CarbonIntensity float64
	QueueTime       time.Duration // Time waiting in queue
	Latency         time.Duration // Time from creation to start (queue + scheduling)
	TurnaroundTime  time.Duration // Time from creation to completion
	ExecutionTime   time.Duration // Actual execution time
}

// Node represents a compute node
type Node struct {
	Name            string
	Region          string
	CarbonIntensity float64
	TotalCPU        float64
	TotalMemory     float64
	AvailableCPU    float64
	AvailableMemory float64
	Jobs            []*Job
	RunningJobs     []*Job // Jobs currently executing (blocking resources)
	Queue           []*Job // Jobs waiting in queue
	Utilization     float64 // CPU utilization percentage
	QueueLength     int     // Current queue length
}

// SchedulerType represents different scheduling strategies
type SchedulerType int

const (
	CarbonAware SchedulerType = iota
	RoundRobin
	Random
	LeastLoaded
	HighestCarbon // Worst case for comparison
)

// SimulationConfig holds simulation parameters
type SimulationConfig struct {
	Duration          time.Duration
	JobArrivalRate   float64 // Jobs per minute
	JobDurationMean  time.Duration
	JobDurationStd   time.Duration
	CPURequestMean   float64
	CPURequestStd    float64
	MemoryRequestMean float64
	MemoryRequestStd  float64
	ComputeJobRatio  float64 // Ratio of compute-intensive jobs (0.0-1.0)
	NumNodes         int
	Regions          []string
}

// SimulationResults holds comprehensive metrics
type SimulationResults struct {
	SchedulerType        string
	TotalJobs            int
	CompletedJobs        int
	FailedJobs           int
	AverageCarbon        float64
	TotalCarbon          float64
	AverageLatency       time.Duration
	AverageTurnaround    time.Duration
	P95Latency           time.Duration
	P95Turnaround        time.Duration
	AverageUtilization   float64
	NodeUtilization      map[string]float64
	RegionDistribution   map[string]int
	CarbonByRegion       map[string]float64
	JobsByRegion         map[string]int
	Throughput           float64 // Jobs per hour
	CarbonReduction      float64 // Percentage vs worst case
	LatencyReduction     float64 // Percentage vs worst case
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run enhanced_simulate.go <carbon_cache.json> [duration_hours] [jobs_per_minute] [compute_job_ratio]")
		fmt.Println("Example: go run enhanced_simulate.go cache.json 1.0 5.0 0.4")
		fmt.Println("  duration_hours: Simulation duration (default: 1.0)")
		fmt.Println("  jobs_per_minute: Job arrival rate (default: 5.0)")
		fmt.Println("  compute_job_ratio: Ratio of compute-intensive jobs 0.0-1.0 (default: 0.4)")
		fmt.Println("    - 0.0 = All I/O-bound jobs (low blocking)")
		fmt.Println("    - 0.4 = Mix of compute and I/O (realistic)")
		fmt.Println("    - 1.0 = All compute-intensive (matrix mult, high blocking)")
		os.Exit(1)
	}

	cacheFile := os.Args[1]
	cache, err := readCarbonCache(cacheFile)
	if err != nil {
		fmt.Printf("Error reading cache: %v\n", err)
		os.Exit(1)
	}

	// Initialize nodes from cache
	nodes := initializeNodes(cache)
	
	// Add additional regions with varied carbon intensities for simulation
	// This helps demonstrate carbon-aware scheduling advantages
	nodes = addSimulationRegions(nodes)
	
	// Parse command-line arguments
	durationHours := 1.0
	jobArrivalRate := 5.0
	computeJobRatio := 0.4 // 40% compute-intensive jobs
	
	if len(os.Args) >= 3 {
		fmt.Sscanf(os.Args[2], "%f", &durationHours)
	}
	if len(os.Args) >= 4 {
		fmt.Sscanf(os.Args[3], "%f", &jobArrivalRate)
	}
	if len(os.Args) >= 5 {
		fmt.Sscanf(os.Args[4], "%f", &computeJobRatio)
	}
	
	// Simulation configuration
	config := SimulationConfig{
		Duration:          time.Duration(durationHours * float64(time.Hour)),
		JobArrivalRate:   jobArrivalRate,
		JobDurationMean:  20 * time.Minute,  // Average job duration
		JobDurationStd:   10 * time.Minute,
		CPURequestMean:   1.0,  // 1 CPU core average
		CPURequestStd:    0.5,
		MemoryRequestMean: 2.0,  // 2 GB average
		MemoryRequestStd:  1.0,
		ComputeJobRatio:  computeJobRatio, // Ratio of compute-intensive jobs
		NumNodes:         len(nodes),
		Regions:          getRegions(nodes),
	}

	fmt.Println("╔══════════════════════════════════════════════════════════════╗")
	fmt.Println("║     Enhanced Carbon-Aware Scheduler Simulation             ║")
	fmt.Println("╠══════════════════════════════════════════════════════════════╣")
	fmt.Printf("║  Duration: %-45s ║\n", config.Duration)
	fmt.Printf("║  Job Arrival Rate: %.1f jobs/minute                          ║\n", config.JobArrivalRate)
	fmt.Printf("║  Compute-Intensive Jobs: %.1f%%                                ║\n", config.ComputeJobRatio*100)
	fmt.Printf("║  Nodes: %d across %d regions                                  ║\n", config.NumNodes, len(config.Regions))
	fmt.Println("╚══════════════════════════════════════════════════════════════╝")
	fmt.Println()

	// Run simulations for different schedulers
	schedulers := []struct {
		name SchedulerType
		desc string
	}{
		{CarbonAware, "Carbon-Aware"},
		{RoundRobin, "Round-Robin"},
		{Random, "Random"},
		{LeastLoaded, "Least-Loaded"},
		{HighestCarbon, "Highest-Carbon (Worst Case)"},
	}

	results := make([]SimulationResults, len(schedulers))

	for i, sched := range schedulers {
		fmt.Printf("Running simulation: %s...\n", sched.desc)
		results[i] = runSimulation(nodes, config, sched.name, sched.desc)
		fmt.Printf("✓ Completed: %s\n\n", sched.desc)
	}

	// Generate comprehensive report
	generateReport(results, cache)
}

func initializeNodes(cache *CarbonCache) []*Node {
	nodes := []*Node{}
	
	// Create nodes for each region
	// REDUCED: Only 1 node per region (was 2-3) to create more contention
	for region, data := range cache.Regions {
		// Create 1 node per region for high contention scenario
		numNodes := 1
		for i := 0; i < numNodes; i++ {
			node := &Node{
				Name:            fmt.Sprintf("%s-node-%d", region, i+1),
				Region:          region,
				CarbonIntensity: data.CarbonIntensity,
				TotalCPU:        4.0,  // REDUCED: 4 CPU cores per node (was 8)
				TotalMemory:     8.0,  // REDUCED: 8 GB per node (was 16)
				AvailableCPU:   4.0,
				AvailableMemory: 8.0,
				Jobs:            []*Job{},
				RunningJobs:     []*Job{},
				Queue:           []*Job{},
			}
			nodes = append(nodes, node)
		}
	}
	
	return nodes
}

// addSimulationRegions adds additional regions with varied carbon intensities
// This is specific to simulation to better demonstrate carbon-aware scheduling
// Includes both US and international regions with diverse energy mixes
func addSimulationRegions(nodes []*Node) []*Node {
	// Additional regions with varied carbon intensities for simulation
	// These represent real-world regions with different energy mixes
	// Includes US and international regions for global carbon-aware scheduling
	
	// US Regions
	usRegions := map[string]float64{
		"US-NW-PACW": 180.0,  // Pacific Northwest (hydroelectric) - VERY LOW
		"US-NY-NYIS": 280.0,  // New York (mix) - LOW
		"US-CAL-CISO": 360.0, // California (mix) - MEDIUM
		"US-TEX-ERCO": 450.0, // Texas (fossil-heavy) - HIGH
		"US-MIDW-MISO": 550.0, // Midwest (coal-heavy) - VERY HIGH
		"US-SE-SERC": 480.0,   // Southeast (fossil-heavy) - HIGH
		"US-FLA-FPL": 420.0,   // Florida (mix) - MEDIUM-HIGH
	}
	
	// International Regions - Low Carbon (Renewable-heavy)
	lowCarbonRegions := map[string]float64{
		"NO-NO1": 25.0,   // Norway (hydroelectric) - EXTREMELY LOW
		"SE-SE3": 45.0,   // Sweden (nuclear + hydro) - VERY LOW
		"FR-FR": 85.0,    // France (nuclear) - VERY LOW
		"BR-S": 120.0,    // Brazil South (hydroelectric) - LOW
		"CA-QC": 30.0,    // Quebec, Canada (hydroelectric) - EXTREMELY LOW
		"IS-IS": 28.0,    // Iceland (geothermal + hydro) - EXTREMELY LOW
	}
	
	// International Regions - Medium Carbon (Mix)
	mediumCarbonRegions := map[string]float64{
		"GB-GB": 250.0,   // United Kingdom (mix) - LOW-MEDIUM
		"DE-DE": 380.0,   // Germany (mix, transitioning) - MEDIUM
		"JP-TK": 420.0,   // Tokyo, Japan (mix) - MEDIUM-HIGH
		"AU-NSW": 650.0,  // New South Wales, Australia (coal-heavy) - HIGH
		"IN-WE": 720.0,   // Western India (coal-heavy) - VERY HIGH
		"CN-BJ": 580.0,   // Beijing, China (coal-heavy) - HIGH
		"KR-KR": 480.0,   // South Korea (mix) - MEDIUM-HIGH
	}
	
	// International Regions - High Carbon (Fossil-heavy)
	highCarbonRegions := map[string]float64{
		"PL-PL": 750.0,   // Poland (coal-heavy) - VERY HIGH
		"AU-VIC": 900.0,  // Victoria, Australia (brown coal) - EXTREMELY HIGH
		"ZA-ZA": 850.0,   // South Africa (coal-heavy) - VERY HIGH
		"ID-JB": 780.0,   // Java-Bali, Indonesia (coal) - VERY HIGH
	}
	
	// Combine all regions
	additionalRegions := make(map[string]float64)
	for k, v := range usRegions {
		additionalRegions[k] = v
	}
	for k, v := range lowCarbonRegions {
		additionalRegions[k] = v
	}
	for k, v := range mediumCarbonRegions {
		additionalRegions[k] = v
	}
	for k, v := range highCarbonRegions {
		additionalRegions[k] = v
	}
	
	// Check which regions already exist
	existingRegions := make(map[string]bool)
	for _, node := range nodes {
		existingRegions[node.Region] = true
	}
	
	// Add nodes for regions not already present
	for region, carbonIntensity := range additionalRegions {
		if !existingRegions[region] {
			// Only add 1 node per new region to keep resource constraints
			node := &Node{
				Name:            fmt.Sprintf("%s-node-1", region),
				Region:          region,
				CarbonIntensity: carbonIntensity,
				TotalCPU:        4.0,  // 4 CPU cores per node
				TotalMemory:     8.0,  // 8 GB per node
				AvailableCPU:   4.0,
				AvailableMemory: 8.0,
				Jobs:            []*Job{},
				RunningJobs:     []*Job{},
				Queue:           []*Job{},
			}
			nodes = append(nodes, node)
		}
	}
	
	return nodes
}

// createJob creates a job with appropriate type and characteristics
func createJob(jobID int, config SimulationConfig, currentTime time.Time) *Job {
	// Determine job type based on ratio
	var jobType JobType
	randVal := rand.Float64()
	if randVal < config.ComputeJobRatio {
		jobType = ComputeIntensive // Matrix multiplication, ML training
	} else if randVal < config.ComputeJobRatio+0.2 {
		jobType = IOBound // Data processing
	} else if randVal < config.ComputeJobRatio+0.5 {
		jobType = Mixed // Web services
	} else {
		jobType = Batch // Batch processing
	}
	
	// Generate resource requests
	cpuRequest := math.Max(0.1, rand.NormFloat64()*config.CPURequestStd+config.CPURequestMean)
	memoryRequest := math.Max(0.5, rand.NormFloat64()*config.MemoryRequestStd+config.MemoryRequestMean)
	
	// Generate duration based on job type
	var duration, blockingTime time.Duration
	switch jobType {
	case ComputeIntensive:
		// Matrix multiplication: long blocking, CPU-intensive
		duration = time.Duration(math.Max(float64(30*time.Minute), rand.NormFloat64()*float64(20*time.Minute)+float64(45*time.Minute)))
		blockingTime = duration * 8 / 10 // 80% of time is blocking compute
		cpuRequest = math.Max(cpuRequest, 2.0) // Compute jobs need more CPU
	case Batch:
		// Batch processing: long-running, blocking
		duration = time.Duration(math.Max(float64(60*time.Minute), rand.NormFloat64()*float64(30*time.Minute)+float64(90*time.Minute)))
		blockingTime = duration * 7 / 10 // 70% blocking
	case IOBound:
		// I/O-bound: shorter, less blocking
		duration = time.Duration(math.Max(float64(5*time.Minute), rand.NormFloat64()*float64(5*time.Minute)+float64(10*time.Minute)))
		blockingTime = duration * 3 / 10 // 30% blocking (mostly I/O wait)
	case Mixed:
		// Mixed workload: moderate blocking
		duration = time.Duration(math.Max(float64(10*time.Minute), rand.NormFloat64()*float64(config.JobDurationStd)+float64(config.JobDurationMean)))
		blockingTime = duration * 5 / 10 // 50% blocking
	default:
		duration = time.Duration(math.Max(float64(time.Minute), rand.NormFloat64()*float64(config.JobDurationStd)+float64(config.JobDurationMean)))
		blockingTime = duration / 2
	}
	
	return &Job{
		ID:            fmt.Sprintf("job-%d", jobID),
		Type:          jobType,
		CPURequest:    cpuRequest,
		MemoryRequest: memoryRequest,
		Duration:      duration,
		BlockingTime:  blockingTime,
		CreatedAt:     currentTime,
	}
}

func getRegions(nodes []*Node) []string {
	regionMap := make(map[string]bool)
	for _, node := range nodes {
		regionMap[node.Region] = true
	}
	regions := []string{}
	for region := range regionMap {
		regions = append(regions, region)
	}
	return regions
}

func runSimulation(nodes []*Node, config SimulationConfig, schedulerType SchedulerType, schedulerName string) SimulationResults {
	// Reset nodes
	for _, node := range nodes {
		node.AvailableCPU = node.TotalCPU
		node.AvailableMemory = node.TotalMemory
		node.Jobs = []*Job{}
		node.RunningJobs = []*Job{}
		node.Queue = []*Job{}
		node.Utilization = 0.0
		node.QueueLength = 0
	}

	startTime := time.Now()
	endTime := startTime.Add(config.Duration)
	
	jobs := []*Job{}
	jobID := 0
	currentTime := startTime
	tickInterval := 10 * time.Second // Process events every 10 seconds
	
	// Simulate job arrivals and processing
	for currentTime.Before(endTime) {
		// Process job arrivals (Poisson process)
		interArrivalTime := time.Duration(float64(time.Minute) / config.JobArrivalRate)
		nextArrivalTime := currentTime.Add(interArrivalTime)
		
		// Process until next arrival or end time
		for currentTime.Before(nextArrivalTime) && currentTime.Before(endTime) {
			// Process queues and start jobs
			processQueues(nodes, currentTime)
			
			// Clean up completed jobs
			cleanupCompletedJobs(nodes, currentTime)
			
			currentTime = currentTime.Add(tickInterval)
		}
		
		if currentTime.After(endTime) {
			break
		}
		
		// Create new job
		job := createJob(jobID, config, currentTime)
		
		// Try to schedule job
		node := scheduleJob(job, nodes, schedulerType, currentTime)
		if node != nil {
			// Job can start immediately
			job.ScheduledAt = currentTime
			job.StartedAt = currentTime
			job.QueueTime = 0
			job.Latency = 0
			job.Node = node.Name
			job.Region = node.Region
			job.CarbonIntensity = node.CarbonIntensity
			job.CompletedAt = currentTime.Add(job.Duration)
			job.ExecutionTime = job.Duration
			job.TurnaroundTime = job.Duration
			
			node.RunningJobs = append(node.RunningJobs, job)
			node.AvailableCPU -= job.CPURequest
			node.AvailableMemory -= job.MemoryRequest
			
			jobs = append(jobs, job)
		} else {
			// No immediate resources - add to queue of best node
			node := selectBestNodeForQueue(job, nodes, schedulerType)
			if node != nil {
				job.Node = node.Name
				job.Region = node.Region
				job.CarbonIntensity = node.CarbonIntensity
				node.Queue = append(node.Queue, job)
				node.QueueLength = len(node.Queue)
				jobs = append(jobs, job)
			} else {
				// Job failed to schedule
				job.ScheduledAt = time.Time{}
				jobs = append(jobs, job)
			}
		}
		
		jobID++
	}
	
	// Process remaining queue after simulation ends (allow jobs to complete)
	maxProcessTime := endTime.Add(48 * time.Hour) // Allow up to 48 hours for jobs to complete
	for currentTime.Before(maxProcessTime) {
		allQueuesEmpty := true
		allJobsDone := true
		for _, node := range nodes {
			if len(node.Queue) > 0 {
				allQueuesEmpty = false
			}
			if len(node.RunningJobs) > 0 {
				allJobsDone = false
			}
		}
		if allQueuesEmpty && allJobsDone {
			break
		}
		
		processQueues(nodes, currentTime)
		cleanupCompletedJobs(nodes, currentTime)
		currentTime = currentTime.Add(tickInterval)
	}
	
	// Calculate metrics
	return calculateMetrics(jobs, nodes, schedulerName, config.Duration)
}

// processQueues processes job queues and starts jobs when resources available
func processQueues(nodes []*Node, currentTime time.Time) {
	for _, node := range nodes {
		// Try to start queued jobs
		newQueue := []*Job{}
		for _, queuedJob := range node.Queue {
			if node.AvailableCPU >= queuedJob.CPURequest && node.AvailableMemory >= queuedJob.MemoryRequest {
				// Can start this job
				queuedJob.ScheduledAt = currentTime
				queuedJob.StartedAt = currentTime
				queuedJob.QueueTime = currentTime.Sub(queuedJob.CreatedAt)
				queuedJob.Latency = queuedJob.QueueTime
				queuedJob.CompletedAt = currentTime.Add(queuedJob.Duration)
				queuedJob.ExecutionTime = queuedJob.Duration
				queuedJob.TurnaroundTime = queuedJob.CompletedAt.Sub(queuedJob.CreatedAt)
				
				node.RunningJobs = append(node.RunningJobs, queuedJob)
				node.AvailableCPU -= queuedJob.CPURequest
				node.AvailableMemory -= queuedJob.MemoryRequest
			} else {
				// Still waiting
				newQueue = append(newQueue, queuedJob)
			}
		}
		node.Queue = newQueue
		node.QueueLength = len(newQueue)
	}
}

// cleanupCompletedJobs removes completed jobs and frees resources
func cleanupCompletedJobs(nodes []*Node, currentTime time.Time) {
	for _, node := range nodes {
		newRunningJobs := []*Job{}
		for _, job := range node.RunningJobs {
			if job.CompletedAt.After(currentTime) {
				// Still running
				newRunningJobs = append(newRunningJobs, job)
			} else {
				// Job completed, free resources
				node.AvailableCPU += job.CPURequest
				node.AvailableMemory += job.MemoryRequest
			}
		}
		node.RunningJobs = newRunningJobs
		
		// Update utilization
		usedCPU := node.TotalCPU - node.AvailableCPU
		node.Utilization = (usedCPU / node.TotalCPU) * 100.0
	}
}

func scheduleJob(job *Job, nodes []*Node, schedulerType SchedulerType, currentTime time.Time) *Node {
	// Filter nodes with available resources
	availableNodes := []*Node{}
	for _, node := range nodes {
		if node.AvailableCPU >= job.CPURequest && node.AvailableMemory >= job.MemoryRequest {
			availableNodes = append(availableNodes, node)
		}
	}
	
	if len(availableNodes) == 0 {
		return nil // No immediate resources
	}
	
	return selectNode(availableNodes, schedulerType)
}

// selectBestNodeForQueue selects the best node for queuing when no immediate resources
func selectBestNodeForQueue(job *Job, nodes []*Node, schedulerType SchedulerType) *Node {
	// Estimate wait time for each node and select best
	bestNode := (*Node)(nil)
	bestScore := math.MaxFloat64
	
	for _, node := range nodes {
		// Estimate wait time based on current load and queue length
		utilization := (node.TotalCPU - node.AvailableCPU) / node.TotalCPU
		estimatedWait := estimateWaitTime(node, job, utilization)
		
		var score float64
		switch schedulerType {
		case CarbonAware:
			// Score = wait time + carbon penalty
			// Heavily weight carbon intensity to strongly prefer low-carbon nodes
			// Even if they have longer queues, prefer low-carbon
			score = float64(estimatedWait)*0.1 + node.CarbonIntensity*10000 // Carbon dominates
		case LeastLoaded:
			// Score = wait time + utilization penalty
			score = float64(estimatedWait) + utilization*10000
		case RoundRobin:
			// Score = wait time + queue length
			score = float64(estimatedWait) + float64(len(node.Queue))*1000
		case HighestCarbon:
			// Score = wait time - carbon bonus (prefer high carbon)
			// Make worst-case scheduler truly prefer highest carbon
			score = float64(estimatedWait)*0.1 - node.CarbonIntensity*10000 // Carbon dominates (negative = prefer high)
		default:
			score = float64(estimatedWait)
		}
		
		if score < bestScore {
			bestScore = score
			bestNode = node
		}
	}
	
	return bestNode
}

func estimateWaitTime(node *Node, job *Job, utilization float64) time.Duration {
	// Estimate based on:
	// 1. Current utilization (how busy node is)
	// 2. Queue length (how many jobs waiting)
	// 3. Average job duration (how long jobs take)
	
	// Base wait time from utilization
	baseWait := time.Duration(float64(10*time.Minute) * utilization)
	
	// Add queue wait time (estimate average job duration * queue length)
	avgJobDuration := 20 * time.Minute // Estimate
	queueWait := time.Duration(float64(avgJobDuration) * float64(len(node.Queue)) * 0.5)
	
	// For compute-intensive jobs, add extra wait (they block longer)
	if job.Type == ComputeIntensive {
		baseWait = baseWait * 2
	}
	
	return baseWait + queueWait
}

func selectNode(availableNodes []*Node, schedulerType SchedulerType) *Node {
	if len(availableNodes) == 0 {
		return nil
	}
	
	switch schedulerType {
	case CarbonAware:
		// Select node with lowest carbon intensity
		sort.Slice(availableNodes, func(i, j int) bool {
			return availableNodes[i].CarbonIntensity < availableNodes[j].CarbonIntensity
		})
		return availableNodes[0]
		
	case RoundRobin:
		// Round-robin: select based on job count
		sort.Slice(availableNodes, func(i, j int) bool {
			return len(availableNodes[i].Jobs) < len(availableNodes[j].Jobs)
		})
		return availableNodes[0]
		
	case Random:
		return availableNodes[rand.Intn(len(availableNodes))]
		
	case LeastLoaded:
		// Select node with most available resources
		sort.Slice(availableNodes, func(i, j int) bool {
			utilI := (availableNodes[i].TotalCPU - availableNodes[i].AvailableCPU) / availableNodes[i].TotalCPU
			utilJ := (availableNodes[j].TotalCPU - availableNodes[j].AvailableCPU) / availableNodes[j].TotalCPU
			return utilI < utilJ
		})
		return availableNodes[0]
		
		case HighestCarbon:
			// Worst case: select highest carbon
			// Always prefer highest carbon, even if it means longer wait
			sort.Slice(availableNodes, func(i, j int) bool {
				return availableNodes[i].CarbonIntensity > availableNodes[j].CarbonIntensity
			})
			return availableNodes[0]
		
	default:
		return availableNodes[0]
	}
}


func calculateMetrics(jobs []*Job, nodes []*Node, schedulerName string, duration time.Duration) SimulationResults {
	results := SimulationResults{
		SchedulerType:      schedulerName,
		TotalJobs:          len(jobs),
		NodeUtilization:    make(map[string]float64),
		RegionDistribution: make(map[string]int),
		CarbonByRegion:     make(map[string]float64),
		JobsByRegion:       make(map[string]int),
	}
	
	if len(jobs) == 0 {
		return results
	}
	
	// Calculate carbon metrics
	totalCarbon := 0.0
	latencies := []float64{}
	turnarounds := []float64{}
	
	for _, job := range jobs {
		if job.ScheduledAt.IsZero() {
			results.FailedJobs++
			continue
		}
		
		results.CompletedJobs++
		totalCarbon += job.CarbonIntensity
		latencies = append(latencies, float64(job.Latency))
		turnarounds = append(turnarounds, float64(job.TurnaroundTime))
		
		results.RegionDistribution[job.Region]++
		results.JobsByRegion[job.Region]++
		results.CarbonByRegion[job.Region] += job.CarbonIntensity
	}
	
	results.AverageCarbon = totalCarbon / float64(results.CompletedJobs)
	results.TotalCarbon = totalCarbon
	
	// Calculate latency metrics
	if len(latencies) > 0 {
		sort.Float64s(latencies)
		// Average latency (mean)
		sum := 0.0
		for _, l := range latencies {
			sum += l
		}
		results.AverageLatency = time.Duration(sum / float64(len(latencies)))
		
		// P95 latency
		if len(latencies) >= 20 {
			p95Index := int(float64(len(latencies)) * 0.95)
			results.P95Latency = time.Duration(latencies[p95Index])
		} else {
			results.P95Latency = time.Duration(latencies[len(latencies)-1])
		}
	}
	
	// Calculate turnaround metrics
	if len(turnarounds) > 0 {
		sort.Float64s(turnarounds)
		// Average turnaround (mean)
		sum := 0.0
		for _, t := range turnarounds {
			sum += t
		}
		results.AverageTurnaround = time.Duration(sum / float64(len(turnarounds)))
		
		// P95 turnaround
		if len(turnarounds) >= 20 {
			p95Index := int(float64(len(turnarounds)) * 0.95)
			results.P95Turnaround = time.Duration(turnarounds[p95Index])
		} else {
			results.P95Turnaround = time.Duration(turnarounds[len(turnarounds)-1])
		}
	}
	
	// Calculate utilization (average over simulation time)
	// Track peak utilization and average utilization
	totalUtilization := 0.0
	totalPeakUtilization := 0.0
	for _, node := range nodes {
		// Current utilization (at end of simulation)
		currentUtilization := (node.TotalCPU - node.AvailableCPU) / node.TotalCPU * 100.0
		
		// Estimate average utilization based on completed jobs
		// This is simplified - ideally we'd track utilization over time
		totalJobCPU := 0.0
		for _, job := range jobs {
			if job.Node == node.Name && !job.ScheduledAt.IsZero() {
				totalJobCPU += job.CPURequest
			}
		}
		// Average utilization = total CPU used / (node capacity * simulation duration factor)
		avgUtilization := math.Min(100.0, (totalJobCPU / node.TotalCPU) * 100.0)
		
		results.NodeUtilization[node.Name] = avgUtilization
		totalUtilization += avgUtilization
		totalPeakUtilization += currentUtilization
	}
	results.AverageUtilization = totalUtilization / float64(len(nodes))
	
	// Calculate throughput
	results.Throughput = float64(results.CompletedJobs) / duration.Hours()
	
	return results
}

func generateReport(results []SimulationResults, cache *CarbonCache) {
	fmt.Println("╔══════════════════════════════════════════════════════════════════════════════════════╗")
	fmt.Println("║                    COMPREHENSIVE SIMULATION RESULTS                                 ║")
	fmt.Println("╠══════════════════════════════════════════════════════════════════════════════════════╣")
	fmt.Println()
	
	// Find carbon-aware and worst-case results for comparison
	var carbonAware, worstCase SimulationResults
	for _, r := range results {
		if r.SchedulerType == "Carbon-Aware" {
			carbonAware = r
		}
		if r.SchedulerType == "Highest-Carbon (Worst Case)" {
			worstCase = r
		}
	}
	
	// Calculate reductions
	if worstCase.AverageCarbon > 0 {
		carbonAware.CarbonReduction = ((worstCase.AverageCarbon - carbonAware.AverageCarbon) / worstCase.AverageCarbon) * 100.0
	}
	if worstCase.AverageLatency > 0 {
		carbonAware.LatencyReduction = ((float64(worstCase.AverageLatency) - float64(carbonAware.AverageLatency)) / float64(worstCase.AverageLatency)) * 100.0
	}
	
	// Print comparison table
	fmt.Println("┌──────────────────────────────────────────────────────────────────────────────────────┐")
	fmt.Println("│                          SCHEDULER COMPARISON                                        │")
	fmt.Println("├──────────────────────────────────────────────────────────────────────────────────────┤")
	fmt.Printf("│ %-25s │ %8s │ %10s │ %12s │ %12s │ %10s │\n", "Scheduler", "Jobs", "Avg Carbon", "Avg Latency", "Turnaround", "Throughput")
	fmt.Println("├──────────────────────────────────────────────────────────────────────────────────────┤")
	
	for _, r := range results {
		fmt.Printf("│ %-25s │ %8d │ %10.2f │ %12s │ %12s │ %10.2f │\n",
			r.SchedulerType,
			r.CompletedJobs,
			r.AverageCarbon,
			formatDuration(r.AverageLatency),
			formatDuration(r.AverageTurnaround),
			r.Throughput)
	}
	fmt.Println("└──────────────────────────────────────────────────────────────────────────────────────┘")
	fmt.Println()
	
	// Detailed carbon metrics
	fmt.Println("┌──────────────────────────────────────────────────────────────────────────────────────┐")
	fmt.Println("│                          CARBON INTENSITY METRICS                                   │")
	fmt.Println("├──────────────────────────────────────────────────────────────────────────────────────┤")
	fmt.Printf("│ Carbon-Aware Average:        %.2f g CO2/kWh                                           │\n", carbonAware.AverageCarbon)
	fmt.Printf("│ Worst-Case Average:          %.2f g CO2/kWh                                           │\n", worstCase.AverageCarbon)
	fmt.Printf("│ Carbon Reduction:            %.2f%%                                                    │\n", carbonAware.CarbonReduction)
	fmt.Printf("│ Total Carbon Saved:          %.2f g CO2/kWh                                           │\n", worstCase.TotalCarbon-carbonAware.TotalCarbon)
	fmt.Println("└──────────────────────────────────────────────────────────────────────────────────────┘")
	fmt.Println()
	
	// Region distribution
	fmt.Println("┌──────────────────────────────────────────────────────────────────────────────────────┐")
	fmt.Println("│                    CARBON-AWARE REGION DISTRIBUTION                                  │")
	fmt.Println("├──────────────────────────────────────────────────────────────────────────────────────┤")
	for region, count := range carbonAware.RegionDistribution {
		avgCarbon := carbonAware.CarbonByRegion[region] / float64(count)
		fmt.Printf("│ %-20s: %4d jobs (%.2f g CO2/kWh avg)                                    │\n", region, count, avgCarbon)
	}
	fmt.Println("└──────────────────────────────────────────────────────────────────────────────────────┘")
	fmt.Println()
	
	// Performance metrics
	fmt.Println("┌──────────────────────────────────────────────────────────────────────────────────────┐")
	fmt.Println("│                          PERFORMANCE METRICS                                         │")
	fmt.Println("├──────────────────────────────────────────────────────────────────────────────────────┤")
	fmt.Printf("│ Average Latency:             %s                                                      │\n", formatDuration(carbonAware.AverageLatency))
	fmt.Printf("│ P95 Latency:                 %s                                                      │\n", formatDuration(carbonAware.P95Latency))
	fmt.Printf("│ Average Turnaround Time:     %s                                                      │\n", formatDuration(carbonAware.AverageTurnaround))
	fmt.Printf("│ P95 Turnaround Time:         %s                                                      │\n", formatDuration(carbonAware.P95Turnaround))
	fmt.Printf("│ Throughput:                  %.2f jobs/hour                                          │\n", carbonAware.Throughput)
	fmt.Printf("│ Average Node Utilization:    %.2f%%                                                    │\n", carbonAware.AverageUtilization)
	fmt.Println("└──────────────────────────────────────────────────────────────────────────────────────┘")
	fmt.Println()
	
	// Summary
	fmt.Println("╔══════════════════════════════════════════════════════════════════════════════════════╗")
	fmt.Println("║                                  SUMMARY                                              ║")
	fmt.Println("╠══════════════════════════════════════════════════════════════════════════════════════╣")
	fmt.Printf("║  Carbon Reduction: %.2f%% vs worst-case scheduler                                    ║\n", carbonAware.CarbonReduction)
	fmt.Printf("║  Jobs Completed: %d                                                                   ║\n", carbonAware.CompletedJobs)
	fmt.Printf("║  Average Carbon: %.2f g CO2/kWh                                                        ║\n", carbonAware.AverageCarbon)
	fmt.Printf("║  Throughput: %.2f jobs/hour                                                           ║\n", carbonAware.Throughput)
	fmt.Println("╚══════════════════════════════════════════════════════════════════════════════════════╝")
}

func formatDuration(d time.Duration) string {
	if d < time.Second {
		return fmt.Sprintf("%.0fms", float64(d)/float64(time.Millisecond))
	} else if d < time.Minute {
		return fmt.Sprintf("%.2fs", d.Seconds())
	} else {
		return fmt.Sprintf("%.2fm", d.Minutes())
	}
}

func readCarbonCache(cacheFile string) (*CarbonCache, error) {
	data, err := os.ReadFile(cacheFile)
	if err != nil {
		return nil, err
	}
	
	// First unmarshal into a generic map to check structure
	var rawData map[string]interface{}
	if err := json.Unmarshal(data, &rawData); err != nil {
		return nil, err
	}
	
	// Handle nested regions structure (backward compatibility)
	if regionsRaw, ok := rawData["regions"].(map[string]interface{}); ok {
		// Check if nested: regions.regions
		if nestedRegions, ok := regionsRaw["regions"].(map[string]interface{}); ok {
			// Flatten the structure
			rawData["regions"] = nestedRegions
		}
	}
	
	// Now unmarshal into proper struct
	var cache CarbonCache
	cacheBytes, _ := json.Marshal(rawData)
	if err := json.Unmarshal(cacheBytes, &cache); err != nil {
		return nil, err
	}
	
	return &cache, nil
}

