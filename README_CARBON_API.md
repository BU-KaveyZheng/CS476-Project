# Carbon Intensity API Client

A Python client for the Electricity Maps Carbon Intensity API that allows you to retrieve real-time and forecasted carbon intensity data for different zones worldwide.

## Features

- **Recent Carbon Intensity**: Get historical carbon intensity data for a specific zone
- **Latest Carbon Intensity**: Get the most current carbon intensity data
- **Carbon Intensity Forecast**: Get predicted carbon intensity values
- **Zone Information**: List all available zones and their details
- **Command Line Interface**: Use the API client from the command line
- **Error Handling**: Comprehensive error handling and user-friendly messages

## Installation

1. Install the required dependencies:
```bash
pip install -r requirements.txt
```

2. Get your API key from [Electricity Maps API Portal](https://api-portal.electricitymaps.com/)

## Usage

### As a Python Module

```python
from carbon_intensity_api import CarbonIntensityAPI

# Initialize the client
api = CarbonIntensityAPI(api_key="your_api_key_here")

# Get latest carbon intensity for Germany
latest_data = api.get_carbon_intensity_latest('DE')
print(api.format_carbon_intensity_data(latest_data))

# Get recent carbon intensity for California
recent_data = api.get_carbon_intensity_recent('US-CA')
print(api.format_carbon_intensity_data(recent_data))

# Get forecast for France
forecast_data = api.get_carbon_intensity_forecast('FR')
print(api.format_carbon_intensity_data(forecast_data))
```

### Command Line Interface

```bash
# Get latest carbon intensity for Germany (default)
python carbon_intensity_api.py --api-key YOUR_API_KEY

# Get recent carbon intensity for California
python carbon_intensity_api.py --api-key YOUR_API_KEY --zone US-CA --type recent

# Get forecast for France
python carbon_intensity_api.py --api-key YOUR_API_KEY --zone FR --type forecast

# List all available zones
python carbon_intensity_api.py --api-key YOUR_API_KEY --type zones

# Output as JSON
python carbon_intensity_api.py --api-key YOUR_API_KEY --format json
```

### Environment Variable

You can also set your API key as an environment variable:

```bash
export ELECTRICITY_MAPS_API_KEY="your_api_key_here"
python carbon_intensity_api.py --zone DE --type latest
```

## API Endpoints

The client supports the following Electricity Maps API endpoints:

- `/v3/carbon-intensity/recent` - Recent carbon intensity data
- `/v3/carbon-intensity/latest` - Latest carbon intensity data  
- `/v3/carbon-intensity/forecast` - Carbon intensity forecast
- `/v3/zones` - Available zones

## Zone Examples

Some common zone identifiers:
- `DE` - Germany
- `US-CA` - California, USA
- `FR` - France
- `GB` - Great Britain
- `AU-NSW` - New South Wales, Australia

## Example Output

```
Latest carbon intensity for DE:
2024-01-15T10:30:00.000Z: 245 gCO₂eq/kWh

Recent carbon intensity for US-CA:
  2024-01-15T10:00:00.000Z: 180 gCO₂eq/kWh
  2024-01-15T09:30:00.000Z: 195 gCO₂eq/kWh
  2024-01-15T09:00:00.000Z: 210 gCO₂eq/kWh
```

## Error Handling

The client includes comprehensive error handling for:
- Missing API keys
- Invalid zone identifiers
- Network connectivity issues
- API rate limiting
- Invalid responses

## Requirements

- Python 3.6+
- requests library

## License

This project is part of the CS476 course project.
