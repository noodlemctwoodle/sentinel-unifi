# UniFi - DCR Transformation Optimizations

## Overview

The unified deployment template now includes optimized KQL transformations for all 17 DCRs. These transformations handle:

- **Type conversion** (datetime, boolean, integer)
- **JSON parsing** for dynamic fields
- **Schema validation** with explicit column projection
- **Compatibility** with Integration API v1 and Legacy API schema variations

## Transformation Strategy

### Clean Tables (12 tables)

Simple schemas with consistent field structures from Integration API v1:

- Type conversion for booleans, integers, datetimes
- JSON parsing for dynamic arrays/objects
- Explicit column projection for validation

### Messy Tables (3 tables)

Complex schemas with multiple variations within the same table:

- Parse only common stable fields
- Keep schema variations in RawData for flexibility
- Allow null values for optional fields

## Table Transformations

### 1. UniFi_Devices_CL (Clean - Integration API v1)

**Transformations:**

- `supported`, `firmwareUpdatable` → boolean
- `features`, `interfaces` → parsed dynamic
- `RawData` → parsed dynamic

**Fields:** id, macAddress, ipAddress, name, model, state, supported, firmwareVersion, firmwareUpdatable, features, interfaces, RawData

---

### 2. UniFi_Clients_CL (Clean - Integration API v1)

**Transformations:**

- `connectedAt` → datetime
- `RawData` → parsed dynamic

**Fields:** id, clientType, name, connectedAt, ipAddress, macAddress, uplinkDeviceId, accessType, RawData

---

### 3. UniFi_Networks_CL (Messy - Integration API v1)

**Schema Variations:** 10+ network types (WAN, LAN, VPN, Guest, Corporate)

**Transformations:**

- `enabled`, `metadataConfigurable` → boolean
- `vlanId` → integer
- `RawData` → parsed dynamic (contains all 50+ variable fields)

**Common Fields:** id, name, management, enabled, vlanId, metadataOrigin, metadataConfigurable, RawData

**Variable Fields in RawData:**

- DHCP configuration (dhcp_enabled, dhcp_start, dhcp_stop, dhcp_dns, etc.)
- IPv6 configuration (ipv6_interface_type, ipv6_ra_enabled, etc.)
- VPN settings (vpn_type, remote_vpn_endpoint, etc.)
- WAN failover settings (wan_load_balance_type, wan_networkgroup, etc.)

---

### 4. UniFi_WiFi_CL (Messy - Integration API v1)

**Schema Variations:** 6+ SSID configuration types (Open, WPA2-Personal, WPA2-Enterprise, Guest Portal)

**Transformations:**

- `enabled` → boolean
- `broadcastingFrequencies` → parsed dynamic array
- `RawData` → parsed dynamic (contains all optional enterprise fields)

**Common Fields:** id, name, wifiType, enabled, networkType, securityType, broadcastingFrequencies, metadataOrigin, RawData

**Variable Fields in RawData:**

- Security configuration (wpa_mode, wpa_enc, radius_profile_id)
- Guest portal settings (guest_access, portal_enabled, redirect_enabled)
- Enterprise features (802.1x settings, RADIUS configuration)
- Scheduling (schedule_enabled, schedule rules)

---

### 5. UniFi_TrafficLists_CL (Clean - Integration API v1)

**Transformations:**

- `items` → parsed dynamic array
- `RawData` → parsed dynamic

**Fields:** id, name, listType, items, RawData

**Note:** This replaces the Legacy API firewall-groups endpoint with Integration API v1 traffic-matching-lists.

---

### 6. UniFi_FirewallZones_CL (Clean - Integration API v1)

**Transformations:**

- `networkIds` → parsed dynamic array
- `metadataConfigurable` → boolean
- `RawData` → parsed dynamic

**Fields:** id, name, networkIds, metadataOrigin, metadataConfigurable, RawData

---

### 7. UniFi_ACLRules_CL (Clean - Integration API v1)

**Transformations:**

- `enabled` → boolean
- `index` → integer
- `RawData` → parsed dynamic

**Fields:** id, name, ruleType, enabled, action, index, description, metadataOrigin, RawData

**Note:** Only returns API-created custom rules. UI-created firewall rules are not accessible via API.

---

### 8. UniFi_RADIUSProfiles_CL (Clean - Integration API v1)

**Transformations:**

- `metadataConfigurable` → boolean
- `RawData` → parsed dynamic

**Fields:** id, name, metadataOrigin, metadataConfigurable, RawData

---

### 9. UniFi_DeviceTags_CL (Clean - Integration API v1)

**Transformations:**

- `deviceIds` → parsed dynamic array
- `RawData` → parsed dynamic

**Fields:** id, name, deviceIds, metadataOrigin, RawData

---

### 10. UniFi_DPICategories_CL (Clean - Integration API v1)

**Transformations:**

- `categoryId` → integer
- `RawData` → parsed dynamic

**Fields:** categoryId, categoryName, RawData

---

### 11. UniFi_DPIApplications_CL (Clean - Integration API v1)

**Transformations:**

- `applicationId` → integer
- `RawData` → parsed dynamic

**Fields:** applicationId, applicationName, RawData

---

### 12. UniFi_WANs_CL (Clean - Integration API v1)

**Transformations:**

- `RawData` → parsed dynamic

**Fields:** id, name, RawData

---

### 13. UniFi_VPNServers_CL (Clean - Integration API v1)

**Transformations:**

- `enabled` → boolean
- `RawData` → parsed dynamic

**Fields:** id, name, vpnType, enabled, metadataOrigin, RawData

---

### 14. UniFi_PortForward_CL (Clean - Legacy API)

**Transformations:**

- `enabled` → boolean
- `RawData` → parsed dynamic

**Fields:** ruleId, name, enabled, pfwd_interface, fwd, dst_port, fwd_port, proto, RawData

**Note:** Uses Legacy API `/s/default/rest/portforward` endpoint.

---

### 15. UniFi_Health_CL (Messy - Legacy API)

**Schema Variations:** 7 subsystem types with different metrics

**Subsystem Types:**

1. **wan** - WAN connectivity (gw_mac, wan_ip, uptime)
2. **lan** - LAN status
3. **wlan** - WiFi status (num_user, num_guest)
4. **www** - Internet connectivity (latency, xput_up, xput_down)
5. **vpn** - VPN status
6. **system** - System health
7. **controller** - Controller status

**Transformations:**

- `num_user`, `num_guest`, `num_adopted`, `num_disconnected` → integer
- `RawData` → parsed dynamic (contains subsystem-specific fields)

**Common Fields:** subsystem, status, num_user, num_guest, num_adopted, num_disconnected, RawData

**Variable Fields in RawData:**

- WAN subsystem: gw_mac, wan_ip, uptime, drops, latency
- WWW subsystem: xput_up, xput_down, speedtest_status
- WLAN subsystem: num_user, num_guest, tx_bytes_r, rx_bytes_r
- System subsystem: cpu_usage, mem_usage, disk_usage

---

### 16. UniFi_Alarms_CL (Clean - Legacy API)

**Transformations:**

- `alarmTime` → long (Unix timestamp)
- `alarmDatetime` → datetime
- `isNegative` → boolean (true = threat/issue, false = cleared)
- `occurs` → integer (number of occurrences)
- `archived` → boolean
- `RawData` → parsed dynamic

**Fields:** alarmId, alarmKey, alarmTime, alarmDatetime, subsystem, isNegative, message, occurs, archived, apName, apModel, apMac, siteId, deviceType, RawData

**Note:** Uses Legacy API `/s/default/stat/alarm` endpoint for security alarms and IDS/IPS threat detections.

**Common Alarm Types:**

- IDS/IPS detections (rogue_ap, honeypot)
- Unauthorized device connections
- Security policy violations
- AP offline/connectivity issues

**Example Query:**

```kql
UniFi_Alarms_CL
| where TimeGenerated > ago(24h)
| where isNegative == true  // Active threats only
| where archived == false   // Not archived
| project TimeGenerated, alarmKey, message, apName, deviceType, subsystem
| sort by TimeGenerated desc
```

---

## Benefits of Optimized Transformations

### 1. Type Safety

- Proper data types improve query performance
- Datetime conversion enables time-based queries
- Integer conversion enables mathematical operations
- Boolean conversion enables logical filtering

### 2. Query Performance

- Explicit column projection reduces data transfer
- Pre-parsed dynamic fields improve query speed
- Type conversion happens at ingestion (not query time)

### 3. Schema Flexibility

- RawData preserves complete API response
- Handles schema variations gracefully
- Future-proof against API changes
- Enables advanced analytics without schema updates

### 4. Data Validation

- Explicit column projection validates data at ingestion
- Missing required fields cause ingestion errors (fail fast)
- Type conversion validates data format

## Example Queries

### Query Devices by Firmware Version

```kql
UniFi_Devices_CL
| where TimeGenerated > ago(1h)
| where firmwareUpdatable == true
| summarize count() by firmwareVersion, model
| order by count_ desc
```

### Query Network Configuration Changes

```kql
UniFi_Networks_CL
| where TimeGenerated > ago(24h)
| extend purpose = RawData.purpose
| where purpose in ("wan", "corporate")
| project TimeGenerated, name, enabled, vlanId, purpose
```

### Query WiFi Security Types

```kql
UniFi_WiFi_CL
| where TimeGenerated > ago(1h)
| where enabled == true
| summarize count() by securityType, networkType
```

### Query Health Status by Subsystem

```kql
UniFi_Health_CL
| where TimeGenerated > ago(5m)
| summarize arg_max(TimeGenerated, *) by subsystem, CollectorSite
| extend
    gw_mac = tostring(RawData.gw_mac),
    wan_ip = tostring(RawData.wan_ip),
    latency = toint(RawData.latency),
    uptime = toint(RawData.uptime)
| project subsystem, status, num_adopted, num_disconnected, gw_mac, wan_ip, latency, uptime
```

### Query Traffic Lists (Firewall Groups)

```kql
UniFi_TrafficLists_CL
| where TimeGenerated > ago(1h)
| extend itemCount = array_length(items)
| mv-expand item = items
| extend
    itemType = tostring(item.type),
    itemValue = tostring(item.value)
| project TimeGenerated, name, listType, itemType, itemValue
```

## Deployment

Transformations are automatically applied when you deploy the unified template:

```bash
az deployment group create \
  --resource-group "rg-sentinel" \
  --template-file unifiedDeployment-v2-complete.json \
  --parameters \
    workspaceName="your-workspace" \
    retentionInDays=90 \
    collectorVmResourceId="/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.HybridCompute/machines/{vm}"
```

The DCRs will automatically:

1. Parse incoming JSON log files
2. Apply type conversions
3. Validate schema with column projection
4. Ingest to custom log tables

## Troubleshooting

### Ingestion Errors

If you see DCR transformation errors in Azure Monitor:

1. Check log file format matches expected schema
2. Verify required fields are present (TimeGenerated, CollectorSite, ControllerIP, RecordType)
3. Check data types (booleans as true/false, integers as numbers, dates as ISO 8601)

### Missing Data

If expected data is not appearing in Sentinel:

1. Verify collector is creating log files: `ls -lh /var/log/unifi/`
2. Check DCR association: `az monitor data-collection rule association list`
3. Review Azure Monitor Agent logs: `journalctl -u azuremonitoragent -f`

### Schema Mismatches

If you see schema mismatch errors:

1. Check if API response structure has changed
2. Verify collector transformation logic matches DCR expectations
3. Use RawData column to see complete API response

## References

- [Azure Monitor Data Collection Rules](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-overview)
- [KQL Transformation Reference](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-transformations)
