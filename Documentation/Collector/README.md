# UniFi v2 Collector - Linux Data Collection Scripts

## Overview

Collects data from UniFi controllers using Integration API v1 (modern) and Legacy API (compatibility).

## Files

- **`unifi-collector.sh`** - Main collector script (supports 17 endpoints)
- **`install-collector.sh`** - Automated installer
- **`test-integration-api.sh`** - API endpoint testing script

## Quick Test

Test the collector manually before deploying:

```bash
# Copy to test location
cp unifi-collector.sh /tmp/

# Set environment
export CONTROLLER_IP="192.0.2.10"
export API_KEY="your-api-key-here"

# Test one endpoint
/tmp/unifi-collector.sh devices
```

## Endpoints Supported

### Integration API v1 (12 endpoints)

- devices, clients, networks, wifi
- traffic-lists, firewall-zones, acl-rules
- radius-profiles, device-tags
- dpi-categories, dpi-applications
- wans, vpn-servers

### Legacy API (5 endpoints)

- alarms, events, port-forward, health

## Installation (Manual)

1. **Create directories**:

   ```bash
   sudo mkdir -p /opt/unifi-collector/{bin,config,cache}
   sudo mkdir -p /var/log/unifi
   ```

2. **Copy collector**:

   ```bash
   sudo cp unifi-collector.sh /opt/unifi-collector/bin/
   sudo chmod +x /opt/unifi-collector/bin/unifi-collector.sh
   ```

3. **Create config**:

   ```bash
   sudo nano /opt/unifi-collector/config/controllers.conf
   ```

   Format: `SITE_NAME|CONTROLLER_IP|PORT|SITE_NAME_IN_CONTROLLER|API_KEY`
   Example: `DEFAULT|192.0.2.10|443|default|abc123...`

4. **Test**:

   ```bash
   /opt/unifi-collector/bin/unifi-collector.sh devices
   ls -lh /var/log/unifi/
   ```

## Systemd Service (Manual)

Create service template:

```bash
sudo nano /etc/systemd/system/unifi-collector@.service
```

```ini
[Unit]
Description=UniFi Network API Collector - %i
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/unifi-collector/bin/unifi-collector.sh %i
User=unifi-collector
Group=unifi-collector
```

Create timer for each endpoint:

```bash
sudo nano /etc/systemd/system/unifi-collector-devices.timer
```

```ini
[Unit]
Description=UniFi Collector Timer - devices

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
AccuracySec=30s
Unit=unifi-collector@devices.service

[Install]
WantedBy=timers.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now unifi-collector-devices.timer
```

Repeat for all 17 endpoints.

## Troubleshooting

### Check logs

```bash
journalctl -u 'unifi-collector@devices.service' -n 50
```

### Check output files

```bash
ls -lh /var/log/unifi/
cat /var/log/unifi/devices_*.json | jq .
```

### Test API manually

```bash
./test-integration-api.sh
```

For comprehensive API testing and troubleshooting, see [API-TESTING.md](API-TESTING.md).

## Architecture

The collector:

1. Reads controller config from `/opt/unifi-collector/config/controllers.conf`
2. Gets site UUID from Integration API v1 `/v1/sites`
3. Queries correct API for each endpoint
4. Transforms data to match table schemas
5. Saves NDJSON to `/var/log/unifi/{endpoint}_*.json`
6. Azure Monitor Agent picks up files via DCR
7. Data flows to Log Analytics tables

## Next Steps

After testing collector manually:

1. Use `unifi-collector.sh` for automated deployment
2. Deploy Azure DCRs to ingest data
3. Associate DCRs with collector VM
4. Verify data in Sentinel
