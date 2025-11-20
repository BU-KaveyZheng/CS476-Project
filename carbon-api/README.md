# Carbon Intensity API Poller

This Python service polls the Electricity Maps API every N minutes to fetch carbon intensity data for multiple zones and writes the results to a cache file with TTL.

## Architecture

- **Publisher (Python)**: Polls Electricity Maps API → Writes to cache
- **Subscriber (Go Scheduler)**: Reads from cache → Makes scheduling decisions

## Configuration

### Environment Variables

- `ELECTRICITY_MAPS_API_KEY`: Your Electricity Maps API key (required)
- `POLL_INTERVAL_MINUTES`: How often to poll (default: 5)
- `CACHE_TTL_MINUTES`: Cache expiration time (default: 10)
- `CACHE_FILE`: Path to cache file (default: `/cache/carbon_cache.json`)
- `ZONES`: Comma-separated list of zone codes (default: US zones)

### Example Zones

- `US-CAL-CISO`: California ISO
- `US-TEX-ERCO`: Texas ERCOT (note: `ERCO` not `ERCOT`)
- `US-NY-NYISO`: New York ISO
- `US-MIDA-PJM`: PJM (Mid-Atlantic)
- `US-MIDW-MISO`: Midwest ISO

**Important**: Zone codes are case-sensitive and must match exactly. See [Electricity Maps Zones](https://portal.electricitymaps.com/zones) for the complete list of available zones.

You can also fetch available zones programmatically using the `/v3/zones` endpoint.

## Cache Format

```json
{
  "timestamp": "2024-01-01T12:00:00",
  "ttl_minutes": 10,
  "regions": {
    "US-CAL-CISO": {
      "zone": "US-CAL-CISO",
      "carbonIntensity": 250.5,
      "datetime": "2024-01-01T12:00:00Z",
      "updatedAt": "2024-01-01T12:00:00Z",
      "createdAt": "2024-01-01T12:00:00Z",
      "emissionFactorType": "lifecycle",
      "isEstimated": false,
      "timestamp": "2024-01-01T12:00:00"
    }
  },
  "sorted_by_carbon": ["US-NY-NYISO", "US-CAL-CISO", ...],
  "best_region": "US-NY-NYISO",
  "worst_region": "US-MIDW-MISO"
}
```

## Local Development

```bash
export ELECTRICITY_MAPS_API_KEY="your-api-key"
export POLL_INTERVAL_MINUTES=5
python carbon_poller.py
```

## Docker

```bash
docker build -t carbon-api:latest .
docker run -e ELECTRICITY_MAPS_API_KEY="your-key" carbon-api:latest
```

## Kubernetes

Update the secret in `k8s.yaml` with your API key, then deploy:

```bash
kubectl apply -f k8s.yaml
```

The cache is stored in a shared volume (`emptyDir`) that can be mounted by the scheduler pod.

