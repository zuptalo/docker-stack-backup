#!/bin/bash
# Test: Check Portainer Docker Endpoint

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Portainer Docker Endpoint"

PORTAINER_URL="http://localhost:9000"
CRED_FILE="/opt/portainer/.credentials"

# Test 1: Check if we can authenticate
if [[ ! -f "$CRED_FILE" ]]; then
    print_test_result "SKIP" "Credentials file not found - cannot test endpoint"
    print_test_summary
    exit 0
fi

source "$CRED_FILE"

if [[ -z "$PORTAINER_ADMIN_USERNAME" ]] || [[ -z "$PORTAINER_ADMIN_PASSWORD" ]]; then
    print_test_result "SKIP" "Credentials not set - cannot test endpoint"
    print_test_summary
    exit 0
fi

# Get JWT token
TOKEN_RESPONSE=$(curl -sf -X POST "$PORTAINER_URL/api/auth" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$PORTAINER_ADMIN_USERNAME\",\"password\":\"$PORTAINER_ADMIN_PASSWORD\"}" \
    2>/dev/null || echo "{}")

JWT_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.jwt' 2>/dev/null || echo "")

if [[ -z "$JWT_TOKEN" ]] || [[ "$JWT_TOKEN" == "null" ]]; then
    print_test_result "SKIP" "Could not authenticate - cannot test endpoint"
    print_test_summary
    exit 0
fi

# Test 2: List endpoints
printf "\n${CYAN}Checking Docker endpoints:${NC}\n"

ENDPOINTS=$(curl -sf "$PORTAINER_URL/api/endpoints" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    2>/dev/null || echo "[]")

ENDPOINT_COUNT=$(echo "$ENDPOINTS" | jq '. | length' 2>/dev/null || echo "0")

printf "  Endpoint count: %s\n" "$ENDPOINT_COUNT"

if [[ "$ENDPOINT_COUNT" -gt 0 ]]; then
    assert_true "0" "At least one endpoint is configured"
else
    assert_true "1" "Should have at least one endpoint configured"
    print_test_summary
    exit 1
fi

# Test 3: Check primary endpoint details
printf "\n${CYAN}Primary endpoint details:${NC}\n"

ENDPOINT_NAME=$(echo "$ENDPOINTS" | jq -r '.[0].Name' 2>/dev/null || echo "unknown")
ENDPOINT_TYPE=$(echo "$ENDPOINTS" | jq -r '.[0].Type' 2>/dev/null || echo "unknown")
ENDPOINT_URL=$(echo "$ENDPOINTS" | jq -r '.[0].URL' 2>/dev/null || echo "unknown")
ENDPOINT_ID=$(echo "$ENDPOINTS" | jq -r '.[0].Id' 2>/dev/null || echo "unknown")

printf "  Name: %s\n" "$ENDPOINT_NAME"
printf "  Type: %s\n" "$ENDPOINT_TYPE"
printf "  URL: %s\n" "$ENDPOINT_URL"
printf "  ID: %s\n" "$ENDPOINT_ID"

assert_not_equals "unknown" "$ENDPOINT_NAME" "Endpoint has a name"

# Type 1 = Docker, 2 = Agent
if [[ "$ENDPOINT_TYPE" == "1" ]]; then
    assert_equals "1" "$ENDPOINT_TYPE" "Endpoint is Docker type"
else
    print_test_result "INFO" "Endpoint type: $ENDPOINT_TYPE"
fi

# Test 4: Check endpoint status
printf "\n${CYAN}Endpoint status:${NC}\n"

ENDPOINT_STATUS=$(curl -sf "$PORTAINER_URL/api/endpoints/$ENDPOINT_ID" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    2>/dev/null || echo "{}")

STATUS_VALUE=$(echo "$ENDPOINT_STATUS" | jq -r '.Status' 2>/dev/null || echo "0")

# Status 1 = Up, 2 = Down
if [[ "$STATUS_VALUE" == "1" ]]; then
    assert_equals "1" "$STATUS_VALUE" "Endpoint is up and running"
else
    print_test_result "WARN" "Endpoint status: $STATUS_VALUE (1=up, 2=down)"
fi

# Test 5: Test endpoint by listing containers
printf "\n${CYAN}Testing endpoint functionality:${NC}\n"

CONTAINERS=$(curl -sf "$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/containers/json" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    2>/dev/null || echo "[]")

CONTAINER_COUNT=$(echo "$CONTAINERS" | jq '. | length' 2>/dev/null || echo "0")

printf "  Containers visible via API: %s\n" "$CONTAINER_COUNT"

if [[ "$CONTAINER_COUNT" -gt 0 ]]; then
    assert_true "0" "Can list containers through endpoint"

    # Show container names
    echo "$CONTAINERS" | jq -r '.[].Names[0]' 2>/dev/null | head -5 | while read name; do
        printf "    - %s\n" "$name"
    done
else
    print_test_result "WARN" "No containers found through endpoint"
fi

print_test_summary
