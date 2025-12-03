#!/bin/bash
#
# UniFi Network API Collector v2.0 - Integration API v1 + Legacy API Support
# Supports both Integration API v1 (modern) and Legacy API (compatibility)
# Collects data and saves to JSON files for Azure Monitor Agent
#

set -euo pipefail

# Configuration
CONFIG_FILE="/opt/unifi-collector/config/controllers.conf"
LOG_DIR="/var/log/unifi"
SITE_UUID_CACHE="/opt/unifi-collector/cache/site_uuid"

# Endpoint type (passed as argument)
ENDPOINT_TYPE="${1:-devices}"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Get site UUID from Integration API v1
get_site_uuid() {
    local controller_ip="$1"
    local api_key="$2"

    # Check cache first
    if [[ -f "$SITE_UUID_CACHE" ]]; then
        cat "$SITE_UUID_CACHE"
        return 0
    fi

    # Query Integration API v1 for site UUID
    local temp_response=$(mktemp)
    local http_code=$(curl -k -s -w "%{http_code}" \
        -H "X-API-Key: ${api_key}" \
        -H "Accept: application/json" \
        --connect-timeout 10 \
        --max-time 30 \
        -o "$temp_response" \
        "https://${controller_ip}:443/proxy/network/integration/v1/sites" 2>&1 || echo "000")

    if [[ "$http_code" == "200" ]]; then
        local site_uuid=$(jq -r '.data[0].id // empty' "$temp_response" 2>/dev/null)
        if [[ -n "$site_uuid" ]]; then
            # Cache the UUID
            mkdir -p "$(dirname "$SITE_UUID_CACHE")"
            echo "$site_uuid" > "$SITE_UUID_CACHE"
            rm -f "$temp_response"
            echo "$site_uuid"
            return 0
        fi
    fi

    rm -f "$temp_response"
    return 1
}

# Get endpoint configuration (API version, path, table name)
get_endpoint_config() {
    local endpoint="$1"
    local site_uuid="$2"

    case "$endpoint" in
        # Integration API v1 endpoints
        devices)
            echo "v1|/v1/sites/${site_uuid}/devices|UniFi_Devices_CL"
            ;;
        clients)
            echo "v1|/v1/sites/${site_uuid}/clients|UniFi_Clients_CL"
            ;;
        networks)
            echo "v1|/v1/sites/${site_uuid}/networks|UniFi_Networks_CL"
            ;;
        wifi)
            echo "v1|/v1/sites/${site_uuid}/wifi/broadcasts|UniFi_WiFi_CL"
            ;;
        traffic-lists)
            echo "v1|/v1/sites/${site_uuid}/traffic-matching-lists|UniFi_TrafficLists_CL"
            ;;
        firewall-zones)
            echo "v1|/v1/sites/${site_uuid}/firewall/zones|UniFi_FirewallZones_CL"
            ;;
        acl-rules)
            echo "v1|/v1/sites/${site_uuid}/acl-rules|UniFi_ACLRules_CL"
            ;;
        radius-profiles)
            echo "v1|/v1/sites/${site_uuid}/radius/profiles|UniFi_RADIUSProfiles_CL"
            ;;
        device-tags)
            echo "v1|/v1/sites/${site_uuid}/device-tags|UniFi_DeviceTags_CL"
            ;;
        dpi-categories)
            echo "v1|/v1/dpi/categories|UniFi_DPICategories_CL"
            ;;
        dpi-applications)
            echo "v1|/v1/dpi/applications|UniFi_DPIApplications_CL"
            ;;
        wans)
            echo "v1|/v1/sites/${site_uuid}/wans|UniFi_WANs_CL"
            ;;
        vpn-servers)
            echo "v1|/v1/sites/${site_uuid}/vpn/servers|UniFi_VPNServers_CL"
            ;;

        # Legacy API endpoints
        port-forward)
            echo "legacy|/s/default/rest/portforward|UniFi_PortForward_CL"
            ;;
        health)
            echo "legacy|/s/default/stat/health|UniFi_Health_CL"
            ;;
        events)
            echo "legacy|/s/default/stat/event|UniFi_Events_CL"
            ;;
        alarms)
            echo "legacy|/s/default/stat/alarm|UniFi_Alarms_CL"
            ;;

        *)
            error "Unknown endpoint: $endpoint"
            return 1
            ;;
    esac
}

# Transform Integration API v1 data to match our schema
transform_v1_data() {
    local endpoint="$1"
    local record="$2"

    case "$endpoint" in
        devices)
            echo "$record" | jq -c '{
                id: .id,
                macAddress: .macAddress,
                ipAddress: .ipAddress,
                name: .name,
                model: .model,
                state: .state,
                supported: .supported,
                firmwareVersion: .firmwareVersion,
                firmwareUpdatable: .firmwareUpdatable,
                features: .features,
                interfaces: .interfaces,
                RawData: .
            }'
            ;;
        clients)
            echo "$record" | jq -c '{
                id: .id,
                clientType: .type,
                name: .name,
                connectedAt: .connectedAt,
                ipAddress: .ipAddress,
                macAddress: .macAddress,
                uplinkDeviceId: .uplinkDeviceId,
                accessType: .access.type,
                RawData: .
            }'
            ;;
        networks)
            echo "$record" | jq -c '{
                id: .id,
                name: .name,
                management: .management,
                enabled: .enabled,
                vlanId: .vlanId,
                metadataOrigin: .metadata.origin,
                metadataConfigurable: .metadata.configurable,
                RawData: .
            }'
            ;;
        wifi)
            echo "$record" | jq -c '{
                id: .id,
                name: .name,
                wifiType: .type,
                enabled: .enabled,
                networkType: .network.type,
                securityType: .securityConfiguration.type,
                broadcastingFrequencies: .broadcastingFrequenciesGHz,
                metadataOrigin: .metadata.origin,
                RawData: .
            }'
            ;;
        traffic-lists)
            echo "$record" | jq -c '{
                id: .id,
                name: .name,
                listType: .type,
                items: .items,
                RawData: .
            }'
            ;;
        firewall-zones)
            echo "$record" | jq -c '{
                id: .id,
                name: .name,
                networkIds: .networkIds,
                metadataOrigin: .metadata.origin,
                metadataConfigurable: .metadata.configurable,
                RawData: .
            }'
            ;;
        acl-rules)
            echo "$record" | jq -c '{
                id: .id,
                name: .name,
                ruleType: .type,
                enabled: .enabled,
                action: .action,
                index: .index,
                description: .description,
                metadataOrigin: .metadata.origin,
                RawData: .
            }'
            ;;
        radius-profiles)
            echo "$record" | jq -c '{
                id: .id,
                name: .name,
                metadataOrigin: .metadata.origin,
                metadataConfigurable: .metadata.configurable,
                RawData: .
            }'
            ;;
        device-tags)
            echo "$record" | jq -c '{
                id: .id,
                name: .name,
                deviceIds: .deviceIds,
                metadataOrigin: .metadata.origin,
                RawData: .
            }'
            ;;
        dpi-categories)
            echo "$record" | jq -c '{
                categoryId: .id,
                categoryName: .name,
                RawData: .
            }'
            ;;
        dpi-applications)
            echo "$record" | jq -c '{
                applicationId: .id,
                applicationName: .name,
                RawData: .
            }'
            ;;
        wans)
            echo "$record" | jq -c '{
                id: .id,
                name: .name,
                RawData: .
            }'
            ;;
        vpn-servers)
            echo "$record" | jq -c '{
                id: .id,
                name: .name,
                vpnType: .type,
                enabled: .enabled,
                metadataOrigin: .metadata.origin,
                RawData: .
            }'
            ;;
        *)
            # Default: return as-is
            echo "$record"
            ;;
    esac
}

# Transform Legacy API data
transform_legacy_data() {
    local endpoint="$1"
    local record="$2"

    case "$endpoint" in
        port-forward)
            echo "$record" | jq -c '{
                ruleId: ._id,
                name: .name,
                enabled: .enabled,
                pfwd_interface: .pfwd_interface,
                fwd: .fwd,
                dst_port: .dst_port,
                fwd_port: .fwd_port,
                proto: .proto,
                RawData: .
            }'
            ;;
        health)
            echo "$record" | jq -c '{
                subsystem: .subsystem,
                status: .status,
                num_user: .num_user,
                num_guest: .num_guest,
                num_adopted: .num_adopted,
                num_disconnected: .num_disconnected,
                RawData: .
            }'
            ;;
        events)
            echo "$record" | jq -c '{
                eventId: ._id,
                eventKey: .key,
                eventTime: .time,
                eventDatetime: .datetime,
                subsystem: .subsystem,
                isNegative: .is_negative,
                message: .msg,
                apName: .ap_name,
                apModel: .ap_model,
                apMac: .ap,
                siteId: .site_id,
                RawData: .
            }'
            ;;
        alarms)
            echo "$record" | jq -c '{
                alarmId: ._id,
                alarmKey: .key,
                alarmTime: .time,
                alarmDatetime: .datetime,
                subsystem: .subsystem,
                isNegative: .is_negative,
                message: .msg,
                occurs: .occurs,
                archived: .archived,
                apName: .ap_name,
                apModel: .ap_model,
                apMac: .ap,
                siteId: .site_id,
                RawData: .
            }'
            ;;
        *)
            echo "$record"
            ;;
    esac
}

# Main collection function
collect_data() {
    local endpoint_type="$1"

    log "Starting collection for endpoint: $endpoint_type"

    # Read controller configuration (UUID is optional 6th field)
    while IFS='|' read -r site_name controller_ip port site_name_controller api_key site_uuid; do
        # Skip comments and empty lines
        [[ "$site_name" =~ ^#.*$ ]] && continue
        [[ -z "$site_name" ]] && continue

        log "Collecting from $site_name ($controller_ip:$port)"

        # Get site UUID for Integration API v1 (auto-discover if not provided in config)
        if [[ -z "$site_uuid" ]]; then
            log "UUID not in config, auto-discovering..."
            if ! site_uuid=$(get_site_uuid "$controller_ip" "$api_key"); then
                error "Failed to get site UUID for Integration API v1"
                continue
            fi
        fi
        log "Site UUID: $site_uuid"

        # Get endpoint configuration
        IFS='|' read -r api_version endpoint_path table_name <<< "$(get_endpoint_config "$endpoint_type" "$site_uuid")"

        log "API: $api_version | Endpoint: $endpoint_path | Table: $table_name"

        # Build API URL
        local api_url
        if [[ "$api_version" == "v1" ]]; then
            api_url="https://${controller_ip}:${port}/proxy/network/integration${endpoint_path}"
        else
            api_url="https://${controller_ip}:${port}/proxy/network/api${endpoint_path}"
        fi

        log "API URL: $api_url"

        # Fetch data
        local temp_response=$(mktemp)
        local http_code=$(curl -k -s -w "%{http_code}" \
            -H "X-API-Key: ${api_key}" \
            -H "Accept: application/json" \
            --connect-timeout 10 \
            --max-time 30 \
            -o "$temp_response" \
            "$api_url" 2>&1 || echo "000")

        if [[ "$http_code" != "200" ]]; then
            error "Failed to fetch: HTTP $http_code"
            rm -f "$temp_response"
            continue
        fi

        # Check response based on API version
        local record_count
        if [[ "$api_version" == "v1" ]]; then
            record_count=$(jq -r '.count // 0' "$temp_response" 2>/dev/null || echo "0")
        else
            # Legacy API check
            local rc_status=$(jq -r '.meta.rc // "unknown"' "$temp_response" 2>/dev/null)
            if [[ "$rc_status" != "ok" ]]; then
                error "API returned error status: $rc_status"
                rm -f "$temp_response"
                continue
            fi
            record_count=$(jq '.data | length' "$temp_response" 2>/dev/null || echo "0")
        fi

        log "Records in response: $record_count"

        if [[ "$record_count" -eq 0 ]]; then
            log "No data returned (empty array)"
            rm -f "$temp_response"
            continue
        fi

        # Extract and enrich records
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local output_file="${LOG_DIR}/${endpoint_type}_${site_name}_$(date +%s).json"

        if [[ "$api_version" == "v1" ]]; then
            # Process Integration API v1 data
            jq -c --arg ts "$timestamp" \
                --arg site "$site_name" \
                --arg controller "$controller_ip" \
                --arg table "$table_name" \
                '.data[]' "$temp_response" | while read -r record; do
                # Transform record
                transformed=$(transform_v1_data "$endpoint_type" "$record")
                # Add metadata
                echo "$transformed" | jq -c '. + {
                    TimeGenerated: $ts,
                    CollectorSite: $site,
                    ControllerIP: $controller,
                    RecordType: $table
                }' --arg ts "$timestamp" --arg site "$site_name" --arg controller "$controller_ip" --arg table "$table_name"
            done > "$output_file"
        else
            # Process Legacy API data
            jq -c --arg ts "$timestamp" \
                --arg site "$site_name" \
                --arg controller "$controller_ip" \
                --arg table "$table_name" \
                '.data[]' "$temp_response" | while read -r record; do
                # Transform record
                transformed=$(transform_legacy_data "$endpoint_type" "$record")
                # Add metadata
                echo "$transformed" | jq -c '. + {
                    TimeGenerated: $ts,
                    CollectorSite: $site,
                    ControllerIP: $controller,
                    RecordType: $table
                }' --arg ts "$timestamp" --arg site "$site_name" --arg controller "$controller_ip" --arg table "$table_name"
            done > "$output_file"
        fi

        local saved_count=$(wc -l < "$output_file")
        log "Saved $saved_count records to $output_file"

        rm -f "$temp_response"

    done < "$CONFIG_FILE"

    log "Collection complete for $endpoint_type"
}

# Cleanup old files (keep last 24 hours)
cleanup_old_files() {
    log "Cleaning up files older than 24 hours"
    cd "$LOG_DIR" 2>/dev/null || return 1
    find . -maxdepth 1 -name "*.json" -type f -mtime +1 -delete 2>/dev/null || true
    log "Cleanup complete"
}

# Main execution
main() {
    if [[ $# -eq 0 ]]; then
        error "Usage: $0 <endpoint-type>"
        error "Endpoint types: devices, clients, networks, wifi, traffic-lists, firewall-zones, acl-rules, radius-profiles, device-tags, dpi-categories, dpi-applications, wans, vpn-servers, port-forward, health"
        exit 1
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi

    if [[ ! -d "$LOG_DIR" ]] || [[ ! -w "$LOG_DIR" ]]; then
        error "Log directory not accessible: $LOG_DIR"
        exit 1
    fi

    # Collect data
    collect_data "$1"

    # Cleanup
    cleanup_old_files
}

main "$@"
