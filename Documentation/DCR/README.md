# Azure Data Collection Rules (DCRs) for UniFi Integration

## Overview

This directory contains the Azure infrastructure needed to ingest UniFi network data into Microsoft Sentinel. The deployment creates:

- **16 Custom Log Tables** - One for each UniFi data type (devices, clients, networks, events, etc.)
- **16 Data Collection Rules (DCRs)** - Transform and route data from the collector VM to Sentinel
- **DCR Association** - Links the collector VM to all DCRs for automatic data ingestion

## What Gets Deployed

### Custom Tables Created

All tables follow the naming pattern `UniFi_<Type>_CL`:

| Table | Data Source | Description |
|-------|-------------|-------------|
| `UniFi_Devices_CL` | Integration API v1 | Access points, switches, gateways |
| `UniFi_Clients_CL` | Integration API v1 | Connected wireless and wired clients |
| `UniFi_Networks_CL` | Integration API v1 | VLANs, subnets, DHCP configuration |
| `UniFi_WiFi_CL` | Integration API v1 | SSIDs and wireless settings |
| `UniFi_Events_CL` | Integration API v1 | Real-time network events with intelligent parsing |
| `UniFi_TrafficLists_CL` | Integration API v1 | Firewall traffic matching lists |
| `UniFi_FirewallZones_CL` | Integration API v1 | Network segmentation zones |
| `UniFi_ACLRules_CL` | Integration API v1 | Access control rules |
| `UniFi_RADIUSProfiles_CL` | Integration API v1 | 802.1X authentication profiles |
| `UniFi_DeviceTags_CL` | Integration API v1 | Device tagging and grouping |
| `UniFi_DPICategories_CL` | Integration API v1 | Deep packet inspection categories |
| `UniFi_DPIApplications_CL` | Integration API v1 | DPI application signatures |
| `UniFi_WANs_CL` | Integration API v1 | WAN connection configuration |
| `UniFi_VPNServers_CL` | Integration API v1 | VPN server endpoints |
| `UniFi_Alarms_CL` | Legacy API | Security alarms and IDS/IPS detections |
| `UniFi_PortForward_CL` | Legacy API | Port forwarding / NAT rules |
| `UniFi_Health_CL` | Legacy API | System health metrics |

### Data Transformations

Each DCR includes KQL transformations that:

- **Parse JSON** - Convert NDJSON log files to structured data
- **Type Conversion** - Convert strings to proper types (datetime, boolean, int)
- **Field Extraction** - Parse nested objects into queryable columns
- **Schema Validation** - Ensure data matches table schema before ingestion

For detailed information about transformations:

- **[TRANSFORMATIONS.md](TRANSFORMATIONS.md)** - Comprehensive transformation strategy
- **[EVENTS-PARSING.md](EVENTS-PARSING.md)** - Event intelligence and parsing details

## Prerequisites

Before deploying DCRs, ensure you have:

- [x] Azure CLI installed and authenticated (`az login`)
- [x] Microsoft Sentinel workspace deployed
- [x] Collector VM deployed with Azure Arc agent
- [x] Azure Monitor Agent installed on collector VM
- [x] Permissions to create DCRs and custom tables

**Required Azure Permissions:**

```text
Microsoft.Insights/dataCollectionRules/write
Microsoft.OperationalInsights/workspaces/tables/write
Microsoft.HybridCompute/machines/read
```

## Quick Deployment

### Step 1: Get Your Resource IDs

```bash
# Set your Azure environment variables
SUBSCRIPTION_ID="your-subscription-id"
RESOURCE_GROUP="rg-sentinel-test"
WORKSPACE_NAME="law-sentinel-unifi"
COLLECTOR_VM_NAME="vm-unifi-collector"

# Get the workspace resource ID
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$WORKSPACE_NAME" \
  --query id -o tsv)

# Get the collector VM resource ID (for Azure Arc-enabled VM)
VM_RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.HybridCompute/machines/$COLLECTOR_VM_NAME"

# For native Azure VMs, use this instead:
# VM_RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$COLLECTOR_VM_NAME"

echo "Workspace ID: $WORKSPACE_ID"
echo "VM Resource ID: $VM_RESOURCE_ID"
```

### Step 2: Deploy DCRs and Tables

```bash
# Navigate to DCR directory
cd /path/to/sentinel-unifi/DCR

# Deploy using ARM template
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file unifiedDeployment.json \
  --parameters \
    workspaceName="$WORKSPACE_NAME" \
    retentionInDays=90 \
    collectorVmResourceId="$VM_RESOURCE_ID"
```

**Expected Output:**

```json
{
  "properties": {
    "provisioningState": "Succeeded",
    "outputs": {
      "dcrIds": {
        "value": [
          "/subscriptions/.../dataCollectionRules/UniFi-Devices-DCR",
          "/subscriptions/.../dataCollectionRules/UniFi-Clients-DCR",
          ...
        ]
      }
    }
  }
}
```

### Step 3: Verify Deployment

#### Check Tables Exist

```bash
# List all UniFi tables
az monitor log-analytics workspace table list \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$WORKSPACE_NAME" \
  --query "[?starts_with(name, 'UniFi_')].name" -o table
```

**Expected Output:**

```text
Result
------------------------
UniFi_ACLRules_CL
UniFi_Alarms_CL
UniFi_Clients_CL
UniFi_DeviceTags_CL
UniFi_Devices_CL
UniFi_DPIApplications_CL
UniFi_DPICategories_CL
UniFi_Events_CL
UniFi_FirewallZones_CL
UniFi_Health_CL
UniFi_Networks_CL
UniFi_PortForward_CL
UniFi_RADIUSProfiles_CL
UniFi_TrafficLists_CL
UniFi_VPNServers_CL
UniFi_WANs_CL
UniFi_WiFi_CL
```

#### Check DCRs Exist

```bash
# List all UniFi DCRs
az monitor data-collection rule list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?starts_with(name, 'UniFi-')].name" -o table
```

#### Verify DCR Association

```bash
# Check VM is associated with DCRs
az monitor data-collection rule association list \
  --resource "$VM_RESOURCE_ID" \
  --query "[].{Name:name, DCR:dataCollectionRuleId}" -o table
```

**Expected:** You should see 17 associations (one per DCR).

### Step 4: Wait for Data Ingestion

After deploying DCRs:

1. **Ensure collector is running** (see [../Collector/README.md](../Collector/README.md))
2. **Wait 10-15 minutes** for initial data collection and ingestion
3. **Query Sentinel** to verify data arrival

#### Verification Query

```kql
// Check all UniFi tables for recent data
search *
| where TimeGenerated > ago(30m)
| where TableName startswith "UniFi_"
| summarize
    EarliestData = min(TimeGenerated),
    LatestData = max(TimeGenerated),
    RecordCount = count()
    by TableName
| sort by TableName asc
```

**Expected Result:** All 17 tables should show recent data.

## Configuration Options

### Retention Period

Default: **90 days**. Adjust during deployment:

```bash
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file unifiedDeployment.json \
  --parameters \
    workspaceName="$WORKSPACE_NAME" \
    retentionInDays=180 \
    collectorVmResourceId="$VM_RESOURCE_ID"
```

### Location

DCRs are deployed to the same location as your Log Analytics workspace by default.

## Troubleshooting

### Issue 1: Deployment Fails - Permission Denied

**Error:**

```text
Code: AuthorizationFailed
Message: The client does not have authorization to perform action...
```

**Solution:**

```bash
# Check your permissions
az role assignment list --assignee $(az account show --query user.name -o tsv) --query "[].roleDefinitionName"

# You need one of these roles:
# - Contributor
# - Monitoring Contributor
# - Custom role with required permissions
```

### Issue 2: Tables Not Created

**Symptom:** DCRs deploy successfully but tables don't appear in workspace.

**Diagnosis:**

```bash
# Check deployment outputs
az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name <deployment-name> \
  --query properties.outputs
```

**Solution:**

- Redeploy with `--mode Complete` (caution: deletes unmanaged resources)
- Manually create tables using Azure Portal → Log Analytics → Tables → New Custom Log

### Issue 3: No Data Appearing in Tables

**Symptom:** Tables exist, DCRs deployed, but no data ingested.

**Diagnosis Steps:**

1. **Check collector is running:**

   ```bash
   ssh user@collector-vm
   systemctl list-timers | grep unifi-collector
   ls -lh /var/log/unifi/
   ```

2. **Check Azure Monitor Agent:**

   ```bash
   sudo systemctl status azuremonitoragent
   sudo journalctl -u azuremonitoragent -n 100
   ```

3. **Check DCR associations:**

   ```bash
   az monitor data-collection rule association list --resource "$VM_RESOURCE_ID"
   ```

4. **Check for DCR errors:**

   ```kql
   // In Sentinel
   AzureDiagnostics
   | where ResourceType == "DATACONNECTION"
   | where TimeGenerated > ago(1h)
   | project TimeGenerated, ResourceId, Message
   ```

**Common Causes:**

- Firewall blocking outbound connections to Azure (check port 443)
- Incorrect file paths in DCR configuration
- Azure Monitor Agent not authenticated
- Data format doesn't match DCR transformation expectations

### Issue 4: Transformation Errors

**Symptom:** Partial data ingestion, missing fields, or type conversion errors.

**Diagnosis:**

```kql
// Check for ingestion errors
_LogOperation_CL
| where TimeGenerated > ago(1h)
| where Category == "Ingestion"
| project TimeGenerated, Detail, ErrorDescription
```

**Solution:**

1. Review [TRANSFORMATIONS.md](TRANSFORMATIONS.md) for expected data formats
2. Check collector output files match expected schema
3. Validate JSON structure: `cat /var/log/unifi/devices_*.json | jq .`

## Updating DCRs

To update existing DCRs with new transformations or configurations:

```bash
# Redeploy the template
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file unifiedDeployment.json \
  --parameters \
    workspaceName="$WORKSPACE_NAME" \
    retentionInDays=90 \
    collectorVmResourceId="$VM_RESOURCE_ID" \
  --mode Incremental
```

**Note:** Incremental mode updates existing resources without deleting others.

## Advanced Topics

### Custom Transformations

To modify KQL transformations for specific tables, edit `unifiedDeployment.json`:

1. Locate the DCR resource for the target table
2. Find the `transformKql` property
3. Modify the KQL query
4. Redeploy the template

**Example:** Add custom field extraction for devices:

```json
{
  "name": "UniFi-Devices-DCR",
  "properties": {
    "dataFlows": [{
      "transformKql": "source | extend customField = RawData.myCustomProperty | project ..."
    }]
  }
}
```

### Multi-Site Deployments

For multiple UniFi sites sending to the same Sentinel workspace:

1. Deploy DCRs once (shared across all collectors)
2. Deploy multiple collector VMs (one per site)
3. Associate each collector VM with the same DCRs

```bash
# Associate additional collector VM
for DCR_ID in $(az monitor data-collection rule list --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, 'UniFi-')].id" -o tsv); do
  az monitor data-collection rule association create \
    --name "UniFi-Association-$(uuidgen)" \
    --resource "$SECOND_VM_RESOURCE_ID" \
    --data-collection-rule-id "$DCR_ID"
done
```

### Performance Optimization

For high-volume environments (200+ devices):

1. **Increase collection intervals** - Reduce timer frequency in systemd units
2. **Enable data sampling** - Modify DCR transformations to sample records
3. **Implement data filtering** - Only ingest changed records

See [TRANSFORMATIONS.md](TRANSFORMATIONS.md) for optimization strategies.

## Cost Considerations

Costs are based on Azure Log Analytics data ingestion and retention:

| Component | Pricing Model |
|-----------|---------------|
| Log Analytics Ingestion | Pay-per-GB ingested |
| Log Analytics Retention | Pay-per-GB per month |
| Data Collection Rules | No additional charge |
| Data Transformations | No additional charge for basic transformations |

**Important Notes:**

- Pricing varies significantly by Azure region
- Enterprise agreements and commitment tiers may reduce costs
- Free tier allowances may apply to your subscription
- Costs scale with network size and collection frequency

**Cost Estimation:**

- Consult the [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) for current rates
- See [Performance Benchmarks](../README.md#performance-benchmarks) for expected data volumes
- Monitor actual ingestion in Azure Portal to track costs

## Additional Resources

### Detailed Documentation

- **[TRANSFORMATIONS.md](TRANSFORMATIONS.md)** - Deep dive into KQL transformations for 16 data types (Events documented separately)
- **[EVENTS-PARSING.md](EVENTS-PARSING.md)** - Intelligent event parsing and categorization details
- **[../Collector/README.md](../Collector/README.md)** - Collector installation and configuration

### Microsoft Documentation

- [Data Collection Rules Overview](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-overview)
- [Custom Logs in Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/custom-logs-overview)
- [KQL Transformation Reference](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-transformations)

### Testing Guide

- **[../README.md](../README.md)** - Comprehensive testing guide for the entire solution

## Support

For issues with DCR deployment or data ingestion:

1. Check the [Troubleshooting](#troubleshooting) section above
2. Review the main [Testing Guide](../README.md#common-issues--troubleshooting)
3. Open a GitHub issue with:
   - Deployment logs
   - Azure Monitor Agent logs
   - Sample data from collector
   - Error messages from Sentinel

**Current Version:** 2.1.0
**Last Updated:** December 2025
