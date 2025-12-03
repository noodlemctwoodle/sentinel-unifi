# Sentinel UniFi Integration - Testing Guide

## Overview

This project integrates Ubiquiti UniFi network infrastructure with Microsoft Sentinel for security monitoring and network analytics. It consists of two main components:

1. **Linux Collector** - Bash scripts that collect data from UniFi controllers via API
2. **Azure DCRs** - Data Collection Rules that ingest data into Sentinel custom tables

## What This Solution Monitors

The integration collects 17 different data types from your UniFi network:

### Network Infrastructure

- **Devices** - Access points, switches, gateways (firmware, status, connectivity)
- **Networks** - VLANs, subnets, DHCP configuration
- **WiFi** - SSIDs, security settings, broadcasting configuration
- **Clients** - Connected wireless and wired devices

### Security & Access Control

- **Alarms** - Security alarms and IDS/IPS threat detections
- **Firewall Zones** - Network segmentation configuration
- **ACL Rules** - Access control policies
- **Traffic Lists** - IP/MAC address groups for firewall rules
- **RADIUS Profiles** - 802.1X authentication settings
- **Port Forwarding** - NAT/port forwarding rules

### Network Intelligence

- **DPI Categories** - Deep packet inspection traffic categories
- **DPI Applications** - Application-level traffic identification
- **WANs** - Internet connection configuration
- **VPN Servers** - VPN endpoint settings

### System Health & Events

- **Health** - System health metrics (WAN, LAN, WLAN, VPN status)
- **Events** - Real-time network events (device upgrades, client roaming, security alerts)

## Prerequisites for Testing

### Required Access & Resources

#### UniFi Environment

- [ ] UniFi Network Controller (on-premise or cloud)
- [ ] Controller administrative access (for API key generation)
- [ ] Controller Integration API v1 enabled
- [ ] Network connectivity from collector VM to controller (HTTPS/443)

#### Azure Environment

- [ ] Active Azure subscription
- [ ] Microsoft Sentinel workspace deployed
- [ ] Azure Arc-enabled VM (or Azure VM) for collector
- [ ] Azure Monitor Agent installed on collector VM
- [ ] Permissions to create DCRs and table schemas

#### Linux Collector VM

- [ ] Linux OS (Ubuntu 20.04+ or RHEL 8+ recommended)
- [ ] Azure Arc agent installed and connected
- [ ] Azure Monitor Agent installed
- [ ] `curl`, `jq`, `systemd` available
- [ ] Internet connectivity to Azure

### Minimum Permissions

**Azure Permissions:**

- `Microsoft.Insights/dataCollectionRules/write`
- `Microsoft.OperationalInsights/workspaces/tables/write`
- `Microsoft.HybridCompute/machines/read` (for Arc VMs)

**UniFi Permissions:**

- Full Administrator or read-only API access to all monitored sites

## Quick Start for Testers

### Phase 1: Generate UniFi API Key

1. Log into your UniFi Controller web interface
2. Navigate to **Settings → Admins**
3. Select your admin user
4. Scroll to **API Access**
5. Click **Generate API Key**
6. Copy the key (you won't see it again!)

### Phase 2: Deploy Azure Infrastructure

```bash
# Clone the repository
git clone <repository-url>
cd sentinel-unifi

# Set your parameters
RESOURCE_GROUP="rg-sentinel-test"
WORKSPACE_NAME="law-sentinel-unifi"
COLLECTOR_VM_NAME="vm-unifi-collector"
SUBSCRIPTION_ID="your-subscription-id"

# Deploy DCRs and tables
cd DCR
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file unifiedDeployment.json \
  --parameters \
    workspaceName="$WORKSPACE_NAME" \
    retentionInDays=90 \
    collectorVmResourceId="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.HybridCompute/machines/$COLLECTOR_VM_NAME"
```

**Expected Result:** 17 custom tables created in Sentinel with `_CL` suffix

### Phase 3: Install Collector on Linux VM

```bash
# SSH to your collector VM
ssh user@collector-vm-ip

# Download the installer
cd /tmp
git clone <repository-url>
cd sentinel-unifi/Collector

# Run automated installer
sudo bash install-collector.sh
```

**Installer will prompt for:**

- Site name (friendly name for this controller)
- Controller IP address
- Controller port (default: 443)
- Site name in controller (usually "default")
- API key (from Phase 1)

**Expected Result:**

- Collector installed to `/opt/unifi-collector/`
- Configuration saved to `/opt/unifi-collector/config/controllers.conf`
- 15 systemd timers enabled and started
- Log files created in `/var/log/unifi/`

### Phase 4: Verify Data Collection

Wait 5-10 minutes for initial data collection, then check:

#### On the Collector VM

```bash
# Check if services are running
systemctl list-timers | grep unifi-collector

# Check if log files are being created
ls -lh /var/log/unifi/
# Should see: devices_*.json, clients_*.json, networks_*.json, etc.

# Verify JSON structure
cat /var/log/unifi/devices_*.json | jq .
# Should show valid JSON with UniFi device data

# Check Azure Monitor Agent status
sudo systemctl status azuremonitoragent
# Should be active (running)

# Check AMA logs for DCR association
journalctl -u azuremonitoragent -n 100 | grep -i "data collection rule"
```

#### In Azure Sentinel

```kql
// Check if tables exist
search *
| where TimeGenerated > ago(1h)
| where TableName startswith "UniFi_"
| summarize count() by TableName
| sort by TableName asc

// Expected tables:
// UniFi_ACLRules_CL
// UniFi_Clients_CL
// UniFi_DeviceTags_CL
// UniFi_Devices_CL
// UniFi_DPIApplications_CL
// UniFi_DPICategories_CL
// UniFi_Events_CL
// UniFi_FirewallZones_CL
// UniFi_Health_CL
// UniFi_Networks_CL
// UniFi_PortForward_CL
// UniFi_RADIUSProfiles_CL
// UniFi_TrafficLists_CL
// UniFi_VPNServers_CL
// UniFi_WANs_CL
// UniFi_WiFi_CL
```

```kql
// Verify device data
UniFi_Devices_CL
| where TimeGenerated > ago(1h)
| summarize count() by model, state
```

```kql
// Verify event data with parsed fields
UniFi_Events_CL
| where TimeGenerated > ago(1h)
| summarize count() by eventCategory, severity, deviceType
```

## Testing Scenarios

### Scenario 1: Basic Data Collection (All Testers)

**Objective:** Verify all 17 endpoints are collecting data

**Steps:**

1. Wait 10 minutes after installation
2. Run verification query in Sentinel
3. Check that all 17 tables have data

**Expected Results:**

- All 17 `UniFi_*_CL` tables show records
- `TimeGenerated` is recent (< 10 minutes old)
- `CollectorSite` field matches your configured site name

### Scenario 2: Event Parsing Intelligence (Security Focus)

**Objective:** Verify event categorization and severity assignment

**Test Actions:**

1. Trigger a firmware upgrade on a test AP
2. Force a WiFi client to roam between APs
3. Disconnect and reconnect a client

**Verification Query:**

```kql
UniFi_Events_CL
| where TimeGenerated > ago(30m)
| project
    TimeGenerated,
    eventCategory,
    severity,
    deviceType,
    deviceName,
    versionFrom,
    versionTo,
    message
| sort by TimeGenerated desc
```

**Expected Results:**

- Firmware upgrade event shows `eventCategory = "FirmwareUpgrade"`
- Version fields (`versionFrom`, `versionTo`) are populated
- Roaming events show `eventCategory = "ClientRoaming"`
- Channel/radio changes are captured

### Scenario 3: Multi-Site Collection (Enterprise Testers)

**Objective:** Verify multiple UniFi sites are collected separately

**Steps:**

1. Add second site to `/opt/unifi-collector/config/controllers.conf`
2. Restart collector services: `sudo systemctl restart unifi-collector@devices.service`
3. Wait 10 minutes
4. Query Sentinel

**Verification Query:**

```kql
UniFi_Devices_CL
| summarize count() by CollectorSite
```

**Expected Results:**

- Each site shows as separate `CollectorSite` value
- Device counts match expected per site

### Scenario 4: Data Freshness & Reliability (All Testers)

**Objective:** Verify data collection intervals and reliability

**Monitoring Query (run multiple times over 1 hour):**

```kql
UniFi_Devices_CL
| summarize
    LatestData = max(TimeGenerated),
    OldestData = min(TimeGenerated),
    RecordCount = count()
    by CollectorSite
| extend
    DataAge = now() - LatestData,
    IsStale = DataAge > 10m
```

**Expected Results:**

- Data refreshes every 5 minutes for most endpoints
- Health data refreshes every 1 minute
- No gaps longer than 10 minutes (unless collector VM is offline)

### Scenario 5: High-Value Security Events (SOC Analysts)

**Objective:** Validate security-relevant event detection

**Test Scenarios:**

- Device readoption (unplug/replug AP)
- Client connection failures
- Firmware version mismatches

**Detection Query:**

```kql
UniFi_Events_CL
| where severity in ("High", "Medium")
| where eventCategory in ("SecurityError", "DeviceAdoption")
| project
    TimeGenerated,
    severity,
    eventCategory,
    deviceType,
    deviceName,
    message
| sort by TimeGenerated desc
```

**Expected Results:**

- High severity events trigger for security errors
- Device readoptions are flagged as low/medium severity
- Event messages are descriptive and actionable

## Common Issues & Troubleshooting

### Issue 1: No Data in Sentinel Tables

**Symptoms:**

- Tables exist but show 0 records
- Queries return empty results

**Diagnosis:**

```bash
# On collector VM
ls -lh /var/log/unifi/
# Files should be present and growing

tail -f /var/log/unifi/devices_*.json
# Should show JSON records

sudo journalctl -u azuremonitoragent -f
# Should show "data uploaded successfully"
```

**Possible Causes:**

- DCR not associated with VM
- Azure Monitor Agent not running
- Firewall blocking Azure endpoints
- Incorrect workspace ID in DCR

**Resolution:**

```bash
# Check DCR association
az monitor data-collection rule association list \
  --resource "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.HybridCompute/machines/$VM"

# Restart AMA
sudo systemctl restart azuremonitoragent
```

### Issue 2: Collector Failing to Reach Controller

**Symptoms:**

- Empty JSON files in `/var/log/unifi/`
- Service logs show "Connection refused" or "timeout"

**Diagnosis:**

```bash
# Test controller connectivity
curl -k "https://CONTROLLER_IP:443/api/s/default/stat/device" \
  -H "X-API-KEY: your-api-key"

# Check DNS resolution
nslookup CONTROLLER_IP

# Check firewall
sudo iptables -L OUTPUT -n | grep 443
```

**Possible Causes:**

- Incorrect controller IP/port
- Invalid API key
- Firewall blocking outbound HTTPS
- Controller not accepting API requests

**Resolution:**

1. Verify controller IP/port in `/opt/unifi-collector/config/controllers.conf`
2. Regenerate API key in UniFi Controller
3. Update config and restart: `sudo systemctl restart unifi-collector@devices.service`

### Issue 3: Events Not Parsing Correctly

**Symptoms:**

- `UniFi_Events_CL` table has data but fields like `deviceType`, `eventCategory` are empty

**Diagnosis:**

```kql
UniFi_Events_CL
| where TimeGenerated > ago(1h)
| project TimeGenerated, eventKey, RawData
| take 10
```

**Possible Causes:**

- DCR transformation not deployed
- Event schema changed in newer UniFi version

**Resolution:**

1. Redeploy DCR template with latest version
2. Check `RawData` field for actual event structure
3. Report schema mismatches as issues

### Issue 4: High Data Ingestion Costs

**Symptoms:**

- Unexpected Azure billing increases
- Large table sizes

**Diagnosis:**

```kql
// Check daily ingestion volume
let startDate = ago(7d);
union UniFi_*_CL
| where TimeGenerated > startDate
| summarize
    SizeMB = sum(_BilledSize) / 1024.0 / 1024.0
    by TableName, bin(TimeGenerated, 1d)
| render columnchart
```

**Possible Causes:**

- High-frequency collection for large networks
- Verbose event logging
- Multiple collectors sending duplicate data

**Resolution:**

1. Adjust collection intervals in systemd timers
2. Reduce retention period for verbose tables
3. Filter unnecessary events at collector level

## Performance Benchmarks

Expected data volumes (based on network size):

| Network Size | Devices | Daily Ingestion |
|--------------|---------|-----------------|
| Small (1-10 devices) | 10 | ~50 MB |
| Medium (10-50 devices) | 50 | ~200 MB |
| Large (50-200 devices) | 200 | ~800 MB |
| Enterprise (200+ devices) | 500+ | ~2 GB |

**Note:** Azure Log Analytics costs vary by region, commitment tier, and enterprise agreements. Consult the [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) for current pricing in your region.

## Reporting Issues

When reporting issues, please include:

### System Information

```bash
# On collector VM
uname -a
cat /etc/os-release
systemctl --version
jq --version
curl --version
```

### Collector Logs

```bash
# Service status
systemctl status unifi-collector@devices.service

# Recent logs
journalctl -u unifi-collector@devices.service -n 100

# Configuration (REDACT API KEY!)
cat /opt/unifi-collector/config/controllers.conf

# Sample output file
ls -lh /var/log/unifi/
head -n 5 /var/log/unifi/devices_*.json
```

### Azure Information

```bash
# DCR associations
az monitor data-collection rule association list --resource "<vm-resource-id>"

# Workspace ID
az monitor log-analytics workspace show --resource-group "$RG" --workspace-name "$WORKSPACE"
```

### Sentinel Query Results

```kql
// Table status
search *
| where TimeGenerated > ago(1h)
| where TableName startswith "UniFi_"
| summarize count() by TableName
```

## Additional Resources

- **Collector Documentation**: [Documentation/Collector/README.md](Documentation/Collector/README.md)
- **DCR Overview**: [Documentation/DCR/README.md](Documentation/DCR/README.md)
- **DCR Transformations**: [Documentation/DCR/TRANSFORMATIONS.md](Documentation/DCR/TRANSFORMATIONS.md)
- **Event Parsing Guide**: [Documentation/DCR/EVENTS-PARSING.md](Documentation/DCR/EVENTS-PARSING.md)

## Support & Feedback

For issues, questions, or feature requests, please open a GitHub issue with:

- Detailed description of the problem
- Steps to reproduce
- Collector and Azure logs
- Network environment details (number of devices, UniFi controller version)

**Current Version**: 2.1.0
**Last Updated**: December 2025
