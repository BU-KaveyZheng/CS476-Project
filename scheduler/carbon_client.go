package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

// CarbonIntensityData represents the structure of carbon intensity data from Electricity Maps API
type CarbonIntensityData struct {
	Zone            string    `json:"zone"`
	CarbonIntensity int       `json:"carbonIntensity"`
	Datetime        time.Time `json:"datetime"`
	UpdatedAt       time.Time `json:"updatedAt"`
}

// CarbonIntensityResponse represents the API response structure
type CarbonIntensityResponse struct {
	Data []CarbonIntensityData `json:"data"`
}

// CarbonClient handles communication with the Electricity Maps API
type CarbonClient struct {
	apiKey string
	client *http.Client
}

// NewCarbonClient creates a new carbon intensity client
func NewCarbonClient() (*CarbonClient, error) {
	apiKey := os.Getenv("ELECTRICITY_MAPS_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("ELECTRICITY_MAPS_API_KEY environment variable is required")
	}

	return &CarbonClient{
		apiKey: apiKey,
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
	}, nil
}

// GetLatestCarbonIntensity retrieves the latest carbon intensity for a given zone
func (c *CarbonClient) GetLatestCarbonIntensity(zone string) (*CarbonIntensityData, error) {
	url := fmt.Sprintf("https://api.electricitymaps.com/v3/carbon-intensity/latest?zone=%s", zone)
	
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("auth-token", c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("API request failed with status %d: %s", resp.StatusCode, string(body))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	var data CarbonIntensityData
	if err := json.Unmarshal(body, &data); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return &data, nil
}

// GetRecentCarbonIntensity retrieves recent carbon intensity data for a given zone
func (c *CarbonClient) GetRecentCarbonIntensity(zone string) ([]CarbonIntensityData, error) {
	url := fmt.Sprintf("https://api.electricitymaps.com/v3/carbon-intensity/recent?zone=%s", zone)
	
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("auth-token", c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("API request failed with status %d: %s", resp.StatusCode, string(body))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	var response CarbonIntensityResponse
	if err := json.Unmarshal(body, &response); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return response.Data, nil
}

// GetAverageCarbonIntensity calculates the average carbon intensity from recent data
// Falls back to latest data if recent data is not available
func (c *CarbonClient) GetAverageCarbonIntensity(zone string, hours int) (float64, error) {
	// Try to get recent data first
	recentData, err := c.GetRecentCarbonIntensity(zone)
	if err == nil && len(recentData) > 0 {
		// Calculate average from recent data points
		var total int
		count := 0
		cutoffTime := time.Now().Add(-time.Duration(hours) * time.Hour)

		for _, data := range recentData {
			if data.Datetime.After(cutoffTime) {
				total += data.CarbonIntensity
				count++
			}
		}

		if count > 0 {
			return float64(total) / float64(count), nil
		}
	}

	// Fall back to latest data if recent data is not available
	latestData, err := c.GetLatestCarbonIntensity(zone)
	if err != nil {
		return 0, fmt.Errorf("failed to get carbon intensity data: %w", err)
	}

	return float64(latestData.CarbonIntensity), nil
}

// IsLowCarbonTime determines if the current time has low carbon intensity
func (c *CarbonClient) IsLowCarbonTime(zone string, threshold int) (bool, error) {
	data, err := c.GetLatestCarbonIntensity(zone)
	if err != nil {
		return false, err
	}

	return data.CarbonIntensity <= threshold, nil
}
