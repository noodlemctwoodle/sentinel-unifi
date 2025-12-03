#!/bin/bash
#
# UniFi Integration API v1 Endpoint Test Script
# Tests all Integration API v1 endpoints and compares with Legacy API
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONTROLLER_IP="${CONTROLLER_IP:-}"
API_KEY="${API_KEY:-}"
OUTPUT_DIR="./api-test-results"

# Usage
if [[ -z "$API_KEY" || -z "$CONTROLLER_IP" ]]; then
    echo "Usage: CONTROLLER_IP=192.0.2.10 API_KEY=your_key $0"
    echo ""
    echo "Or set environment variables:"
    echo "  export CONTROLLER_IP=192.0.2.10  # Your UniFi controller IP"
    echo "  export API_KEY=your_api_key_here"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# API call function
call_api() {
    local endpoint="$1"
    local output_file="$2"
    local api_type="${3:-v1}" # v1 or legacy

    local url
    if [[ "$api_type" == "v1" ]]; then
        url="https://${CONTROLLER_IP}:443/proxy/network/integration${endpoint}"
    else
        url="https://${CONTROLLER_IP}:443/proxy/network/api${endpoint}"
    fi

    log_info "Testing: $endpoint"

    local http_code
    http_code=$(curl -k -s -w "%{http_code}" \
        -H "X-API-Key: ${API_KEY}" \
        -H "Accept: application/json" \
        --connect-timeout 10 \
        --max-time 30 \
        -o "$output_file" \
        "$url" 2>&1 || echo "000")

    if [[ "$http_code" == "200" ]]; then
        local count
        if [[ "$api_type" == "v1" ]]; then
            # Integration API v1 uses paginated response
            count=$(jq -r '.count // 0' "$output_file" 2>/dev/null || echo "0")
        else
            # Legacy API uses data array
            count=$(jq -r '.data | length' "$output_file" 2>/dev/null || echo "0")
        fi
        log_success "HTTP 200 | Records: $count"
        echo "$count"
        return 0
    elif [[ "$http_code" == "400" ]]; then
        local error_msg=$(jq -r '.message // "Unknown error"' "$output_file" 2>/dev/null)
        log_error "HTTP 400 | $error_msg"
        return 1
    elif [[ "$http_code" == "404" ]]; then
        log_error "HTTP 404 | Endpoint not found"
        return 1
    else
        log_error "HTTP $http_code | Request failed"
        return 1
    fi
}

# Step 1: Get Site UUID
echo ""
echo "========================================="
echo "Step 1: Getting Site UUID"
echo "========================================="

SITE_UUID=""
if call_api "/v1/sites" "$OUTPUT_DIR/sites.json" "v1" > /dev/null; then
    SITE_UUID=$(jq -r '.data[0].id' "$OUTPUT_DIR/sites.json")
    SITE_NAME=$(jq -r '.data[0].name' "$OUTPUT_DIR/sites.json")
    log_success "Site UUID: $SITE_UUID"
    log_success "Site Name: $SITE_NAME"
else
    log_error "Failed to get site UUID - cannot continue"
    exit 1
fi

# Step 2: Test Integration API v1 Endpoints
echo ""
echo "========================================="
echo "Step 2: Testing Integration API v1 Endpoints"
echo "========================================="

declare -A V1_RESULTS

test_v1_endpoint() {
    local name="$1"
    local endpoint="$2"

    echo ""
    echo "--- Testing: $name ---"

    local output_file="$OUTPUT_DIR/v1_${name}.json"
    if call_api "$endpoint" "$output_file" "v1" > /dev/null; then
        V1_RESULTS[$name]="✓"

        # Show sample fields
        local sample_keys=$(jq -r '.data[0] | keys | @json' "$output_file" 2>/dev/null)
        if [[ -n "$sample_keys" && "$sample_keys" != "null" ]]; then
            log_info "Sample fields: $sample_keys"
        fi
    else
        V1_RESULTS[$name]="✗"
    fi
}

# Test all Integration API v1 endpoints
test_v1_endpoint "devices" "/v1/sites/${SITE_UUID}/devices"
test_v1_endpoint "clients" "/v1/sites/${SITE_UUID}/clients"
test_v1_endpoint "networks" "/v1/sites/${SITE_UUID}/networks"
test_v1_endpoint "wifi-broadcasts" "/v1/sites/${SITE_UUID}/wifi/broadcasts"
test_v1_endpoint "traffic-matching-lists" "/v1/sites/${SITE_UUID}/traffic-matching-lists"
test_v1_endpoint "acl-rules" "/v1/sites/${SITE_UUID}/acl-rules"
test_v1_endpoint "firewall-zones" "/v1/sites/${SITE_UUID}/firewall/zones"
test_v1_endpoint "vpn-site-to-site" "/v1/sites/${SITE_UUID}/vpn/site-to-site-tunnels"
test_v1_endpoint "vpn-servers" "/v1/sites/${SITE_UUID}/vpn/servers"
test_v1_endpoint "radius-profiles" "/v1/sites/${SITE_UUID}/radius/profiles"
test_v1_endpoint "device-tags" "/v1/sites/${SITE_UUID}/device-tags"
test_v1_endpoint "dpi-categories" "/v1/dpi/categories"
test_v1_endpoint "dpi-applications" "/v1/dpi/applications"
test_v1_endpoint "wans" "/v1/sites/${SITE_UUID}/wans"
test_v1_endpoint "hotspot-vouchers" "/v1/sites/${SITE_UUID}/hotspot/vouchers"

# Step 3: Test Legacy API Endpoints (for comparison)
echo ""
echo "========================================="
echo "Step 3: Testing Legacy API Endpoints"
echo "========================================="

declare -A LEGACY_RESULTS

test_legacy_endpoint() {
    local name="$1"
    local endpoint="$2"

    echo ""
    echo "--- Testing: $name ---"

    local output_file="$OUTPUT_DIR/legacy_${name}.json"
    if call_api "$endpoint" "$output_file" "legacy" > /dev/null; then
        LEGACY_RESULTS[$name]="✓"

        # Show sample fields
        local sample_keys=$(jq -r '.data[0] | keys | @json' "$output_file" 2>/dev/null)
        if [[ -n "$sample_keys" && "$sample_keys" != "null" ]]; then
            log_info "Sample fields: $sample_keys"
        fi
    else
        LEGACY_RESULTS[$name]="✗"
    fi
}

# Get legacy site ID
LEGACY_SITE_ID=$(jq -r '.data[0]._id' "$OUTPUT_DIR/sites.json" 2>/dev/null || echo "")
if [[ -z "$LEGACY_SITE_ID" ]]; then
    # Try legacy self/sites endpoint
    if call_api "/self/sites" "$OUTPUT_DIR/legacy_sites.json" "legacy" > /dev/null; then
        LEGACY_SITE_ID=$(jq -r '.data[0]._id' "$OUTPUT_DIR/legacy_sites.json")
        log_success "Legacy Site ID: $LEGACY_SITE_ID"
    fi
fi

# Test legacy endpoints that aren't in v1
test_legacy_endpoint "port-forward" "/s/default/rest/portforward"
test_legacy_endpoint "routing" "/s/default/rest/routing"
test_legacy_endpoint "site-settings" "/s/default/rest/setting"
test_legacy_endpoint "health" "/s/default/stat/health"
test_legacy_endpoint "devices-legacy" "/s/default/stat/device"
test_legacy_endpoint "clients-legacy" "/s/default/stat/sta"

# Step 4: Generate Report
echo ""
echo "========================================="
echo "Test Results Summary"
echo "========================================="
echo ""

echo "Integration API v1 Endpoints:"
echo "-----------------------------"
for endpoint in "${!V1_RESULTS[@]}"; do
    status="${V1_RESULTS[$endpoint]}"
    count=$(jq -r '.count // 0' "$OUTPUT_DIR/v1_${endpoint}.json" 2>/dev/null || echo "0")
    printf "%-30s %s (Records: %s)\n" "$endpoint" "$status" "$count"
done | sort

echo ""
echo "Legacy API Endpoints:"
echo "-----------------------------"
for endpoint in "${!LEGACY_RESULTS[@]}"; do
    status="${LEGACY_RESULTS[$endpoint]}"
    count=$(jq -r '.data | length' "$OUTPUT_DIR/legacy_${endpoint}.json" 2>/dev/null || echo "0")
    printf "%-30s %s (Records: %s)\n" "$endpoint" "$status" "$count"
done | sort

echo ""
echo "========================================="
echo "Data Comparison"
echo "========================================="
echo ""

compare_endpoints() {
    local v1_name="$1"
    local legacy_name="$2"
    local display_name="$3"

    local v1_count=$(jq -r '.count // 0' "$OUTPUT_DIR/v1_${v1_name}.json" 2>/dev/null || echo "0")
    local legacy_count=$(jq -r '.data | length' "$OUTPUT_DIR/legacy_${legacy_name}.json" 2>/dev/null || echo "0")

    echo "$display_name:"
    echo "  Integration API v1: $v1_count records"
    echo "  Legacy API: $legacy_count records"

    if [[ "$v1_count" == "$legacy_count" ]]; then
        log_success "Record counts match"
    else
        log_warning "Record count mismatch!"
    fi
    echo ""
}

compare_endpoints "devices" "devices-legacy" "Devices"
compare_endpoints "clients" "clients-legacy" "Clients"

echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "1. Review JSON files in: $OUTPUT_DIR/"
echo "2. Check field structures for schema design"
echo "3. Identify which endpoints to migrate to v1"
echo "4. Design comprehensive schemas based on actual data"
echo ""
echo "To view sample data:"
echo "  jq '.data[0]' $OUTPUT_DIR/v1_devices.json"
echo "  jq '.data[0]' $OUTPUT_DIR/v1_networks.json"
echo ""

log_success "Test complete!"
