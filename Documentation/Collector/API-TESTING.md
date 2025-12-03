# UniFi API Testing Guide

## Overview

The `test-integration-api.sh` script is a diagnostic tool that validates connectivity to your UniFi controller and tests all API endpoints used by the collector. This is useful for:

- **Pre-deployment validation** - Verify API access before installing the full collector
- **Troubleshooting** - Diagnose connectivity or authentication issues
- **API exploration** - Understand which endpoints return data for your environment
- **Version compatibility** - Compare Integration API v1 vs Legacy API responses

## What This Script Tests

The script performs comprehensive API testing:

### Integration API v1 Endpoints (12 endpoints)

- Sites discovery
- Devices, Clients, Networks, WiFi
- Traffic matching lists, Firewall zones, ACL rules
- RADIUS profiles, Device tags
- DPI categories and applications
- WANs, VPN servers

### Legacy API Endpoints (7 endpoints)

- Security alarms (IDS/IPS detections)
- Events (network activity)
- Port forwarding rules
- Routing configuration
- Site settings
- Health status
- Devices (legacy format)
- Clients (legacy format)

### Comparison Analysis

- Record count comparison between v1 and Legacy APIs
- Field structure analysis
- Data completeness validation

## Prerequisites

Before running the test script:

- [x] UniFi Controller accessible via HTTPS
- [x] Valid API key generated (see [README.md](README.md#generate-unifi-api-key))
- [x] Network connectivity from test machine to controller (port 443)
- [x] `curl` and `jq` installed on test machine

## Installation

The script is standalone and doesn't require installation:

```bash
# Download or copy the script
cd /path/to/sentinel-unifi/Collector

# Make it executable
chmod +x test-integration-api.sh

# Verify dependencies
which curl jq
```

## Running the Test

### Method 1: Environment Variables (Recommended)

```bash
# Set your controller details
export CONTROLLER_IP="192.0.2.10"      # Your controller IP
export API_KEY="your-api-key-here"     # From controller admin panel

# Run the test
./test-integration-api.sh
```

### Method 2: Inline Variables

```bash
CONTROLLER_IP="192.0.2.10" API_KEY="your-api-key-here" ./test-integration-api.sh
```

### Test Execution Flow

The script executes in 4 steps:

Step 1: Get Site UUID

- Tests connectivity to controller
- Retrieves site information
- Extracts site UUID needed for v1 API calls

Step 2: Test Integration API v1 Endpoints

- Tests all 12 v1 endpoints
- Saves responses to `./api-test-results/v1_*.json`
- Reports success/failure and record counts

Step 3: Test Legacy API Endpoints

- Tests 6 legacy endpoints
- Saves responses to `./api-test-results/legacy_*.json`
- Reports success/failure and record counts

Step 4: Generate Comparison Report

- Compares v1 vs Legacy record counts
- Identifies data discrepancies
- Provides next steps

## Understanding the Output

### Console Output

#### Successful Endpoint Test

```text
[INFO] Testing: /v1/sites/507f1f77bcf86cd799439011/devices
[SUCCESS] HTTP 200 | Records: 12
[INFO] Sample fields: ["id","macAddress","ipAddress","name","model","state"]
```

#### Failed Endpoint Test

```text
[INFO] Testing: /v1/sites/507f1f77bcf86cd799439011/acl-rules
[ERROR] HTTP 404 | Endpoint not found
```

#### Comparison Summary

```text
========================================
Data Comparison
========================================

Devices:
  Integration API v1: 12 records
  Legacy API: 12 records
[SUCCESS] Record counts match

Clients:
  Integration API v1: 45 records
  Legacy API: 48 records
[WARNING] Record count mismatch!
```

### Output Files

All responses are saved to `./api-test-results/`:

| File Pattern | Description | API Type |
|--------------|-------------|----------|
| `sites.json` | Site information and UUIDs | Integration v1 |
| `v1_devices.json` | Device data from v1 API | Integration v1 |
| `v1_clients.json` | Client data from v1 API | Integration v1 |
| `v1_networks.json` | Network config from v1 API | Integration v1 |
| `legacy_devices-legacy.json` | Device data from legacy API | Legacy |
| `legacy_clients-legacy.json` | Client data from legacy API | Legacy |
| `legacy_port-forward.json` | Port forwarding rules | Legacy |
| `legacy_health.json` | System health metrics | Legacy |

### Inspecting Output Files

#### View JSON Structure

```bash
# Pretty-print first record from devices endpoint
jq '.data[0]' ./api-test-results/v1_devices.json

# Count records
jq '.count' ./api-test-results/v1_devices.json

# List all field names
jq '.data[0] | keys' ./api-test-results/v1_devices.json
```

#### Check Response Format

```bash
# Integration API v1 format
{
  "count": 12,
  "data": [
    { "id": "...", "name": "...", ... }
  ]
}

# Legacy API format
{
  "data": [
    { "_id": "...", "name": "...", ... }
  ],
  "meta": { "rc": "ok" }
}
```

## Interpreting Results

### All Tests Pass ✅

```text
Integration API v1 Endpoints:
-----------------------------
devices                        ✓ (Records: 12)
clients                        ✓ (Records: 45)
networks                       ✓ (Records: 8)
wifi-broadcasts                ✓ (Records: 5)
...

Legacy API Endpoints:
-----------------------------
alarms                         ✓ (Records: 12)
events                         ✓ (Records: 156)
port-forward                   ✓ (Records: 3)
health                         ✓ (Records: 7)
...
```

**Meaning:** Your API key has full access, and all endpoints are working.

**Next Steps:**

1. Proceed with collector installation
2. Use the record counts to estimate data volume
3. Save the JSON files for schema reference

### Partial Success ⚠️

Some endpoints return data, others fail:

```text
devices                        ✓ (Records: 12)
clients                        ✓ (Records: 45)
acl-rules                      ✗ HTTP 404
vpn-servers                    ✗ HTTP 404
```

**Meaning:**

- Your API key works but may have limited permissions
- Some features aren't configured in your controller (e.g., no VPN servers)
- Some endpoints require specific UniFi OS versions

**Next Steps:**

1. Check if missing data is expected (e.g., no VPNs = no vpn-servers data)
2. Verify API key has admin permissions
3. Check UniFi Controller version (Integration API v1 requires UniFi OS 3.0+)

### Authentication Failure ❌

```text
[ERROR] Failed to get site UUID - cannot continue
[ERROR] HTTP 401 | Unauthorized
```

**Meaning:** API key is invalid or expired.

**Solution:**

1. Regenerate API key in UniFi Controller
2. Verify you copied the entire key (no spaces/truncation)
3. Check API key hasn't been revoked

### Connection Failure ❌

```text
[ERROR] HTTP 000 | Request failed
curl: (7) Failed to connect to 192.0.2.10 port 443: Connection refused
```

**Meaning:** Cannot reach controller.

**Solution:**

1. Verify controller IP address
2. Check firewall rules allow outbound HTTPS (port 443)
3. Verify controller is online: `ping 192.0.2.10`
4. Test HTTPS access: `curl -k https://192.0.2.10:443`

## Common Issues

### Issue 1: Record Count Mismatches Between v1 and Legacy

**Symptom:**

```text
Clients:
  Integration API v1: 45 records
  Legacy API: 48 records
[WARNING] Record count mismatch!
```

**Possible Causes:**

- Legacy API includes disconnected clients (historical data)
- Integration API v1 only shows currently connected clients
- API pagination (unlikely with default limits)

**Solution:**

- This is often expected behavior
- The collector uses v1 API where available
- Check `./api-test-results/` files to see which records differ

### Issue 2: Empty Data Arrays

**Symptom:**

```text
[SUCCESS] HTTP 200 | Records: 0
```

**Meaning:** Endpoint works but no data exists.

**Common Reasons:**

- `acl-rules` - No custom ACL rules created via API
- `vpn-servers` - No VPN endpoints configured
- `device-tags` - No tags applied to devices
- `hotspot-vouchers` - No guest vouchers active

**Action:** This is normal if you haven't configured these features.

### Issue 3: 404 Errors on Valid Endpoints

**Symptom:**

```text
[ERROR] HTTP 404 | Endpoint not found
```

**Possible Causes:**

1. **UniFi OS version too old** - Integration API v1 requires UniFi OS 3.0+
2. **Cloud controller differences** - Some endpoints behave differently on cloud
3. **Network Application version** - Older versions missing newer endpoints

**Solution:**

```bash
# Check controller version
curl -k "https://$CONTROLLER_IP:443/proxy/network/api/s/default/stat/sysinfo" \
  -H "X-API-Key: $API_KEY" | jq '.data[0].version'

# Required: UniFi Network Application 7.3+ or UniFi OS 3.0+
```

### Issue 4: SSL Certificate Errors

**Symptom:**

```text
curl: (60) SSL certificate problem: self-signed certificate
```

**Note:** The script uses `-k` flag to ignore SSL certificate validation. If you're still seeing this:

**Solution:**

```bash
# Verify curl version supports -k flag
curl --version

# Test with explicit --insecure flag
curl --insecure "https://$CONTROLLER_IP:443/proxy/network/api/s/default/stat/device" \
  -H "X-API-Key: $API_KEY"
```

## Integration API v1 vs Legacy API

### When to Use Each API

| Feature | Integration API v1 | Legacy API | Collector Uses |
|---------|-------------------|------------|----------------|
| Devices | ✅ Preferred | ✅ Available | v1 |
| Clients | ✅ Preferred | ✅ Available | v1 |
| Networks | ✅ Preferred | ✅ Available | v1 |
| WiFi | ✅ Preferred | ✅ Available | v1 |
| Port Forwarding | ❌ Not available | ✅ Only option | Legacy |
| Health Metrics | ❌ Not available | ✅ Only option | Legacy |
| Events | ✅ Preferred | ✅ Available | v1 |
| Firewall Rules | ✅ Preferred (ACL) | ✅ Available | v1 |

### Key Differences

**Integration API v1:**

- Modern RESTful design
- Consistent schema across endpoints
- Better field naming (camelCase)
- Pagination support
- Official Ubiquiti support

**Legacy API:**

- Older design, less consistent
- Some endpoints only available here
- Underscore field names (`_id`, `_source`)
- Will be deprecated eventually

### Collector Strategy

The collector uses a **hybrid approach**:

1. Integration API v1 for all modern endpoints (12 endpoints)
2. Legacy API only where necessary (3 endpoints: port-forward, health, events)

## Using Test Results

### Schema Design

The JSON output files are useful for understanding field structures:

```bash
# Extract all field names from devices
jq '[.data[] | keys] | add | unique' ./api-test-results/v1_devices.json

# Find device models in your network
jq '.data[].model' ./api-test-results/v1_devices.json | sort -u

# Check network purposes
jq '.data[].purpose' ./api-test-results/v1_networks.json | sort -u
```

### Data Volume Estimation

Use record counts to estimate data ingestion volume:

```bash
# Sum all record counts
for file in ./api-test-results/v1_*.json; do
  echo "$(basename $file): $(jq '.count // 0' $file) records"
done | awk '{sum+=$2} END {print "Total: " sum " records per collection cycle"}'
```

**Example Calculation:**

- 100 total records per cycle
- 12 collections per hour (5min interval)
- 1,200 records/hour × 24 hours = 28,800 records/day
- Average record size: ~2 KB
- Estimated daily ingestion: ~56 MB/day

**Note:** Use this volume estimate to plan your Azure Log Analytics deployment. See the main [Performance Benchmarks](../../README.md#performance-benchmarks) for typical data volumes by network size.

### Troubleshooting Collector Issues

If the collector isn't working, run this test script to isolate the issue:

```bash
# Use same credentials as collector
export CONTROLLER_IP="192.0.2.10"
export API_KEY="your-key"

./test-integration-api.sh

# If test script works but collector doesn't:
# - Check collector logs: journalctl -u unifi-collector@devices.service
# - Verify collector config: cat /opt/unifi-collector/config/controllers.conf
# - Check file permissions: ls -la /var/log/unifi/
```

## Advanced Usage

### Testing Multiple Controllers

```bash
# Test controller 1
CONTROLLER_IP="192.0.2.10" API_KEY="key1" ./test-integration-api.sh
mv ./api-test-results ./api-test-results-site1

# Test controller 2
CONTROLLER_IP="192.0.2.20" API_KEY="key2" ./test-integration-api.sh
mv ./api-test-results ./api-test-results-site2

# Compare results
diff <(jq '.count' ./api-test-results-site1/v1_devices.json) \
     <(jq '.count' ./api-test-results-site2/v1_devices.json)
```

### Automated Testing

```bash
#!/bin/bash
# Test script for CI/CD pipelines

CONTROLLER_IP="192.0.2.10"
API_KEY="$UNIFI_API_KEY"  # From environment

# Run test
if ./test-integration-api.sh > test-output.log 2>&1; then
  echo "✅ API test passed"
  exit 0
else
  echo "❌ API test failed"
  cat test-output.log
  exit 1
fi
```

### Custom Endpoint Testing

To test a specific endpoint not in the script:

```bash
# Test custom endpoint
CONTROLLER_IP="192.0.2.10"
API_KEY="your-key"
SITE_UUID="507f1f77bcf86cd799439011"

curl -k "https://${CONTROLLER_IP}:443/proxy/network/integration/v1/sites/${SITE_UUID}/your-endpoint" \
  -H "X-API-Key: ${API_KEY}" \
  -H "Accept: application/json" | jq .
```

## Next Steps

After running the API test:

### If All Tests Pass

1. Proceed with [collector installation](README.md#installation)
2. Configure controllers.conf with your credentials
3. Deploy DCRs to Azure (see [../DCR/README.md](../DCR/README.md))

### If Tests Fail

1. Review error messages in console output
2. Check [Common Issues](#common-issues) section
3. Verify UniFi Controller version and API key permissions
4. Open GitHub issue with test output if you need help

### For API Exploration

1. Review JSON files in `./api-test-results/`
2. Understand your network's data structure
3. Customize collector or transformations as needed

## Additional Resources

- **Collector Setup Guide**: [README.md](README.md)
- **DCR Deployment**: [../DCR/README.md](../DCR/README.md)
- **Main Testing Guide**: [../../README.md](../../README.md)

## Support

For API testing issues:

1. Run the test script with your credentials
2. Save the console output and `./api-test-results/` directory
3. Open a GitHub issue with:
   - Controller type (UDM-Pro, CloudKey, self-hosted, etc.)
   - UniFi OS version
   - Network Application version
   - Test output and any error messages

**Current Version:** 2.1.0
**Last Updated:** December 2025
