#!/usr/bin/env python3
"""
Electricity Maps Carbon Intensity API Client

This module provides a Python client for interacting with the Electricity Maps API
to retrieve carbon intensity data for different zones.

API Documentation: https://portal.electricitymaps.com/developer-hub/api/reference#carbon-intensity-recent
"""

import requests
import json
import os
from datetime import datetime, timezone
from typing import Dict, List, Optional, Union
import argparse


class CarbonIntensityAPI:
    """Client for Electricity Maps Carbon Intensity API"""
    
    BASE_URL = "https://api.electricitymaps.com/v3"
    
    def __init__(self, api_key: Optional[str] = None):
        """
        Initialize the API client
        
        Args:
            api_key: Your Electricity Maps API key. If not provided, will look for 
                    ELECTRICITY_MAPS_API_KEY environment variable
        """
        self.api_key = api_key or os.getenv('ELECTRICITY_MAPS_API_KEY')
        if not self.api_key:
            raise ValueError(
                "API key is required. Provide it as parameter or set ELECTRICITY_MAPS_API_KEY environment variable"
            )
        
        self.headers = {
            'auth-token': self.api_key,
            'Content-Type': 'application/json'
        }
    
    def get_carbon_intensity_recent(self, zone: str) -> Dict:
        """
        Get recent carbon intensity data for a specific zone
        
        Args:
            zone: The zone identifier (e.g., 'DE' for Germany, 'US-CA' for California)
            
        Returns:
            Dictionary containing carbon intensity data
        """
        url = f"{self.BASE_URL}/carbon-intensity/recent"
        params = {'zone': zone}
        
        try:
            response = requests.get(url, headers=self.headers, params=params)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            raise Exception(f"API request failed: {e}")
    
    def get_carbon_intensity_latest(self, zone: str) -> Dict:
        """
        Get latest carbon intensity data for a specific zone
        
        Args:
            zone: The zone identifier
            
        Returns:
            Dictionary containing latest carbon intensity data
        """
        url = f"{self.BASE_URL}/carbon-intensity/latest"
        params = {'zone': zone}
        
        try:
            response = requests.get(url, headers=self.headers, params=params)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            raise Exception(f"API request failed: {e}")
    
    def get_carbon_intensity_forecast(self, zone: str) -> Dict:
        """
        Get carbon intensity forecast for a specific zone
        
        Args:
            zone: The zone identifier
            
        Returns:
            Dictionary containing forecast data
        """
        url = f"{self.BASE_URL}/carbon-intensity/forecast"
        params = {'zone': zone}
        
        try:
            response = requests.get(url, headers=self.headers, params=params)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            raise Exception(f"API request failed: {e}")
    
    def get_zones(self) -> Dict:
        """
        Get list of available zones
        
        Returns:
            Dictionary containing available zones
        """
        url = f"{self.BASE_URL}/zones"
        
        try:
            response = requests.get(url, headers=self.headers)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            raise Exception(f"API request failed: {e}")
    
    def format_carbon_intensity_data(self, data: Dict) -> str:
        """
        Format carbon intensity data for display
        
        Args:
            data: Carbon intensity data from API
            
        Returns:
            Formatted string representation
        """
        if 'data' in data:
            # Handle recent/forecast data format
            entries = data['data']
            if not entries:
                return "No data available"
            
            formatted = []
            for entry in entries:
                timestamp = entry.get('datetime', 'Unknown time')
                intensity = entry.get('carbonIntensity', 'N/A')
                formatted.append(f"  {timestamp}: {intensity} gCO₂eq/kWh")
            
            return "\n".join(formatted)
        
        elif 'carbonIntensity' in data:
            # Handle latest data format
            timestamp = data.get('datetime', 'Unknown time')
            intensity = data.get('carbonIntensity', 'N/A')
            return f"{timestamp}: {intensity} gCO₂eq/kWh"
        
        return "Unknown data format"


def main():
    """Command line interface for the Carbon Intensity API"""
    parser = argparse.ArgumentParser(description='Electricity Maps Carbon Intensity API Client')
    parser.add_argument('--api-key', help='Your Electricity Maps API key')
    parser.add_argument('--zone', default='DE', help='Zone identifier (default: DE for Germany)')
    parser.add_argument('--type', choices=['recent', 'latest', 'forecast', 'zones'], 
                       default='latest', help='Type of data to retrieve')
    parser.add_argument('--format', choices=['json', 'pretty'], default='pretty',
                       help='Output format')
    
    args = parser.parse_args()
    
    try:
        # Initialize API client
        api = CarbonIntensityAPI(api_key=args.api_key)
        
        if args.type == 'zones':
            data = api.get_zones()
            if args.format == 'json':
                print(json.dumps(data, indent=2))
            else:
                print("Available zones:")
                for zone_id, zone_info in data.items():
                    print(f"  {zone_id}: {zone_info.get('countryName', 'Unknown')}")
        
        elif args.type == 'recent':
            data = api.get_carbon_intensity_recent(args.zone)
            if args.format == 'json':
                print(json.dumps(data, indent=2))
            else:
                print(f"Recent carbon intensity for {args.zone}:")
                print(api.format_carbon_intensity_data(data))
        
        elif args.type == 'latest':
            data = api.get_carbon_intensity_latest(args.zone)
            if args.format == 'json':
                print(json.dumps(data, indent=2))
            else:
                print(f"Latest carbon intensity for {args.zone}:")
                print(api.format_carbon_intensity_data(data))
        
        elif args.type == 'forecast':
            data = api.get_carbon_intensity_forecast(args.zone)
            if args.format == 'json':
                print(json.dumps(data, indent=2))
            else:
                print(f"Carbon intensity forecast for {args.zone}:")
                print(api.format_carbon_intensity_data(data))
    
    except Exception as e:
        print(f"Error: {e}")
        return 1
    
    return 0


if __name__ == "__main__":
    exit(main())
