#!/usr/bin/env python3
"""
Carbon Intensity API Poller
Polls Electricity Maps API every N minutes and writes results to cache with TTL.
"""

import os
import json
import time
import requests
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
ELECTRICITY_MAPS_API_KEY = os.getenv('ELECTRICITY_MAPS_API_KEY', '')
ELECTRICITY_MAPS_API_BASE = 'https://api.electricitymap.org'
POLL_INTERVAL_MINUTES = int(os.getenv('POLL_INTERVAL_MINUTES', '5'))
# Default to project cache directory for local dev, /cache for Kubernetes
CACHE_FILE = os.getenv('CACHE_FILE', os.path.join(os.path.dirname(os.path.dirname(__file__)), 'cache', 'carbon_cache.json'))
CACHE_TTL_MINUTES = int(os.getenv('CACHE_TTL_MINUTES', '10'))

# Default zones (Electricity Maps format)
# See https://portal.electricitymaps.com/zones for available zones
# Common US zones:
# - US-CAL-CISO: California ISO
# - US-TEX-ERCO: Texas ERCOT (note: ERCO not ERCOT)
# - US-NY-NYISO: New York ISO
# - US-MIDA-PJM: PJM (Mid-Atlantic)
# - US-MIDW-MISO: Midwest ISO
DEFAULT_ZONES = [
    'US-CAL-CISO',  # California
    'US-TEX-ERCO',  # Texas ERCOT (correct code: ERCO)
    'US-NY-NYIS',  # New York
    'US-MIDA-PJM',  # PJM (Mid-Atlantic)
    'US-MIDW-MISO',  # Midwest
]

class CarbonIntensityCache:
    """Manages carbon intensity data cache with TTL."""
    
    def __init__(self, cache_file: str, ttl_minutes: int):
        self.cache_file = cache_file
        self.ttl_minutes = ttl_minutes
    
    def read_cache(self) -> Optional[Dict]:
        """Read cache file if it exists and is not expired."""
        try:
            if not os.path.exists(self.cache_file):
                return None
            
            with open(self.cache_file, 'r') as f:
                data = json.load(f)
            
            # Check if cache is expired
            cached_time = datetime.fromisoformat(data.get('timestamp', ''))
            if datetime.now() - cached_time > timedelta(minutes=self.ttl_minutes):
                logger.info(f"Cache expired (age: {datetime.now() - cached_time})")
                return None
            
            logger.info(f"Cache valid (age: {datetime.now() - cached_time})")
            return data
        except Exception as e:
            logger.error(f"Error reading cache: {e}")
            return None
    
    def write_cache(self, data: Dict):
        """Write data to cache file with timestamp."""
        try:
            # data already contains 'regions', 'sorted_by_carbon', 'best_region', 'worst_region'
            # Just add timestamp and TTL
            cache_data = {
                'timestamp': datetime.now().isoformat(),
                'ttl_minutes': self.ttl_minutes,
                **data  # Merge data dict into cache_data
            }
            
            # Ensure directory exists
            os.makedirs(os.path.dirname(self.cache_file) if os.path.dirname(self.cache_file) else '.', exist_ok=True)
            
            with open(self.cache_file, 'w') as f:
                json.dump(cache_data, f, indent=2)
            
            logger.info(f"Cache written to {self.cache_file}")
        except Exception as e:
            logger.error(f"Error writing cache: {e}")


class ElectricityMapsAPIClient:
    """Client for Electricity Maps API."""
    
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.base_url = ELECTRICITY_MAPS_API_BASE
        self.session = requests.Session()
        self.session.headers.update({
            'auth-token': api_key
        })
    
    def get_zones(self) -> List[str]:
        """Get list of available zones."""
        try:
            url = f'{self.base_url}/v3/zones'
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            zones_data = response.json()
            zones = list(zones_data.keys())
            logger.info(f"Retrieved {len(zones)} zones")
            return zones
        except Exception as e:
            logger.error(f"Error fetching zones list: {e}")
            return []
    
    def get_carbon_intensity(self, zone: str) -> Optional[Dict]:
        """
        Get current carbon intensity for a zone.
        Returns: {'zone': str, 'carbonIntensity': float, 'datetime': str, ...}
        """
        try:
            url = f'{self.base_url}/v3/carbon-intensity/latest'
            params = {'zone': zone}
            response = self.session.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            # Electricity Maps returns carbon intensity in gCO2eq/kWh
            carbon_intensity = data.get('carbonIntensity')
            if carbon_intensity is None:
                logger.warning(f"No carbon intensity data for zone {zone}")
                return None
            
            return {
                'zone': zone,
                'carbonIntensity': carbon_intensity,  # g CO2/kWh
                'datetime': data.get('datetime'),
                'updatedAt': data.get('updatedAt'),
                'createdAt': data.get('createdAt'),
                'emissionFactorType': data.get('emissionFactorType'),
                'isEstimated': data.get('isEstimated', False),
                'estimationMethod': data.get('estimationMethod'),
                'timestamp': datetime.now().isoformat()
            }
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 404:
                logger.warning(f"Zone {zone} not found or no data available")
            else:
                logger.error(f"HTTP error fetching carbon intensity for {zone}: {e}")
            return None
        except Exception as e:
            logger.error(f"Error fetching carbon intensity for {zone}: {e}")
            return None
    
    def get_forecast(self, zone: str) -> Optional[List[Dict]]:
        """
        Get carbon intensity forecast for a zone.
        """
        try:
            url = f'{self.base_url}/v3/carbon-intensity/forecast'
            params = {'zone': zone}
            response = self.session.get(url, params=params, timeout=10)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.error(f"Error fetching forecast for {zone}: {e}")
            return None


def get_zones_from_env() -> List[str]:
    """Get zones list from environment variable or use defaults."""
    zones_env = os.getenv('ZONES', '')
    if zones_env:
        return [z.strip() for z in zones_env.split(',') if z.strip()]
    return DEFAULT_ZONES


def poll_and_update_cache():
    """Poll Electricity Maps API and update cache."""
    if not ELECTRICITY_MAPS_API_KEY:
        logger.error("ELECTRICITY_MAPS_API_KEY environment variable not set!")
        return
    
    cache = CarbonIntensityCache(CACHE_FILE, CACHE_TTL_MINUTES)
    client = ElectricityMapsAPIClient(ELECTRICITY_MAPS_API_KEY)
    zones = get_zones_from_env()
    
    logger.info(f"Polling carbon intensity for {len(zones)} zones: {zones}")
    
    # Optional: Log available zones if there are errors (helpful for debugging)
    available_zones = None
    
    results = {}
    for zone in zones:
        logger.info(f"Fetching data for {zone}...")
        data = client.get_carbon_intensity(zone)
        if data:
            results[zone] = data
            carbon_intensity = data.get('carbonIntensity', 0)
            logger.info(f"{zone}: Carbon Intensity = {carbon_intensity} g CO2/kWh")
        else:
            logger.warning(f"Failed to fetch data for {zone}")
            # If zone not found, suggest fetching available zones
            if available_zones is None:
                try:
                    available_zones = client.get_zones()
                    logger.info(f"Available zones (sample): {sorted(available_zones)[:10]}...")
                    logger.info(f"Total available zones: {len(available_zones)}")
                    logger.info("See https://portal.electricitymaps.com/zones for full list")
                except Exception as e:
                    logger.debug(f"Could not fetch zones list: {e}")
        time.sleep(0.5)  # Rate limiting
    
    if results:
        # Sort zones by carbon intensity (lowest first)
        sorted_zones = sorted(results.items(), key=lambda x: x[1].get('carbonIntensity', float('inf')))
        
        cache_data = {
            'regions': dict(results),  # Keep 'regions' key for compatibility with scheduler
            'sorted_by_carbon': [z[0] for z in sorted_zones],
            'best_region': sorted_zones[0][0] if sorted_zones else None,
            'worst_region': sorted_zones[-1][0] if sorted_zones else None
        }
        
        cache.write_cache(cache_data)
        logger.info(f"Cache updated. Best zone: {cache_data['best_region']}")
    else:
        logger.error("No data retrieved, cache not updated")


def main():
    """Main loop: poll every N minutes."""
    logger.info("Starting Carbon Intensity API Poller (Electricity Maps)")
    logger.info(f"Poll interval: {POLL_INTERVAL_MINUTES} minutes")
    logger.info(f"Cache TTL: {CACHE_TTL_MINUTES} minutes")
    logger.info(f"Cache file: {CACHE_FILE}")
    
    # Initial poll
    poll_and_update_cache()
    
    # Poll every N minutes
    while True:
        try:
            time.sleep(POLL_INTERVAL_MINUTES * 60)
            poll_and_update_cache()
        except KeyboardInterrupt:
            logger.info("Shutting down...")
            break
        except Exception as e:
            logger.error(f"Error in main loop: {e}")
            time.sleep(60)  # Wait 1 minute before retrying


if __name__ == '__main__':
    main()

