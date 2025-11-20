package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"
)

// Simulation results
type SimulationResult struct {
	Mode              string
	TotalPods         int
	TotalCarbonGrams  float64
	AverageCarbonPerPod float64
	NodeAssignments   map[string]int
	RegionAssignments map[string]int
	CarbonByRegion    map[string]float64
}

// Carbon cache structure (same as scheduler)
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
	CarbonIntensity   float64 `json:"carbonIntensity"` // g CO2/kWh (Electricity Maps)
	MOER              float64 `json:"moer"`             // Legacy WattimeAPI field
	Datetime          string  `json:"datetime"`
	UpdatedAt         string  `json:"updatedAt"`
	CreatedAt         string  `json:"createdAt"`
	EmissionFactorType string  `json:"emissionFactorType"`
	IsEstimated       bool    `json:"isEstimated"`
	EstimationMethod  string  `json:"estimationMethod"`
	Timestamp         string  `json:"timestamp"`
}

// Simulated pod with estimated energy consumption
type SimulatedPod struct {
	Name       string
	Region     string
	Node       string
	EnergyKWh  float64 // Estimated energy consumption
	CarbonGrams float64
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: simulate <cache_file> [num_pods] [energy_per_pod_kwh]")
		fmt.Println("Example: simulate /tmp/carbon_cache.json 100 0.5")
		os.Exit(1)
	}

	cacheFile := os.Args[1]
	numPods := 100
	energyPerPodKWh := 0.5

	if len(os.Args) >= 3 {
		fmt.Sscanf(os.Args[2], "%d", &numPods)
	}
	if len(os.Args) >= 4 {
		fmt.Sscanf(os.Args[3], "%f", &energyPerPodKWh)
	}

	fmt.Printf("Running simulation with %d pods, %.2f kWh per pod\n", numPods, energyPerPodKWh)
	fmt.Println(strings.Repeat("=", 62))

	// Read carbon cache
	cache, err := readCarbonCache(cacheFile)
	if err != nil {
		fmt.Printf("Error reading cache: %v\n", err)
		fmt.Println("Using mock data for simulation...")
		cache = createMockCache()
	}

	// Simulate non-carbon-aware scheduling
	nonCarbonAware := simulateNonCarbonAware(cache, numPods, energyPerPodKWh)

	// Simulate carbon-aware scheduling
	carbonAware := simulateCarbonAware(cache, numPods, energyPerPodKWh)

	// Print results
	printResults(nonCarbonAware, carbonAware)

	// Calculate savings
	savings := nonCarbonAware.TotalCarbonGrams - carbonAware.TotalCarbonGrams
	savingsPercent := (savings / nonCarbonAware.TotalCarbonGrams) * 100

	fmt.Println("\n" + strings.Repeat("=", 62))
	fmt.Printf("CARBON SAVINGS: %.2f g CO2 (%.2f%% reduction)\n", savings, savingsPercent)
	fmt.Println(strings.Repeat("=", 62))
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

func createMockCache() *CarbonCache {
	return &CarbonCache{
		Timestamp: time.Now().Format(time.RFC3339),
		Regions: map[string]Region{
			"US-CAL-CISO": {Zone: "US-CAL-CISO", CarbonIntensity: 250.0},
			"US-TEX-ERCO": {Zone: "US-TEX-ERCO", CarbonIntensity: 450.0}, // Correct zone code
			"US-NY-NYISO": {Zone: "US-NY-NYISO", CarbonIntensity: 200.0},
			"US-MIDA-PJM": {Zone: "US-MIDA-PJM", CarbonIntensity: 350.0},
			"US-MIDW-MISO": {Zone: "US-MIDW-MISO", CarbonIntensity: 500.0},
		},
		SortedByCarbon: []string{"US-NY-NYISO", "US-CAL-CISO", "US-MIDA-PJM", "US-TEX-ERCO", "US-MIDW-MISO"},
		BestRegion:     "US-NY-NYISO",
		WorstRegion:    "US-MIDW-MISO",
	}
}

func simulateNonCarbonAware(cache *CarbonCache, numPods int, energyPerPodKWh float64) SimulationResult {
	// Non-carbon-aware: distribute pods evenly across regions (round-robin)
	regions := make([]string, 0, len(cache.Regions))
	for region := range cache.Regions {
		regions = append(regions, region)
	}

	result := SimulationResult{
		Mode:              "Non-Carbon-Aware",
		TotalPods:         numPods,
		NodeAssignments:   make(map[string]int),
		RegionAssignments: make(map[string]int),
		CarbonByRegion:    make(map[string]float64),
	}

	for i := 0; i < numPods; i++ {
		region := regions[i%len(regions)]
		regionData := cache.Regions[region]
		// Use carbonIntensity (Electricity Maps) or fall back to MOER (WattimeAPI)
		carbonIntensity := regionData.CarbonIntensity
		if carbonIntensity == 0 {
			carbonIntensity = regionData.MOER
		}
		carbonGrams := energyPerPodKWh * carbonIntensity

		result.RegionAssignments[region]++
		result.NodeAssignments[fmt.Sprintf("node-%s-%d", region, i%3)]++
		result.CarbonByRegion[region] += carbonGrams
		result.TotalCarbonGrams += carbonGrams
	}

	result.AverageCarbonPerPod = result.TotalCarbonGrams / float64(numPods)
	return result
}

func simulateCarbonAware(cache *CarbonCache, numPods int, energyPerPodKWh float64) SimulationResult {
	// Carbon-aware: schedule all pods to the best (lowest carbon) region
	result := SimulationResult{
		Mode:              "Carbon-Aware",
		TotalPods:         numPods,
		NodeAssignments:   make(map[string]int),
		RegionAssignments: make(map[string]int),
		CarbonByRegion:    make(map[string]float64),
	}

	bestRegion := cache.BestRegion
	if bestRegion == "" && len(cache.SortedByCarbon) > 0 {
		bestRegion = cache.SortedByCarbon[0]
	}
	if bestRegion == "" {
		// Fallback: find region with lowest carbon intensity
		minCarbon := 10000.0
		for region, data := range cache.Regions {
			carbonIntensity := data.CarbonIntensity
			if carbonIntensity == 0 {
				carbonIntensity = data.MOER
			}
			if carbonIntensity > 0 && carbonIntensity < minCarbon {
				minCarbon = carbonIntensity
				bestRegion = region
			}
		}
	}

	regionData := cache.Regions[bestRegion]
	// Use carbonIntensity (Electricity Maps) or fall back to MOER (WattimeAPI)
	carbonIntensity := regionData.CarbonIntensity
	if carbonIntensity == 0 {
		carbonIntensity = regionData.MOER
	}
	carbonGrams := energyPerPodKWh * carbonIntensity

	result.RegionAssignments[bestRegion] = numPods
	result.NodeAssignments[fmt.Sprintf("node-%s-0", bestRegion)] = numPods
	result.CarbonByRegion[bestRegion] = carbonGrams * float64(numPods)
	result.TotalCarbonGrams = carbonGrams * float64(numPods)
	result.AverageCarbonPerPod = carbonGrams

	return result
}

func printResults(nonCarbonAware, carbonAware SimulationResult) {
	fmt.Printf("\n%-30s | %-30s\n", "Non-Carbon-Aware", "Carbon-Aware")
	fmt.Println(strings.Repeat("-", 65))

	fmt.Printf("%-30s | %-30s\n",
		fmt.Sprintf("Total Pods: %d", nonCarbonAware.TotalPods),
		fmt.Sprintf("Total Pods: %d", carbonAware.TotalPods))

	fmt.Printf("%-30s | %-30s\n",
		fmt.Sprintf("Total Carbon: %.2f g CO2", nonCarbonAware.TotalCarbonGrams),
		fmt.Sprintf("Total Carbon: %.2f g CO2", carbonAware.TotalCarbonGrams))

	fmt.Printf("%-30s | %-30s\n",
		fmt.Sprintf("Avg per Pod: %.2f g CO2", nonCarbonAware.AverageCarbonPerPod),
		fmt.Sprintf("Avg per Pod: %.2f g CO2", carbonAware.AverageCarbonPerPod))

	fmt.Println("\nRegion Distribution:")
	fmt.Printf("%-20s | %-20s | %-20s\n", "Region", "Non-Carbon-Aware", "Carbon-Aware")
	fmt.Println(strings.Repeat("-", 65))

	allRegions := make(map[string]bool)
	for r := range nonCarbonAware.RegionAssignments {
		allRegions[r] = true
	}
	for r := range carbonAware.RegionAssignments {
		allRegions[r] = true
	}

	for region := range allRegions {
		nonCarbonCount := nonCarbonAware.RegionAssignments[region]
		carbonCount := carbonAware.RegionAssignments[region]
		fmt.Printf("%-20s | %-20d | %-20d\n", region, nonCarbonCount, carbonCount)
	}
}

