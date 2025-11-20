#!/bin/bash
# Quick test script for Carbon API

cd "$(dirname "$0")"

echo "🧪 Testing Carbon API Poller"
echo "============================"
echo ""

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Install dependencies if needed
if ! python3 -c "import requests" 2>/dev/null; then
    echo "Installing dependencies..."
    pip install -q -r requirements.txt
fi

# Load .env file if it exists
if [ -f ".env" ]; then
    echo "📄 Loading environment variables from .env file..."
    set -a  # automatically export all variables
    source .env
    set +a
fi

# Check if API key is set
if [ -z "$ELECTRICITY_MAPS_API_KEY" ]; then
    echo "❌ ERROR: ELECTRICITY_MAPS_API_KEY environment variable not set!"
    echo ""
    echo "Options to set your API key:"
    echo ""
    echo "1. Create a .env file:"
    echo "   cp env.example .env"
    echo "   # Then edit .env and add your API key"
    echo ""
    echo "2. Set environment variable:"
    echo "   export ELECTRICITY_MAPS_API_KEY='your-api-key-here'"
    echo ""
    echo "3. Inline (one-time use):"
    echo "   ELECTRICITY_MAPS_API_KEY='your-key' ./test-api.sh"
    echo ""
    exit 1
fi

# Set environment variables
export POLL_INTERVAL_MINUTES=1
export CACHE_TTL_MINUTES=10
# Cache file will default to ../cache/carbon_cache.json
export ZONES="US-CAL-CISO,US-TEX-ERCO,US-NY-NYIS,US-MIDA-PJM,US-MIDW-MISO"

echo "Configuration:"
echo "  API Key: ${ELECTRICITY_MAPS_API_KEY:0:8}... (hidden)"
echo "  Poll Interval: ${POLL_INTERVAL_MINUTES} minute(s)"
echo "  Cache TTL: ${CACHE_TTL_MINUTES} minutes"
echo "  Zones: ${ZONES}"
echo "  Cache file: Will be created in ../cache/carbon_cache.json"
echo ""
echo "Starting API poller..."
echo "Press Ctrl+C to stop after first poll completes (~70 seconds)"
echo ""

# Run the poller
python3 carbon_poller.py

