package main

import (
	"encoding/json"
	"fmt"
	"os"
)

// Carbon intensity cache structure
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

func main() {
	cacheFile := os.Getenv("CACHE_FILE")
	if cacheFile == "" {
		cacheFile = "../cache/carbon_cache.json"
	}

	data, err := os.ReadFile(cacheFile)
	if err != nil {
		fmt.Printf("❌ Error reading cache: %v\n", err)
		os.Exit(1)
	}

	// Handle nested structure
	var rawData map[string]interface{}
	if err := json.Unmarshal(data, &rawData); err != nil {
		fmt.Printf("❌ Error parsing cache: %v\n", err)
		os.Exit(1)
	}

	// Handle nested regions structure
	if regionsRaw, ok := rawData["regions"].(map[string]interface{}); ok {
		if nestedRegions, ok := regionsRaw["regions"].(map[string]interface{}); ok {
			rawData["regions"] = nestedRegions
		}
	}

	cacheBytes, _ := json.Marshal(rawData)
	var cache CarbonCache
	if err := json.Unmarshal(cacheBytes, &cache); err != nil {
		fmt.Printf("❌ Error unmarshaling cache: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("✓ Cache file read successfully\n")
	fmt.Printf("  Timestamp: %s\n", cache.Timestamp)
	fmt.Printf("  Best region: %s\n", cache.BestRegion)
	fmt.Printf("  Worst region: %s\n", cache.WorstRegion)
	fmt.Printf("  Zones cached: %d\n", len(cache.Regions))

	if len(cache.Regions) > 0 {
		fmt.Println("\n  Zone carbon intensities:")
		for zone, region := range cache.Regions {
			ci := region.CarbonIntensity
			if ci == 0 {
				ci = region.MOER
			}
			fmt.Printf("    %s: %.2f g CO2/kWh\n", zone, ci)
		}
	}
}

