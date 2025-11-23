#!/bin/bash

# Delete region-specific matrix-mult-service instances
REGIONS=("US-NY-NYIS" "US-MIDA-PJM" "US-NW-PACW" "US-CAL-CISO")

echo "🧹 Deleting region-specific matrix-mult-service instances..."
for region in "${REGIONS[@]}"; do
  # Convert region to lowercase for service/deployment names
  region_lower=$(echo "$region" | tr '[:upper:]' '[:lower:]')
  
  echo "  Deleting region: $region (service: matrix-mult-service-$region_lower)"
  # Replace {{REGION}} with actual region (uppercase for labels), {{REGION_LOWER}} with lowercase (for names)
  sed "s/{{REGION}}/$region/g" ./matrixmult-py/k8s-template.yaml | \
    sed "s/{{REGION_LOWER}}/$region_lower/g" | \
    kubectl delete -f - 2>/dev/null || echo "    (Already deleted or doesn't exist)"
done

echo "✅ Cleanup complete!"

