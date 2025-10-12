#!/usr/bin/env python3
"""
Example usage of the Carbon Intensity API client

This script demonstrates how to use the CarbonIntensityAPI class to retrieve
carbon intensity data from the Electricity Maps API.
"""

import os
from carbon_intensity_api import CarbonIntensityAPI


def main():
    """Example usage of the Carbon Intensity API"""
    
    # Set your API key (you can also set ELECTRICITY_MAPS_API_KEY environment variable)
    api_key = "your_api_key_here"  # Replace with your actual API key
    
    try:
        # Initialize the API client
        api = CarbonIntensityAPI(api_key=api_key)
        
        # Example 1: Get latest carbon intensity for Germany
        print("=== Latest Carbon Intensity for Germany ===")
        latest_data = api.get_carbon_intensity_latest('DE')
        print(api.format_carbon_intensity_data(latest_data))
        print()
        
        # Example 2: Get recent carbon intensity data for California
        print("=== Recent Carbon Intensity for California ===")
        recent_data = api.get_carbon_intensity_recent('US-CA')
        print(api.format_carbon_intensity_data(recent_data))
        print()
        
        # Example 3: Get carbon intensity forecast for France
        print("=== Carbon Intensity Forecast for France ===")
        forecast_data = api.get_carbon_intensity_forecast('FR')
        print(api.format_carbon_intensity_data(forecast_data))
        print()
        
        # Example 4: List available zones
        print("=== Available Zones (first 10) ===")
        zones_data = api.get_zones()
        zone_count = 0
        for zone_id, zone_info in zones_data.items():
            if zone_count >= 10:
                break
            country_name = zone_info.get('countryName', 'Unknown')
            print(f"  {zone_id}: {country_name}")
            zone_count += 1
        print(f"... and {len(zones_data) - 10} more zones")
        
    except Exception as e:
        print(f"Error: {e}")
        print("\nMake sure to:")
        print("1. Replace 'your_api_key_here' with your actual Electricity Maps API key")
        print("2. Sign up at https://api-portal.electricitymaps.com/ to get an API key")


if __name__ == "__main__":
    main()
