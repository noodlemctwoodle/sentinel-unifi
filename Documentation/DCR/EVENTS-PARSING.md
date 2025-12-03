# UniFi Events - Enhanced Intelligent Parsing

## Overview

The UniFi Events DCR now includes intelligent parsing that automatically extracts useful information from the RawData field based on event type. This eliminates the need for complex KQL queries and makes event data immediately useful for security monitoring and troubleshooting.

## What's New in v2.1.0

### Automatically Extracted Fields

The DCR transformation now extracts **15 additional fields** from event RawData:

| Field | Type | Description | Example Values |
|-------|------|-------------|----------------|
| `deviceType` | string | Type of device generating event | AccessPoint, Switch, DeviceManager, Gateway, WirelessUser, WiredUser |
| `eventCategory` | string | Categorized event type | FirmwareUpgrade, DeviceAdoption, ClientRoaming, ClientConnection, SecurityError, DeviceStatus |
| `severity` | string | Event severity level | High, Medium, Low, Informational |
| `deviceModel` | string | Device hardware model | USW-24-POE, UAP-AC-PRO, UDM-Pro |
| `deviceName` | string | Device hostname | office-switch, lobby-ap, main-gateway |
| `deviceDisplayName` | string | Friendly display name | Office Switch (Floor 2), Lobby Access Point |
| `versionFrom` | string | Previous firmware version (upgrades) | 6.5.54.14277 |
| `versionTo` | string | New firmware version (upgrades) | 6.5.59.14854 |
| `channelFrom` | string | Previous WiFi channel (roaming) | 36, 6 |
| `channelTo` | string | New WiFi channel (roaming) | 149, 11 |
| `radioFrom` | string | Previous radio band (roaming) | ng, na |
| `radioTo` | string | New radio band (roaming) | na, ng |
| `userMac` | string | Client MAC address (user events) | ab:cd:ef:12:34:56 |
| `gatewayMac` | string | Gateway MAC address | 00:11:22:33:44:55 |
| `gatewayName` | string | Gateway display name | Main Gateway |

### Device Type Classification

Events are automatically classified by device type based on the `eventKey` prefix:

- **EVT_AP_*** → `AccessPoint` - Access Point events
- **EVT_SW_*** → `Switch` - Switch events
- **EVT_DM_*** → `DeviceManager` - Device Manager/Gateway events
- **EVT_GW_*** → `Gateway` - Gateway-specific events
- **EVT_WU_*** → `WirelessUser` - Wireless client events
- **EVT_LU_*** → `WiredUser` - Wired client events

### Event Categorization

Events are grouped into logical categories:

- **FirmwareUpgrade** - Device firmware updates (EVT_*_Upgraded)
- **DeviceAdoption** - Device adoption and readoption (EVT_*_Adopted, EVT_*_Readopted)
- **ClientRoaming** - WiFi clients moving between APs/channels (EVT_WU_Roam*)
- **ClientConnection** - Client connect/disconnect events (EVT_*_Connect*, EVT_*_Disconnect*)
- **SecurityError** - Security issues (EVT_AP_HostKeyMismatch)
- **DeviceStatus** - Device online/offline status (EVT_*_Online, EVT_*_Offline)
- **General** - Other miscellaneous events

### Severity Levels

Automatic severity assignment for faster triage:

- **High** - Security errors (HostKeyMismatch), negative events (`isNegative = true`)
- **Medium** - Device offline, client disconnects
- **Low** - Device readoptions
- **Informational** - Firmware upgrades, general events

## Example KQL Queries

### 1. Security Monitoring - SSH Host Key Mismatches

Detect potential MITM attacks or device replacements:

```kql
UniFi_Events_CL
| where eventCategory == "SecurityError"
| where eventKey == "EVT_AP_HostKeyMismatch"
| project
    TimeGenerated,
    CollectorSite,
    severity,
    deviceType,
    deviceName,
    deviceModel,
    apMac,
    message
| sort by TimeGenerated desc
```

### 2. Firmware Upgrade Tracking

Track firmware updates across all device types:

```kql
UniFi_Events_CL
| where eventCategory == "FirmwareUpgrade"
| where isnotempty(versionFrom) and isnotempty(versionTo)
| project
    TimeGenerated,
    CollectorSite,
    deviceType,
    deviceName,
    deviceModel,
    versionFrom,
    versionTo,
    message
| sort by TimeGenerated desc
```

### 3. WiFi Roaming Analysis

Understand client roaming patterns between APs and channels:

```kql
UniFi_Events_CL
| where eventCategory == "ClientRoaming"
| where isnotempty(userMac)
| project
    TimeGenerated,
    CollectorSite,
    userMac,
    deviceName,                    // AP name
    channelFrom,
    channelTo,
    radioFrom,                     // ng = 2.4GHz, na = 5GHz
    radioTo,
    message
| extend
    BandFrom = case(radioFrom == "ng", "2.4GHz", radioFrom == "na", "5GHz", radioFrom == "6e", "6GHz", radioFrom),
    BandTo = case(radioTo == "ng", "2.4GHz", radioTo == "na", "5GHz", radioTo == "6e", "6GHz", radioTo)
| sort by TimeGenerated desc
```

### 4. Device Adoption Events

Monitor devices being adopted or readopted (potential security concern if unexpected):

```kql
UniFi_Events_CL
| where eventCategory == "DeviceAdoption"
| project
    TimeGenerated,
    CollectorSite,
    severity,
    deviceType,
    deviceName,
    deviceModel,
    deviceDisplayName,
    eventKey,
    message
| sort by TimeGenerated desc
```

### 5. High Severity Events Dashboard

Quick overview of issues requiring attention:

```kql
UniFi_Events_CL
| where severity in ("High", "Medium")
| summarize
    Count = count(),
    LatestEvent = max(TimeGenerated),
    EventTypes = make_set(eventCategory)
    by
        CollectorSite,
        severity,
        deviceType,
        deviceName
| sort by severity asc, Count desc
```

### 6. Client Roaming Frequency (Potential WiFi Issues)

Identify clients roaming excessively (may indicate coverage or interference issues):

```kql
UniFi_Events_CL
| where eventCategory == "ClientRoaming"
| where TimeGenerated > ago(1h)
| summarize
    RoamCount = count(),
    UniqueAPs = dcount(deviceName),
    ChannelChanges = make_set(strcat(channelFrom, "→", channelTo))
    by userMac
| where RoamCount > 10
| sort by RoamCount desc
```

### 7. Device Offline Events

Track device reliability and uptime:

```kql
UniFi_Events_CL
| where eventCategory == "DeviceStatus"
| where eventKey contains "Offline"
| project
    TimeGenerated,
    CollectorSite,
    deviceType,
    deviceName,
    deviceModel,
    deviceDisplayName,
    severity,
    message
| sort by TimeGenerated desc
```

### 8. Gateway Firmware Upgrades with Version Tracking

Monitor critical infrastructure updates:

```kql
UniFi_Events_CL
| where deviceType == "DeviceManager" or deviceType == "Gateway"
| where eventCategory == "FirmwareUpgrade"
| project
    TimeGenerated,
    CollectorSite,
    deviceName,
    gatewayName,
    versionFrom,
    versionTo,
    message
| extend
    VersionIncrease = strcat(versionFrom, " → ", versionTo)
| sort by TimeGenerated desc
```

### 9. Multi-Site Event Summary

Aggregate view across all sites:

```kql
UniFi_Events_CL
| where TimeGenerated > ago(24h)
| summarize
    TotalEvents = count(),
    HighSeverity = countif(severity == "High"),
    MediumSeverity = countif(severity == "Medium"),
    FirmwareUpgrades = countif(eventCategory == "FirmwareUpgrade"),
    SecurityErrors = countif(eventCategory == "SecurityError"),
    DeviceAdoptions = countif(eventCategory == "DeviceAdoption")
    by CollectorSite, deviceType
| sort by TotalEvents desc
```

### 10. Detailed Event Investigation

Deep dive into specific events with all parsed data:

```kql
UniFi_Events_CL
| where eventKey == "EVT_WU_RoamRadio"  // Change to any event key
| project
    TimeGenerated,
    CollectorSite,
    severity,
    eventCategory,
    deviceType,
    deviceName,
    deviceModel,
    deviceDisplayName,
    versionFrom,
    versionTo,
    channelFrom,
    channelTo,
    radioFrom,
    radioTo,
    userMac,
    gatewayName,
    message,
    RawData                               // Full JSON for additional context
| sort by TimeGenerated desc
```

---

## Event Types Discovered

### Access Point Events

- **EVT_AP_HostKeyMismatch** - SSH host key verification failure (security concern)
- **EVT_AP_AutoReadopted** - AP automatically readopted after disconnection
- **EVT_AP_Upgraded** - AP firmware upgrade completed
- **EVT_AP_Offline** - AP went offline
- **EVT_AP_Connected** - AP connected to controller

### Switch Events

- **EVT_SW_AutoReadopted** - Switch automatically readopted
- **EVT_SW_Upgraded** - Switch firmware upgrade completed
- **EVT_SW_Offline** - Switch went offline
- **EVT_SW_Connected** - Switch connected to controller

### Device Manager/Gateway Events

- **EVT_DM_Upgraded** - Gateway/UDM firmware upgrade
- **EVT_DM_Offline** - Gateway went offline
- **EVT_DM_Connected** - Gateway connected

### Wireless User Events

- **EVT_WU_RoamRadio** - Client roamed between radios/channels
- **EVT_WU_Connected** - Wireless client connected
- **EVT_WU_Disconnected** - Wireless client disconnected
- **EVT_WU_Roam** - Client roamed between APs

### Wired User Events

- **EVT_LU_Connected** - Wired client connected
- **EVT_LU_Disconnected** - Wired client disconnected

---

## Radio Band Mapping

The `radioFrom` and `radioTo` fields use UniFi's internal radio identifiers:

| Radio ID | Band | Frequency |
|----------|------|-----------|
| `ng` | 2.4 GHz | 802.11n/g/b |
| `na` | 5 GHz | 802.11ac/n/a |
| `6e` | 6 GHz | 802.11ax (WiFi 6E) |

Example KQL to decode radio bands:

```kql
UniFi_Events_CL
| where eventCategory == "ClientRoaming"
| extend
    BandFrom = case(
        radioFrom == "ng", "2.4GHz",
        radioFrom == "na", "5GHz",
        radioFrom == "6e", "6GHz",
        radioFrom
    ),
    BandTo = case(
        radioTo == "ng", "2.4GHz",
        radioTo == "na", "5GHz",
        radioTo == "6e", "6GHz",
        radioTo
    )
| project TimeGenerated, userMac, BandFrom, BandTo, channelFrom, channelTo
```

---

## Use Cases

### Security Monitoring

1. **MITM Detection** - Alert on EVT_AP_HostKeyMismatch events
2. **Unauthorized Adoptions** - Monitor unexpected device adoption events
3. **Rogue Device Detection** - Track devices appearing without authorization

### Network Operations

1. **Firmware Compliance** - Track firmware versions across fleet
2. **Device Health** - Monitor offline/online events for reliability metrics
3. **Client Experience** - Analyze roaming patterns for WiFi optimization

### Troubleshooting

1. **Coverage Issues** - Identify clients roaming excessively
2. **Channel Interference** - Detect frequent channel changes
3. **Device Reliability** - Track readoption frequency indicating instability

---

## Performance Notes

All field extraction happens **at ingestion time** via DCR transformation, which means:

- ✅ **No query-time overhead** - Fields are pre-parsed and indexed
- ✅ **Faster queries** - Direct field access instead of JSON parsing
- ✅ **Lower cost** - Reduced compute for repeated queries
- ✅ **Better indexing** - String fields are properly indexed for search

The `RawData` field is still preserved for:

- Additional fields not extracted by default
- Debugging and investigation
- Future enhancements without data loss

---

## Migration from v2.0.0 to v2.1.0

If you deployed v2.0.0, upgrading to v2.1.0 is straightforward:

1. **Redeploy the ARM template** - This will update table schemas and DCR transformations
2. **Existing data preserved** - Old events without parsed fields remain queryable via RawData
3. **New data enhanced** - Events after upgrade will have all parsed fields populated
4. **No breaking changes** - All v2.0.0 queries continue to work

### Deployment Command

```bash
cd /path/to/Solution/UniFi/v2/Azure/DCR

az deployment group create \
  --resource-group "rg-sentinel" \
  --template-file unifiedDeployment.json \
  --parameters workspaceName="law-sentinel" \
  --parameters retentionInDays=90
```

---

## Summary

The enhanced event parsing in v2.1.0 transforms raw UniFi events into actionable intelligence automatically. Security teams can now:

- **Instantly identify security issues** without writing complex KQL
- **Track firmware compliance** across the entire network estate
- **Optimize WiFi performance** by analyzing client roaming patterns
- **Monitor device health** with pre-categorized severity levels

All parsing happens at ingestion time for maximum performance and zero query-time overhead.
