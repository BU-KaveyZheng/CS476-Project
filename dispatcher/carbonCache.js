// ===========================
// Latency Data (for reference)
// ===========================

const LATENCY_DATA = {
  source: "Binghamton, NY, USA",
  unit: "milliseconds",
  latencies: {
    "US-NY-NYIS": {
      region: "New York ISO",
      location: "New York, USA",
      latency_ms: 8,
      notes: "Very close geographic proximity, same state"
    },
    "US-MIDA-PJM": {
      region: "PJM Mid-Atlantic",
      location: "Mid-Atlantic USA (PA/NJ/MD)",
      latency_ms: 15,
      notes: "Adjacent region, excellent connectivity"
    },
    "US-NW-PACW": {
      region: "Pacific Northwest",
      location: "Washington/Oregon, USA",
      latency_ms: 65,
      notes: "Cross-country US, good domestic routing"
    },
    "US-CAL-CISO": {
      region: "California ISO",
      location: "California, USA",
      latency_ms: 70,
      notes: "Cross-country US, excellent domestic infrastructure"
    },
  }
};

const LATENCY_MAP = LATENCY_DATA.latencies;

// ===========================
// Carbon Intensity (in-memory)
// ===========================

const ELECTRICITY_MAPS_API_KEY = process.env.ELECTRICITY_MAPS_API_KEY || "";
const ELECTRICITY_MAPS_API_BASE = "https://api.electricitymaps.com";

const DEFAULT_ZONES = [
  "US-CAL-CISO",
  "US-TEX-ERCO",
  "US-NY-NYIS",
  "US-MIDA-PJM",
  "US-MIDW-MISO"
];

class CarbonRegionCache {
  constructor({ ttlMinutes = 10, zones = DEFAULT_ZONES, apiKey = ELECTRICITY_MAPS_API_KEY } = {}) {
    this.ttlMinutes = ttlMinutes;
    this.zones = zones;
    this.apiKey = apiKey;

    this.regionIntensity = null; // will hold the big dict
    this.expiry = new Date(0);
  }

  isValid() {
    return this.regionIntensity && this.expiry > new Date();
  }

  getBestRegion() {
    return this.regionIntensity?.regions?.best_region || null;
  }

  getRegionData(zone) {
    return this.regionIntensity?.regions?.regions?.[zone] || null;
  }

  getAllRegions() {
    return this.regionIntensity?.regions?.regions || {};
  }

  async ensureFresh() {
    if (!this.isValid()) {
      console.log(`[CarbonCache] Cache expired or empty, refreshing...`);
      await this.repoll();
    } else {
      const timeUntilExpiry = Math.round((this.expiry - new Date()) / 1000 / 60);
      console.log(`[CarbonCache] Cache valid. Expires in ${timeUntilExpiry} minutes`);
      this.logCacheState();
    }
    return this.regionIntensity;
  }

  logCacheState() {
    if (!this.regionIntensity) {
      console.log(`[CarbonCache] Cache is empty`);
      return;
    }

    const regions = this.regionIntensity.regions.regions;
    const sortedZones = this.regionIntensity.regions.sorted_by_carbon;
    
    console.log(`[CarbonCache] Current cache state:`);
    console.log(`  Timestamp: ${this.regionIntensity.timestamp}`);
    console.log(`  Expires: ${this.expiry.toISOString()}`);
    console.log(`  Best region: ${this.regionIntensity.regions.best_region} (${regions[this.regionIntensity.regions.best_region]?.carbonIntensity || 'N/A'} gCO₂eq/kWh)`);
    console.log(`  Regions (sorted by carbon intensity):`);
    
    sortedZones.forEach((zone, index) => {
      const region = regions[zone];
      if (region) {
        console.log(`    ${index + 1}. ${zone}: ${region.carbonIntensity} gCO₂eq/kWh`);
      }
    });
  }

  async repoll() {
    if (!this.apiKey) {
      console.error("ELECTRICITY_MAPS_API_KEY is not set");
      throw new Error("Missing ELECTRICITY_MAPS_API_KEY");
    }

    const now = new Date();
    const regions = {};

    for (const zone of this.zones) {
      try {
        const url = `${ELECTRICITY_MAPS_API_BASE}/v3/carbon-intensity/latest?zone=${encodeURIComponent(zone)}`;
        const res = await fetch(url, {
          headers: { "auth-token": this.apiKey }
        });

        if (!res.ok) {
          console.warn(`Failed to fetch ${zone}: ${res.status} ${res.statusText}`);
          continue;
        }

        const data = await res.json();
        const carbonIntensity = data.carbonIntensity;

        if (carbonIntensity == null) {
          console.warn(`No carbonIntensity for zone ${zone}`);
          continue;
        }

        regions[zone] = {
          zone,
          carbonIntensity,
          datetime: data.datetime,
          updatedAt: data.updatedAt,
          createdAt: data.createdAt,
          emissionFactorType: data.emissionFactorType,
          isEstimated: data.isEstimated ?? false,
          estimationMethod: data.estimationMethod ?? null,
          timestamp: new Date().toISOString(),
          // Add latency data if available
          latency: LATENCY_MAP[zone] || null
        };
      } catch (err) {
        console.error(`Error fetching zone ${zone}:`, err.message || err);
      }
    }

    const sortedZones = Object.entries(regions)
      .sort(([, a], [, b]) => (a.carbonIntensity ?? Infinity) - (b.carbonIntensity ?? Infinity))
      .map(([zone]) => zone);

    const best_region = sortedZones[0] || null;

    this.regionIntensity = {
      timestamp: now.toISOString(),
      ttl_minutes: this.ttlMinutes,
      regions: {
        regions,
        sorted_by_carbon: sortedZones,
        best_region
      }
    };

    this.expiry = new Date(now.getTime() + this.ttlMinutes * 60 * 1000);

    console.log(
      `[CarbonCache] ✅ Cache updated successfully!`
    );
    console.log(`  Best region: ${best_region} (${regions[best_region]?.carbonIntensity || 'N/A'} gCO₂eq/kWh)`);
    console.log(`  TTL: ${this.ttlMinutes} minutes (expires: ${this.expiry.toISOString()})`);
    console.log(`  Regions fetched: ${Object.keys(regions).length}/${this.zones.length}`);
    
    // Log detailed state
    this.logCacheState();

    return { expiry: this.expiry, best_region };
  }
}

const carbonCache = new CarbonRegionCache({
  ttlMinutes: Number(process.env.CACHE_TTL_MINUTES) || 10
});

export { carbonCache, CarbonRegionCache, LATENCY_MAP, LATENCY_DATA };

