#!/bin/bash
# Test: Multi-Stack Restore Verification

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test Multi-Stack Restore"

# Load configuration
DEFAULT_CONFIG="/etc/docker-backup-manager.conf"
if [[ ! -f "$DEFAULT_CONFIG" ]]; then
    skip_test "Config file not found"
fi

source "$DEFAULT_CONFIG"

# Test 1: Check Portainer credentials
printf "\n${CYAN}Checking Portainer credentials:${NC}\n"

if [[ ! -f "$PORTAINER_PATH/.credentials" ]]; then
    skip_test "Portainer credentials not found"
fi

source "$PORTAINER_PATH/.credentials"
assert_true "0" "Portainer credentials loaded"

# Test 2: Authenticate with Portainer API
printf "\n${CYAN}Authenticating with Portainer API:${NC}\n"

AUTH_PAYLOAD=$(jq -n \
    --arg user "$PORTAINER_ADMIN_USERNAME" \
    --arg pass "$PORTAINER_ADMIN_PASSWORD" \
    '{username: $user, password: $pass}')

JWT_TOKEN=$(curl -s -X POST "${PORTAINER_API_URL}/auth" \
    -H "Content-Type: application/json" \
    -d "$AUTH_PAYLOAD" | jq -r '.jwt // empty')

if [[ -n "$JWT_TOKEN" && "$JWT_TOKEN" != "null" ]]; then
    assert_true "0" "Successfully authenticated with Portainer API"
else
    skip_test "Failed to authenticate with Portainer API"
fi

# Test 3: Get current stacks
printf "\n${CYAN}Querying deployed stacks:${NC}\n"

STACKS_RESPONSE=$(curl -s -H "Authorization: Bearer $JWT_TOKEN" \
    "${PORTAINER_API_URL}/stacks")

if [[ -z "$STACKS_RESPONSE" ]]; then
    skip_test "Failed to retrieve stacks from Portainer API"
fi

STACK_COUNT=$(echo "$STACKS_RESPONSE" | jq '. | length' 2>/dev/null || echo "0")

printf "  Total stacks deployed: %d\n" "$STACK_COUNT"

if [[ $STACK_COUNT -lt 2 ]]; then
    skip_test "Need at least 2 stacks deployed to test multi-stack restore (current: $STACK_COUNT)"
fi

assert_true "0" "Multiple stacks are deployed ($STACK_COUNT stacks)"

# Test 4: Verify all stacks have running status
printf "\n${CYAN}Checking stack statuses:${NC}\n"

RUNNING_STACKS=0
STOPPED_STACKS=0

echo "$STACKS_RESPONSE" | jq -c '.[]' | while read stack; do
    STACK_NAME=$(echo "$stack" | jq -r '.Name')
    STACK_STATUS=$(echo "$stack" | jq -r '.Status')

    if [[ "$STACK_STATUS" == "1" ]]; then
        printf "  ✓ %s: Running\n" "$STACK_NAME"
        RUNNING_STACKS=$((RUNNING_STACKS + 1))
    else
        printf "  ✗ %s: Stopped (Status: %s)\n" "$STACK_NAME" "$STACK_STATUS"
        STOPPED_STACKS=$((STOPPED_STACKS + 1))
    fi
done

# Since we're in a subshell, we need to count again
RUNNING_COUNT=$(echo "$STACKS_RESPONSE" | jq '[.[] | select(.Status == 1)] | length')
STOPPED_COUNT=$(echo "$STACKS_RESPONSE" | jq '[.[] | select(.Status != 1)] | length')

printf "\n  Running stacks: %d\n" "$RUNNING_COUNT"
printf "  Stopped stacks: %d\n" "$STOPPED_COUNT"

if [[ $RUNNING_COUNT -ge 1 ]]; then
    assert_true "0" "At least one stack is in running state"
else
    print_test_result "WARN" "No stacks are running"
fi

# Test 5: Verify stack containers are actually running
printf "\n${CYAN}Verifying stack containers are running:${NC}\n"

CONTAINER_CHECK_FAILURES=0

echo "$STACKS_RESPONSE" | jq -r '.[] | select(.Status == 1) | .Name' | while read stack_name; do
    # Query Docker API through Portainer to get stack containers
    CONTAINERS=$(curl -s -H "Authorization: Bearer $JWT_TOKEN" \
        "${PORTAINER_API_URL}/endpoints/1/docker/containers/json" | \
        jq -r ".[] | select(.Labels.\"com.docker.compose.project\" == \"$stack_name\") | .Names[0]" 2>/dev/null)

    if [[ -n "$CONTAINERS" ]]; then
        CONTAINER_NAME=$(echo "$CONTAINERS" | head -1 | sed 's|^/||')
        printf "  ✓ %s: Container '%s' found\n" "$stack_name" "$CONTAINER_NAME"
    else
        printf "  ✗ %s: No containers found\n" "$stack_name"
        CONTAINER_CHECK_FAILURES=$((CONTAINER_CHECK_FAILURES + 1))
    fi
done

# Test 6: Check latest backup contains all current stacks
printf "\n${CYAN}Checking latest backup contains all stacks:${NC}\n"

LATEST_BACKUP=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | sort -r | head -1)

if [[ -z "$LATEST_BACKUP" ]]; then
    skip_test "No backup found to verify"
fi

TEMP_DIR=$(mktemp -d)
tar -xzf "$LATEST_BACKUP" -C "$TEMP_DIR" stack_states.json 2>/dev/null

if [[ ! -f "$TEMP_DIR/stack_states.json" ]]; then
    rm -rf "$TEMP_DIR"
    skip_test "stack_states.json not found in backup"
fi

BACKED_UP_STACK_COUNT=$(jq '.total_stacks' "$TEMP_DIR/stack_states.json")
printf "  Stacks in latest backup: %d\n" "$BACKED_UP_STACK_COUNT"
printf "  Stacks currently deployed: %d\n" "$STACK_COUNT"

if [[ $BACKED_UP_STACK_COUNT -eq $STACK_COUNT ]]; then
    assert_true "0" "Backup contains all currently deployed stacks"
else
    print_test_result "WARN" "Backup stack count ($BACKED_UP_STACK_COUNT) differs from deployed count ($STACK_COUNT)"
fi

# Test 7: Verify backed-up stacks have compose content
printf "\n${CYAN}Verifying backed-up stacks have compose content:${NC}\n"

STACKS_WITH_COMPOSE=0
STACKS_WITHOUT_COMPOSE=0

jq -c '.stacks[]' "$TEMP_DIR/stack_states.json" | while read -r stack; do
    STACK_NAME=$(echo "$stack" | jq -r '.name')
    # Check if compose_file_content exists and is not empty
    HAS_COMPOSE=$(echo "$stack" | jq 'has("compose_file_content") and .compose_file_content != null and .compose_file_content != ""')

    if [[ "$HAS_COMPOSE" == "true" ]]; then
        printf "  ✓ %s: Has compose content\n" "$STACK_NAME"
    else
        printf "  ✗ %s: Missing compose content\n" "$STACK_NAME"
    fi
done

# Count again for assertion
STACKS_WITH_COMPOSE=$(jq '[.stacks[] | select(has("compose_file_content") and .compose_file_content != null and .compose_file_content != "")] | length' "$TEMP_DIR/stack_states.json")
printf "\n  Stacks with compose content: %d/%d\n" "$STACKS_WITH_COMPOSE" "$BACKED_UP_STACK_COUNT"

if [[ $STACKS_WITH_COMPOSE -eq $BACKED_UP_STACK_COUNT ]]; then
    assert_true "0" "All backed-up stacks have compose content"
else
    assert_true "1" "Some stacks are missing compose content"
fi

# Test 8: Verify stack names match between backup and deployment
printf "\n${CYAN}Verifying stack names consistency:${NC}\n"

DEPLOYED_NAMES=$(echo "$STACKS_RESPONSE" | jq -r '.[].Name' | sort)
BACKED_UP_NAMES=$(jq -r '.stacks[].name' "$TEMP_DIR/stack_states.json" | sort)

printf "  Deployed stacks:\n"
echo "$DEPLOYED_NAMES" | while read name; do
    printf "    - %s\n" "$name"
done

printf "  Backed-up stacks:\n"
echo "$BACKED_UP_NAMES" | while read name; do
    printf "    - %s\n" "$name"
done

if [[ "$DEPLOYED_NAMES" == "$BACKED_UP_NAMES" ]]; then
    assert_true "0" "Stack names match between deployment and backup"
else
    print_test_result "WARN" "Stack names differ between deployment and backup"
fi

# Cleanup
rm -rf "$TEMP_DIR"

print_test_summary
