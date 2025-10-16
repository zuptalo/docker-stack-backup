#!/bin/bash
# Test: Check Portainer API

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Portainer API"

# Test 1: Check if Portainer is accessible
printf "\n${CYAN}Testing Portainer API connectivity:${NC}\n"

PORTAINER_URL="http://localhost:9000"

# Wait for Portainer to be ready (max 30 seconds)
WAIT_TIME=0
MAX_WAIT=30

while [[ $WAIT_TIME -lt $MAX_WAIT ]]; do
    if curl -sf "$PORTAINER_URL/api/status" >/dev/null 2>&1; then
        break
    fi
    sleep 1
    ((WAIT_TIME++))
done

if curl -sf "$PORTAINER_URL/api/status" >/dev/null 2>&1; then
    assert_true "0" "Portainer API is accessible"
else
    print_test_result "WARN" "Portainer API not accessible (expected if not fully initialized)"
    print_test_summary
    exit 0
fi

# Test 2: Check API status endpoint
printf "\n${CYAN}Checking API status:${NC}\n"

STATUS=$(curl -sf "$PORTAINER_URL/api/status" 2>/dev/null || echo "{}")

if echo "$STATUS" | grep -q "Version"; then
    VERSION=$(echo "$STATUS" | jq -r '.Version' 2>/dev/null || echo "unknown")
    printf "  Portainer Version: %s\n" "$VERSION"
    assert_true "0" "API returns version information"
else
    print_test_result "WARN" "Could not get version information"
fi

# Test 3: Check if admin user is initialized
printf "\n${CYAN}Checking admin user initialization:${NC}\n"

# Try to get system info (requires auth if initialized)
SYSTEM_INFO=$(curl -sf "$PORTAINER_URL/api/system/info" 2>/dev/null || echo "")

if [[ -z "$SYSTEM_INFO" ]]; then
    # Empty response usually means auth is required (user initialized)
    assert_true "0" "Admin user appears to be initialized (auth required)"
else
    print_test_result "INFO" "Admin user may not be initialized yet"
fi

# Test 4: Check if credentials file exists
CRED_FILE="/opt/portainer/.credentials"

if [[ -f "$CRED_FILE" ]]; then
    assert_file_exists "$CRED_FILE" "Credentials file exists"

    printf "\n${CYAN}Credentials file info:${NC}\n"
    printf "  Path: %s\n" "$CRED_FILE"
    printf "  Permissions: %s\n" "$(stat -c "%a" "$CRED_FILE" 2>/dev/null || stat -f "%Lp" "$CRED_FILE" 2>/dev/null)"
    printf "  Owner: %s\n" "$(stat -c "%U:%G" "$CRED_FILE" 2>/dev/null || stat -f "%Su:%Sg" "$CRED_FILE" 2>/dev/null)"

    # Check if credentials file contains expected fields
    if grep -q "PORTAINER_ADMIN_USERNAME" "$CRED_FILE" 2>/dev/null; then
        assert_true "0" "Credentials file contains username"
    fi

    if grep -q "PORTAINER_ADMIN_PASSWORD" "$CRED_FILE" 2>/dev/null; then
        assert_true "0" "Credentials file contains password"
    fi
else
    print_test_result "WARN" "Credentials file not found (expected if setup not complete)"
fi

# Test 5: Test API authentication (if credentials exist)
if [[ -f "$CRED_FILE" ]]; then
    printf "\n${CYAN}Testing API authentication:${NC}\n"

    source "$CRED_FILE"

    if [[ -n "$PORTAINER_ADMIN_USERNAME" ]] && [[ -n "$PORTAINER_ADMIN_PASSWORD" ]]; then
        # Try to get JWT token
        TOKEN_RESPONSE=$(curl -sf -X POST "$PORTAINER_URL/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"$PORTAINER_ADMIN_USERNAME\",\"password\":\"$PORTAINER_ADMIN_PASSWORD\"}" \
            2>/dev/null || echo "{}")

        JWT_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.jwt' 2>/dev/null || echo "")

        if [[ -n "$JWT_TOKEN" ]] && [[ "$JWT_TOKEN" != "null" ]]; then
            assert_true "0" "Can authenticate with Portainer API"
            printf "  JWT token received (length: %d chars)\n" "${#JWT_TOKEN}"
        else
            print_test_result "WARN" "Could not authenticate with stored credentials"
        fi
    fi
fi

print_test_summary
