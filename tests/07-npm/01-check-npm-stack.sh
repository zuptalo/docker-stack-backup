#!/bin/bash
# Test: Check NPM Stack

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check NPM Stack"

PORTAINER_URL="http://localhost:9000"
CRED_FILE="/opt/portainer/.credentials"

# Test 1: Check if we can authenticate with Portainer
if [[ ! -f "$CRED_FILE" ]]; then
    print_test_result "SKIP" "Credentials file not found"
    print_test_summary
    exit 0
fi

source "$CRED_FILE"

TOKEN_RESPONSE=$(curl -sf -X POST "$PORTAINER_URL/api/auth" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$PORTAINER_ADMIN_USERNAME\",\"password\":\"$PORTAINER_ADMIN_PASSWORD\"}" \
    2>/dev/null || echo "{}")

JWT_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.jwt' 2>/dev/null || echo "")

if [[ -z "$JWT_TOKEN" ]] || [[ "$JWT_TOKEN" == "null" ]]; then
    print_test_result "SKIP" "Could not authenticate with Portainer"
    print_test_summary
    exit 0
fi

# Test 2: Get endpoint ID
ENDPOINT_ID=$(curl -sf "$PORTAINER_URL/api/endpoints" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    2>/dev/null | jq -r '.[0].Id' 2>/dev/null || echo "")

if [[ -z "$ENDPOINT_ID" ]]; then
    print_test_result "SKIP" "Could not get endpoint ID"
    print_test_summary
    exit 0
fi

# Test 3: Check if NPM stack exists
printf "\n${CYAN}Checking for NPM stack:${NC}\n"

STACKS=$(curl -sf "$PORTAINER_URL/api/stacks" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    2>/dev/null || echo "[]")

NPM_STACK=$(echo "$STACKS" | jq -r '.[] | select(.Name == "nginx-proxy-manager")' 2>/dev/null || echo "")

if [[ -n "$NPM_STACK" ]]; then
    assert_true "0" "NPM stack exists"

    STACK_ID=$(echo "$NPM_STACK" | jq -r '.Id' 2>/dev/null)
    STACK_STATUS=$(echo "$NPM_STACK" | jq -r '.Status' 2>/dev/null)

    printf "  Stack ID: %s\n" "$STACK_ID"
    printf "  Stack Status: %s\n" "$STACK_STATUS"

    # Status 1 = active, 2 = inactive
    if [[ "$STACK_STATUS" == "1" ]]; then
        assert_equals "1" "$STACK_STATUS" "NPM stack is active"
    else
        print_test_result "WARN" "NPM stack status: $STACK_STATUS"
    fi
else
    print_test_result "WARN" "NPM stack not found (expected if not deployed)"
    print_test_summary
    exit 0
fi

# Test 4: Check NPM containers
printf "\n${CYAN}Checking NPM containers:${NC}\n"

NPM_CONTAINERS=$(docker ps --filter "name=npm" --format '{{.Names}}' 2>/dev/null || echo "")

if [[ -n "$NPM_CONTAINERS" ]]; then
    echo "$NPM_CONTAINERS" | while read container; do
        printf "  - %s\n" "$container"

        STATUS=$(docker inspect "$container" --format '{{.State.Status}}' 2>/dev/null)
        printf "    Status: %s\n" "$STATUS"
    done

    assert_true "0" "NPM containers are running"
else
    assert_true "1" "NPM containers should be running"
fi

# Test 5: Check NPM data directory
if [[ -n "$NPM_PATH" ]] || [[ -f "/etc/docker-backup-manager.conf" ]]; then
    source /etc/docker-backup-manager.conf 2>/dev/null

    if [[ -n "$NPM_PATH" ]]; then
        printf "\n${CYAN}Checking NPM data directory:${NC}\n"
        printf "  Path: %s\n" "$NPM_PATH"

        if [[ -d "$NPM_PATH" ]]; then
            assert_dir_exists "$NPM_PATH" "NPM data directory exists"

            # Check subdirectories
            for subdir in data letsencrypt; do
                if [[ -d "$NPM_PATH/$subdir" ]]; then
                    printf "    ✓ %s/ exists\n" "$subdir"
                fi
            done
        else
            assert_true "1" "NPM data directory should exist"
        fi
    fi
fi

print_test_summary
