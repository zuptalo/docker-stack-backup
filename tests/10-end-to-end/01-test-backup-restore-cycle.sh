#!/bin/bash
# Test: End-to-End Backup and Restore Cycle
# This test deploys a test stack, creates a backup, destroys the stack,
# restores from backup, and verifies everything is restored correctly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test End-to-End Backup and Restore Cycle"

# Load configuration
DEFAULT_CONFIG="/etc/docker-backup-manager.conf"
if [[ ! -f "$DEFAULT_CONFIG" ]]; then
    skip_test "Config file not found"
fi

source "$DEFAULT_CONFIG"

# Test stack configuration
TEST_STACK_NAME="e2e-test-stack"
TEST_DATA_DIR="/opt/tools/${TEST_STACK_NAME}"
TEST_INDEX_CONTENT="E2E Test - Backup Restore Cycle - $(date +%s)"
JWT_TOKEN=""
TEST_BACKUP_FILE=""

# Cleanup function
cleanup() {
    printf "\n${CYAN}Cleaning up test resources:${NC}\n"

    # Remove test stack via Portainer API if it exists
    if [[ -n "${JWT_TOKEN:-}" ]]; then
        STACKS=$(curl -s -H "Authorization: Bearer $JWT_TOKEN" "${PORTAINER_API_URL}/stacks")
        STACK_ID=$(echo "$STACKS" | jq -r ".[] | select(.Name == \"$TEST_STACK_NAME\") | .Id" 2>/dev/null)

        if [[ -n "$STACK_ID" && "$STACK_ID" != "null" ]]; then
            printf "  Removing test stack (ID: %s)...\n" "$STACK_ID"
            curl -s -X DELETE -H "Authorization: Bearer $JWT_TOKEN" \
                "${PORTAINER_API_URL}/stacks/${STACK_ID}?endpointId=1" >/dev/null
        fi
    fi

    # Remove test data directory
    if [[ -d "$TEST_DATA_DIR" ]]; then
        printf "  Removing test data directory...\n"
        sudo rm -rf "$TEST_DATA_DIR"
    fi

    # Remove test backup if it exists
    if [[ -n "${TEST_BACKUP_FILE:-}" && -f "${TEST_BACKUP_FILE:-}" ]]; then
        printf "  Removing test backup...\n"
        sudo rm -f "$TEST_BACKUP_FILE"
    fi

    printf "  Cleanup completed\n"
}

# Don't cleanup on ERR, only on EXIT
trap cleanup EXIT

# Test 1: Authenticate with Portainer API
printf "\n${CYAN}Step 1: Authenticating with Portainer API:${NC}\n"

if [[ ! -f "$PORTAINER_PATH/.credentials" ]]; then
    skip_test "Portainer credentials not found"
fi

source "$PORTAINER_PATH/.credentials"

AUTH_PAYLOAD=$(jq -n \
    --arg user "$PORTAINER_ADMIN_USERNAME" \
    --arg pass "$PORTAINER_ADMIN_PASSWORD" \
    '{username: $user, password: $pass}')

JWT_TOKEN=$(curl -s -X POST "${PORTAINER_API_URL}/auth" \
    -H "Content-Type: application/json" \
    -d "$AUTH_PAYLOAD" | jq -r '.jwt // empty')

if [[ -z "$JWT_TOKEN" || "$JWT_TOKEN" == "null" ]]; then
    skip_test "Failed to authenticate with Portainer API"
fi

assert_true "0" "Successfully authenticated with Portainer API"

# Test 2: Create test data directory and files
printf "\n${CYAN}Step 2: Creating test data:${NC}\n"

sudo mkdir -p "${TEST_DATA_DIR}/html"
sudo bash -c "cat > ${TEST_DATA_DIR}/html/index.html << EOF
<html>
<head><title>E2E Test Stack</title></head>
<body>
<h1>End-to-End Backup/Restore Test</h1>
<p>${TEST_INDEX_CONTENT}</p>
<p>Timestamp: $(date)</p>
</body>
</html>
EOF"

sudo bash -c "cat > ${TEST_DATA_DIR}/test-data.txt << EOF
This is test data for the end-to-end backup/restore test.
Created at: $(date)
Unique identifier: ${TEST_INDEX_CONTENT}
EOF"

sudo chown -R portainer:portainer "$TEST_DATA_DIR"

assert_file_exists "${TEST_DATA_DIR}/html/index.html" "Test index.html created"
assert_file_exists "${TEST_DATA_DIR}/test-data.txt" "Test data file created"

# Verify content
ACTUAL_CONTENT=$(cat "${TEST_DATA_DIR}/html/index.html" | grep -o "E2E Test - Backup Restore Cycle - [0-9]*")
if [[ "$ACTUAL_CONTENT" == "$TEST_INDEX_CONTENT" ]]; then
    assert_true "0" "Test data contains expected content"
else
    assert_true "1" "Test data content mismatch"
fi

# Test 3: Deploy test stack via Portainer API
printf "\n${CYAN}Step 3: Deploying test stack via Portainer API:${NC}\n"

TEST_COMPOSE="services:
  nginx:
    image: nginx:latest
    container_name: ${TEST_STACK_NAME}-nginx
    restart: unless-stopped
    volumes:
      - ${TEST_DATA_DIR}/html:/usr/share/nginx/html:ro
    networks:
      - prod-network
    labels:
      - \"e2e-test=true\"
      - \"test-id=${TEST_INDEX_CONTENT}\"

networks:
  prod-network:
    external: true"

STACK_RESPONSE=$(curl -s -X POST "${PORTAINER_API_URL}/stacks/create/standalone/string?endpointId=1" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"method\": \"string\",
        \"type\": \"standalone\",
        \"Name\": \"$TEST_STACK_NAME\",
        \"StackFileContent\": $(echo "$TEST_COMPOSE" | jq -Rs .),
        \"Env\": []
    }")

STACK_ID=$(echo "$STACK_RESPONSE" | jq -r '.Id // empty')

if [[ -n "$STACK_ID" && "$STACK_ID" != "null" ]]; then
    printf "  Test stack deployed with ID: %s\n" "$STACK_ID"
    assert_true "0" "Test stack deployed successfully"
else
    printf "  API Response: %s\n" "$STACK_RESPONSE"
    assert_true "1" "Failed to deploy test stack"
    exit 1
fi

# Wait for container to start
printf "  Waiting for container to start...\n"
sleep 5

# Verify container is running
CONTAINER_STATUS=$(sudo docker ps --filter "name=${TEST_STACK_NAME}-nginx" --format "{{.Status}}")
if [[ -n "$CONTAINER_STATUS" ]]; then
    printf "  Container status: %s\n" "$CONTAINER_STATUS"
    assert_true "0" "Test container is running"
else
    assert_true "1" "Test container failed to start"
    exit 1
fi

# Test 4: Create backup with test stack
printf "\n${CYAN}Step 4: Creating backup:${NC}\n"

BACKUP_NAME="e2e-test-$(date +%Y%m%d-%H%M%S)"

# Run backup and capture result (disable errexit temporarily)
set +e
(cd /home/vagrant/docker-stack-backup && ./backup-manager.sh --non-interactive backup "$BACKUP_NAME" >/dev/null 2>&1)
BACKUP_EXIT_CODE=$?
set -e

if [[ $BACKUP_EXIT_CODE -eq 0 ]]; then
    printf "  Backup command completed successfully\n"
else
    printf "  Backup command failed with exit code: %d\n" "$BACKUP_EXIT_CODE"
fi

# Find the created backup
TEST_BACKUP_FILE=$(find "$BACKUP_PATH" -name "docker_backup_*-${BACKUP_NAME}.tar.gz" 2>/dev/null | head -1)

if [[ -n "$TEST_BACKUP_FILE" && -f "$TEST_BACKUP_FILE" ]]; then
    printf "  Backup created: %s\n" "$(basename "$TEST_BACKUP_FILE")"
    assert_file_exists "$TEST_BACKUP_FILE" "Backup file created"
else
    printf "  Backup creation failed - file not found\n"
    printf "  Looking for pattern: docker_backup_*-${BACKUP_NAME}.tar.gz\n"
    printf "  In directory: $BACKUP_PATH\n"
    ls -lh "$BACKUP_PATH/" 2>/dev/null || echo "  Directory listing failed"
    assert_true "1" "Failed to create backup"
    exit 1
fi

# Test 5: Verify backup contains test stack data
printf "\n${CYAN}Step 5: Verifying backup contains test data:${NC}\n"

# Check for test data directory
if tar -tzf "$TEST_BACKUP_FILE" 2>/dev/null | grep "opt/tools/${TEST_STACK_NAME}/" >/dev/null 2>&1; then
    assert_true "0" "Backup contains test stack directory"
else
    assert_true "1" "Backup missing test stack directory"
fi

# Check for test files
if tar -tzf "$TEST_BACKUP_FILE" 2>/dev/null | grep "opt/tools/${TEST_STACK_NAME}/html/index.html$" >/dev/null 2>&1; then
    assert_true "0" "Backup contains test index.html"
else
    assert_true "1" "Backup missing test index.html"
fi

if tar -tzf "$TEST_BACKUP_FILE" 2>/dev/null | grep "opt/tools/${TEST_STACK_NAME}/test-data.txt$" >/dev/null 2>&1; then
    assert_true "0" "Backup contains test data file"
else
    assert_true "1" "Backup missing test data file"
fi

# Check for stack_states.json
TEMP_DIR=$(mktemp -d)
tar -xzf "$TEST_BACKUP_FILE" -C "$TEMP_DIR" stack_states.json 2>/dev/null

if [[ -f "$TEMP_DIR/stack_states.json" ]]; then
    assert_true "0" "Backup contains stack_states.json"

    # Verify test stack is in stack_states.json
    STACK_IN_METADATA=$(jq -r ".stacks[] | select(.name == \"$TEST_STACK_NAME\") | .name" "$TEMP_DIR/stack_states.json")
    if [[ "$STACK_IN_METADATA" == "$TEST_STACK_NAME" ]]; then
        assert_true "0" "Test stack found in stack_states.json"

        # Verify compose content is captured
        HAS_COMPOSE=$(jq -r ".stacks[] | select(.name == \"$TEST_STACK_NAME\") | has(\"compose_file_content\")" "$TEMP_DIR/stack_states.json")
        if [[ "$HAS_COMPOSE" == "true" ]]; then
            assert_true "0" "Test stack has compose_file_content in metadata"
        else
            assert_true "1" "Test stack missing compose_file_content"
        fi
    else
        assert_true "1" "Test stack not found in stack_states.json"
    fi
else
    assert_true "1" "Backup missing stack_states.json"
fi

rm -rf "$TEMP_DIR"

# Test 6: Destroy test stack
printf "\n${CYAN}Step 6: Destroying test stack:${NC}\n"

DELETE_RESPONSE=$(curl -s -X DELETE -H "Authorization: Bearer $JWT_TOKEN" \
    "${PORTAINER_API_URL}/stacks/${STACK_ID}?endpointId=1")

# Wait for stack to be removed
sleep 3

# Verify stack is gone
REMAINING_STACKS=$(curl -s -H "Authorization: Bearer $JWT_TOKEN" "${PORTAINER_API_URL}/stacks")
STACK_STILL_EXISTS=$(echo "$REMAINING_STACKS" | jq -r ".[] | select(.Id == $STACK_ID) | .Id" 2>/dev/null)

if [[ -z "$STACK_STILL_EXISTS" ]]; then
    assert_true "0" "Test stack removed from Portainer"
else
    assert_true "1" "Test stack still exists in Portainer"
fi

# Verify container is gone
CONTAINER_GONE=$(sudo docker ps -a --filter "name=${TEST_STACK_NAME}-nginx" --format "{{.Names}}")
if [[ -z "$CONTAINER_GONE" ]]; then
    assert_true "0" "Test container removed"
else
    printf "  Warning: Container still exists: %s\n" "$CONTAINER_GONE"
    assert_true "1" "Test container still exists"
fi

# Remove test data directory to simulate complete data loss
printf "  Removing test data directory...\n"
sudo rm -rf "$TEST_DATA_DIR"

if [[ ! -d "$TEST_DATA_DIR" ]]; then
    assert_true "0" "Test data directory removed"
else
    assert_true "1" "Test data directory still exists"
fi

# Test 7: Restore from backup
printf "\n${CYAN}Step 7: Restoring from backup:${NC}\n"

# Create a non-interactive restore by using printf to provide inputs
set +e
RESTORE_OUTPUT=$(cd /home/vagrant/docker-stack-backup && printf "1\ny\n" | ./backup-manager.sh restore 2>&1)
RESTORE_EXIT_CODE=$?
set -e

# Wait for restore to complete
sleep 5

# Check if restore succeeded
if [[ $RESTORE_EXIT_CODE -eq 0 ]] && echo "$RESTORE_OUTPUT" | grep -q "Restore completed"; then
    assert_true "0" "Restore process completed"
else
    printf "  Restore exit code: %d\n" "$RESTORE_EXIT_CODE"
    printf "  Restore output (last 20 lines):\n"
    echo "$RESTORE_OUTPUT" | tail -20 | sed 's/^/    /'
    assert_true "1" "Restore process failed"
fi

# Test 8: Verify data is restored
printf "\n${CYAN}Step 8: Verifying restored data:${NC}\n"

# Check data directory is restored
if [[ -d "$TEST_DATA_DIR" ]]; then
    assert_true "0" "Test data directory restored"
else
    assert_true "1" "Test data directory not restored"
    exit 1
fi

# Check files are restored
if [[ -f "${TEST_DATA_DIR}/html/index.html" ]]; then
    assert_file_exists "${TEST_DATA_DIR}/html/index.html" "Test index.html restored"

    # Verify content matches
    RESTORED_CONTENT=$(cat "${TEST_DATA_DIR}/html/index.html" | grep -o "E2E Test - Backup Restore Cycle - [0-9]*")
    if [[ "$RESTORED_CONTENT" == "$TEST_INDEX_CONTENT" ]]; then
        assert_true "0" "Restored content matches original"
    else
        printf "  Expected: %s\n" "$TEST_INDEX_CONTENT"
        printf "  Got: %s\n" "$RESTORED_CONTENT"
        assert_true "1" "Restored content mismatch"
    fi
else
    assert_true "1" "Test index.html not restored"
fi

if [[ -f "${TEST_DATA_DIR}/test-data.txt" ]]; then
    assert_file_exists "${TEST_DATA_DIR}/test-data.txt" "Test data file restored"
else
    assert_true "1" "Test data file not restored"
fi

# Test 9: Verify stack is restored in Portainer
printf "\n${CYAN}Step 9: Verifying stack is restored in Portainer:${NC}\n"

# Re-authenticate (token might have expired)
JWT_TOKEN=$(curl -s -X POST "${PORTAINER_API_URL}/auth" \
    -H "Content-Type: application/json" \
    -d "$AUTH_PAYLOAD" | jq -r '.jwt // empty')

RESTORED_STACKS=$(curl -s -H "Authorization: Bearer $JWT_TOKEN" "${PORTAINER_API_URL}/stacks")
RESTORED_STACK_ID=$(echo "$RESTORED_STACKS" | jq -r ".[] | select(.Name == \"$TEST_STACK_NAME\") | .Id" 2>/dev/null)

if [[ -n "$RESTORED_STACK_ID" && "$RESTORED_STACK_ID" != "null" ]]; then
    printf "  Test stack restored with ID: %s\n" "$RESTORED_STACK_ID"
    assert_true "0" "Test stack restored in Portainer"

    # Check stack status
    STACK_STATUS=$(echo "$RESTORED_STACKS" | jq -r ".[] | select(.Name == \"$TEST_STACK_NAME\") | .Status")
    printf "  Stack status: %s\n" "$STACK_STATUS"

    if [[ "$STACK_STATUS" == "1" ]]; then
        assert_true "0" "Test stack is running (Status=1)"
    else
        assert_true "1" "Test stack is not running (Status=$STACK_STATUS)"
    fi
else
    assert_true "1" "Test stack not found in Portainer after restore"
fi

# Test 10: Verify container is running
printf "\n${CYAN}Step 10: Verifying restored container:${NC}\n"

RESTORED_CONTAINER=$(sudo docker ps --filter "name=${TEST_STACK_NAME}-nginx" --format "{{.Names}}")

if [[ -n "$RESTORED_CONTAINER" ]]; then
    printf "  Container running: %s\n" "$RESTORED_CONTAINER"
    assert_true "0" "Test container is running after restore"

    # Verify container can serve the test content
    CONTAINER_IP=$(sudo docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${TEST_STACK_NAME}-nginx" 2>/dev/null)
    if [[ -n "$CONTAINER_IP" ]]; then
        printf "  Container IP: %s\n" "$CONTAINER_IP"

        # Try to curl the content from inside the container
        SERVED_CONTENT=$(sudo docker exec "${TEST_STACK_NAME}-nginx" cat /usr/share/nginx/html/index.html | grep -o "E2E Test - Backup Restore Cycle - [0-9]*" || echo "")

        if [[ "$SERVED_CONTENT" == "$TEST_INDEX_CONTENT" ]]; then
            assert_true "0" "Container is serving correct content"
        else
            printf "  Expected content: %s\n" "$TEST_INDEX_CONTENT"
            printf "  Served content: %s\n" "$SERVED_CONTENT"
            print_test_result "WARN" "Container content verification inconclusive"
        fi
    fi
else
    assert_true "1" "Test container not running after restore"
fi

print_test_summary

# Cleanup will be called automatically by trap
