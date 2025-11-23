import express from "express";
import cors from "cors";
import { createProxyMiddleware } from "http-proxy-middleware";
import dotenv from "dotenv";
import { carbonCache, LATENCY_MAP } from "./carbonCache.js";

// Load environment variables from .env file
dotenv.config();

// List of regions that are actually deployed as services
const DEPLOYED_REGIONS = [
  "US-NY-NYIS",
  "US-MIDA-PJM",
  "US-NW-PACW",
  "US-CAL-CISO"
];

const app = express();
const port = process.env.PORT || 8080;

// Enable CORS for specific routes
// app.use(cors({
//   origin: 'http://localhost:3000',
//   credentials: true
// }));

// ONLY FOR DEVELOPMENT - allows all routes
app.use(cors()); 

//    kubectl logs -f deployment/dispatcher to check if api calls are being made
// Get carbon intensity for a specific zone (uses cache)
async function getCarbonIntensity(zone = 'US-NY-NYIS') {
  try {
    // Ensure cache is fresh
    await carbonCache.ensureFresh();
    
    // Get data for the specific zone
    const regionData = carbonCache.getRegionData(zone);
    
    if (regionData) {
      return {
        carbonIntensity: regionData.carbonIntensity,
        zone: regionData.zone,
        datetime: regionData.datetime,
        updatedAt: regionData.updatedAt
      };
    }
    
    // If zone not in cache, return null
    console.warn(`⚠️  Zone ${zone} not found in cache`);
    return null;
  } catch (error) {
    console.error(`❌ Failed to get carbon intensity: ${error.message}`);
    return null;
  }
}

// Endpoint to get current carbon intensity for a specific zone
app.get("/carbon-intensity", async (req, res) => {
  const zone = req.query.zone || 'US-NY-NYIS';
  const carbonData = await getCarbonIntensity(zone);
  
  if (carbonData) {
    res.json(carbonData);
  } else {
    res.status(503).json({ 
      error: 'Failed to fetch carbon intensity data',
      message: 'Please check ELECTRICITY_MAPS_API_KEY is set correctly or zone may not be in cache'
    });
  }
});

// Endpoint to get all cached carbon intensity data
app.get("/carbon-intensity/all", async (req, res) => {
  try {
    await carbonCache.ensureFresh();
    const cacheData = carbonCache.regionIntensity;
    
    if (cacheData) {
      res.json(cacheData);
    } else {
      res.status(503).json({ 
        error: 'Cache not available',
        message: 'Please check ELECTRICITY_MAPS_API_KEY is set correctly'
      });
    }
  } catch (error) {
    res.status(503).json({ 
      error: 'Failed to fetch carbon intensity data',
      message: error.message
    });
  }
});

// Endpoint to get best/worst regions
app.get("/carbon-intensity/best", async (req, res) => {
  try {
    await carbonCache.ensureFresh();
    const bestRegion = carbonCache.getBestRegion();
    const regionData = bestRegion ? carbonCache.getRegionData(bestRegion) : null;
    
    if (regionData) {
      res.json({
        zone: bestRegion,
        ...regionData
      });
    } else {
      res.status(503).json({ 
        error: 'Best region not available',
        message: 'Cache may not be populated'
      });
    }
  } catch (error) {
    res.status(503).json({ 
      error: 'Failed to get best region',
      message: error.message
    });
  }
});

// Endpoint to manually refresh cache
app.post("/carbon-intensity/refresh", async (req, res) => {
  try {
    const result = await carbonCache.repoll();
    res.json({
      success: true,
      message: 'Cache refreshed',
      ...result
    });
  } catch (error) {
    res.status(500).json({ 
      error: 'Failed to refresh cache',
      message: error.message
    });
  }
});

// Check if a service is available/free (not busy)
// Directly queries the /status endpoint to get the actual busy status
async function isServiceAvailable(serviceName, timeoutMs = 500) {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    
    // Query the /status endpoint to get the actual busy status
    const response = await fetch(`http://${serviceName}:3000/status`, {
      method: 'GET',
      signal: controller.signal
    });
    
    clearTimeout(timeoutId);
    
    if (!response.ok) {
      console.log(`   ❌ ${serviceName}: Unhealthy (status: ${response.status})`);
      return false;
    }
    
    const statusData = await response.json();
    const isBusy = statusData.busy === true;
    
    if (isBusy) {
      console.log(`   ⚠️  ${serviceName}: Busy (status: ${statusData.status || 'unknown'})`);
      return false;
    }
    
    console.log(`   ✅ ${serviceName}: Available (not busy, status: ${statusData.status || 'ready'})`);
    return true;
  } catch (error) {
    // Service doesn't exist, is unreachable, or timed out
    if (error.name === 'AbortError') {
      console.log(`   ❌ ${serviceName}: Timeout (no response within ${timeoutMs}ms)`);
    } else if (error instanceof TypeError) {
      console.log(`   ❌ ${serviceName}: Unavailable (service not found or network error)`);
    } else {
      console.log(`   ❌ ${serviceName}: Unavailable (${error.name}: ${error.message})`);
    }
    return false;
  }
}

// Get the best zone based on critical flag
async function getBestZone(isCritical, serviceName) {
  if (isCritical) {
    // Critical: find zone with lowest latency that is NOT busy
    // Only check regions that are actually deployed
    const zonesWithLatency = Object.entries(LATENCY_MAP)
      .filter(([zone, data]) => 
        DEPLOYED_REGIONS.includes(zone) && // Only check deployed regions
        data && 
        data.latency_ms !== undefined
      )
      .sort(([, a], [, b]) => a.latency_ms - b.latency_ms);
    
    if (zonesWithLatency.length > 0) {
      // Only check availability for region-specific services (like matrix-mult-service)
      const isRegionSpecificService = serviceName === 'matrix-mult-service';
      
      if (isRegionSpecificService) {
        console.log(`🔍 Checking availability for critical request (region-specific service)...`);
        
        // Check each zone in order of latency until we find one that's free
        let checkedCount = 0;
        for (const [zone, latencyData] of zonesWithLatency) {
          checkedCount++;
          // Convert zone to lowercase for service name (Kubernetes requires lowercase)
          const zoneLower = zone.toLowerCase();
          const regionServiceName = `${serviceName}-${zoneLower}`;
          
          console.log(`   [${checkedCount}/${zonesWithLatency.length}] Checking ${zone} (${latencyData.latency_ms}ms latency)...`);
          const isAvailable = await isServiceAvailable(regionServiceName);
        
          if (isAvailable) {
            console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
            console.log(`🚨 CRITICAL REQUEST - Region Selection:`);
            console.log(`   Selected Region: ${zone}`);
            console.log(`   Service Name: ${regionServiceName}`);
            console.log(`   Reason: Lowest latency (${latencyData.latency_ms}ms) AND available (not busy)`);
            console.log(`   Location: ${latencyData.location}`);
            console.log(`   Notes: ${latencyData.notes}`);
            console.log(`   Service Status: ✅ Available and responsive`);
            console.log(`   Zones checked: ${checkedCount}/${zonesWithLatency.length}`);
            if (checkedCount > 1) {
              console.log(`   Note: ${checkedCount - 1} lower latency zone(s) were busy/unavailable`);
            }
            console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
            
            return zone;
          } else {
            console.log(`   ⚠️  ${zone} (${latencyData.latency_ms}ms) is busy or unavailable, checking next...`);
          }
        }
      
        // If all zones are busy, use the lowest latency one anyway
        const bestZone = zonesWithLatency[0][0];
        const latencyData = zonesWithLatency[0][1];
        console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
        console.log(`🚨 CRITICAL REQUEST - Region Selection:`);
        console.log(`   Selected Region: ${bestZone}`);
        console.log(`   Reason: Lowest latency (${latencyData.latency_ms}ms) - ALL regions busy, using best available`);
        console.log(`   ⚠️  Warning: All regions checked, but all appear busy`);
        console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
        
        return bestZone;
      } else {
        // For non-region-specific services, just use lowest latency
        const bestZone = zonesWithLatency[0][0];
        const latencyData = zonesWithLatency[0][1];
        
        console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
        console.log(`🚨 CRITICAL REQUEST - Region Selection:`);
        console.log(`   Selected Region: ${bestZone}`);
        console.log(`   Reason: Lowest latency (${latencyData.latency_ms}ms)`);
        console.log(`   Location: ${latencyData.location}`);
        console.log(`   Notes: ${latencyData.notes}`);
        console.log(`   Note: Service is not region-specific, using best latency region`);
        console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
        
        return bestZone;
      }
    }
    // Fallback to default zone (New York)
    console.warn(`⚠️  No latency data available, using default zone US-NY-NYIS`);
    return 'US-NY-NYIS';
  } else {
    // Non-critical: use lowest carbon intensity region
    try {
      const bestRegion = carbonCache.getBestRegion();
      if (bestRegion) {
        const regionData = carbonCache.getRegionData(bestRegion);
        const allRegions = carbonCache.getAllRegions();
        const sortedRegions = Object.entries(allRegions)
          .sort(([, a], [, b]) => (a.carbonIntensity ?? Infinity) - (b.carbonIntensity ?? Infinity));
        
        console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
        console.log(`🌱 NON-CRITICAL REQUEST - Region Selection:`);
        console.log(`   Selected Region: ${bestRegion}`);
        console.log(`   Reason: Lowest carbon intensity (${regionData?.carbonIntensity || 'N/A'} gCO₂eq/kWh)`);
        console.log(`   Carbon Intensity: ${regionData?.carbonIntensity || 'N/A'} gCO₂eq/kWh`);
        console.log(`   Updated At: ${regionData?.updatedAt || 'N/A'}`);
        console.log(`   Available regions considered: ${sortedRegions.length}`);
        if (sortedRegions.length > 1) {
          console.log(`   Alternative regions (sorted by carbon intensity):`);
          sortedRegions.slice(1, 4).forEach(([zone, data], idx) => {
            console.log(`     ${idx + 2}. ${zone}: ${data.carbonIntensity} gCO₂eq/kWh`);
          });
        }
        console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
        
        return bestRegion;
      }
    } catch (error) {
      console.warn(`⚠️  Could not get best carbon region: ${error.message}`);
    }
    // Fallback to default (New York)
    console.warn(`⚠️  Using fallback zone: US-NY-NYIS`);
    return 'US-NY-NYIS';
  }
}

async function targetForRequest(req) {
  const service = req.query.service; 
  if (!service) return null;

  // Check if request is critical (defaults to false)
  const isCritical = req.query.critical === 'true' || req.query.critical === '1';
  
  console.log(`\n📥 New Request Received:`);
  console.log(`   Service: ${service}`);
  console.log(`   Critical Flag: ${isCritical ? 'YES' : 'NO'}`);
  
  // Ensure cache is fresh for non-critical requests
  if (!isCritical) {
    await carbonCache.ensureFresh();
  }
  
  // Get the best zone based on critical flag
  const zone = await getBestZone(isCritical, service);
  
  // Get carbon intensity data for the selected zone
  const carbonData = await getCarbonIntensity(zone);
  
  // Store carbon intensity and routing info in request
  req.carbonIntensity = carbonData;
  req.selectedZone = zone;
  req.isCritical = isCritical;
  
  if (isCritical && LATENCY_MAP[zone]) {
    req.latency = LATENCY_MAP[zone].latency_ms;
  }

  // For matrix-mult-service, route to region-specific service instance
  // For other services, use the service name as-is
  let targetService = service;
  let finalZone = zone;
  
  if (service === 'matrix-mult-service') {
    // Convert zone to lowercase for service name (Kubernetes requires lowercase)
    const zoneLower = zone.toLowerCase();
    targetService = `${service}-${zoneLower}`;
    
    // Verify the service exists by checking availability
    // If it doesn't exist or is busy, try next lowest latency region
    const serviceExists = await isServiceAvailable(targetService, 300);
    
    if (!serviceExists) {
      console.warn(`⚠️  Region-specific service ${targetService} not available (doesn't exist or busy)`);
      console.log(`🔄 Trying next lowest latency region...`);
      
      // Get all DEPLOYED zones sorted by latency and find the next available one
      const zonesWithLatency = Object.entries(LATENCY_MAP)
        .filter(([z, data]) => 
          DEPLOYED_REGIONS.includes(z) && // Only check deployed regions
          data && 
          data.latency_ms !== undefined
        )
        .sort(([, a], [, b]) => a.latency_ms - b.latency_ms);
      
      // Find current zone index and try next ones
      const currentIndex = zonesWithLatency.findIndex(([z]) => z === zone);
      let foundAlternative = false;
      
      for (let i = currentIndex + 1; i < zonesWithLatency.length; i++) {
        const [nextZone, nextLatencyData] = zonesWithLatency[i];
        const nextZoneLower = nextZone.toLowerCase();
        const nextServiceName = `${service}-${nextZoneLower}`;
        
        console.log(`   Trying ${nextZone} (${nextLatencyData.latency_ms}ms latency)...`);
        const nextAvailable = await isServiceAvailable(nextServiceName, 300);
        
        if (nextAvailable) {
          targetService = nextServiceName;
          finalZone = nextZone;
          console.log(`✅ Found available region: ${nextZone} (${nextLatencyData.latency_ms}ms)`);
          foundAlternative = true;
          break;
        } else {
          console.log(`   ⚠️  ${nextZone} also unavailable, trying next...`);
        }
      }
      
      if (!foundAlternative) {
        console.warn(`⚠️  All region-specific services unavailable, falling back to base service: ${service}`);
        targetService = service;
        console.log(`✅ Routing decision complete - Target: ${targetService}:3000 (fallback to base service)`);
      } else {
        console.log(`✅ Routing decision complete - Target: ${targetService}:3000 (region: ${finalZone}, alternative region)`);
      }
    } else {
      console.log(`✅ Routing decision complete - Target: ${targetService}:3000 (region: ${zone}, service: ${targetService})`);
    }
  } else {
    console.log(`✅ Routing decision complete - Target: ${service}:3000`);
  }
  
  // Update the zone in request if we switched to an alternative region
  if (finalZone !== zone && service === 'matrix-mult-service') {
    req.selectedZone = finalZone;
    console.log(`📝 Updated selected zone from ${zone} to ${finalZone} (service availability)`);
  }
  console.log(`\n`);

  // construct URL dynamically
  const port = 3000;
  return `http://${targetService}:${port}`;
};

// Middleware
app.use("/proxy", async (req, res, next) => {
  try {
    const target = await targetForRequest(req);
    if (!target) {
      return res.status(404).json({ 
        error: "No matching backend",
        message: `Service not found or invalid request`
      });
    }
    
    // strip the /proxy path
    req.url = req.url.replace(/^\/proxy/, "") 

    return createProxyMiddleware({
      target,
      changeOrigin: true,
      pathRewrite: { '^/proxy': '' },
      onProxyRes: function(proxyRes, req, res) {
        proxyRes.headers['access-control-allow-origin'] = '*';
        proxyRes.headers['access-control-allow-credentials'] = 'true';
        
        // Add routing metadata to response headers
        if (req.isCritical) {
          proxyRes.headers['x-routing-mode'] = 'critical';
          proxyRes.headers['x-selected-zone'] = req.selectedZone;
          if (req.latency) {
            proxyRes.headers['x-latency-ms'] = req.latency.toString();
          }
        } else {
          proxyRes.headers['x-routing-mode'] = 'carbon-aware';
          proxyRes.headers['x-selected-zone'] = req.selectedZone;
        }
        
        // Add carbon intensity to response headers if available
        if (req.carbonIntensity) {
          proxyRes.headers['x-carbon-intensity'] = req.carbonIntensity.carbonIntensity;
          proxyRes.headers['x-carbon-zone'] = req.carbonIntensity.zone;
          proxyRes.headers['x-carbon-datetime'] = req.carbonIntensity.datetime;
        }
      },
      onError: function(err, req, res) {
        console.error(`❌ Proxy error: ${err.message}`);
        res.status(502).json({
          error: "Proxy error",
          message: err.message,
          target: req.target || "unknown"
        });
      }
    })(req, res, next);
  } catch (error) {
    console.error(`❌ Error in proxy middleware: ${error.message}`);
    res.status(500).json({
      error: "Internal server error",
      message: error.message
    });
  }
});

app.listen(port, () => {
  console.log(`Dispatcher listening on port ${port}`);
});
