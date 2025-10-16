#!/bin/bash
# Test: Stack States Capture in Backup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test Stack States Capture"

# Load configuration
DEFAULT_CONFIG="/etc/docker-backup-manager.conf"
if [[ ! -f "$DEFAULT_CONFIG" ]]; then
    skip_test "Config file not found"
fi

source "$DEFAULT_CONFIG"

# Test 1: Find latest backup
printf "\n${CYAN}Finding latest backup:${NC}\n"

LATEST_BACKUP=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | sort -r | head -1)

if [[ -z "$LATEST_BACKUP" ]]; then
    skip_test "No backup files found - create a backup first"
fi

printf "  Latest: %s\n" "$(basename "$LATEST_BACKUP")"
assert_file_exists "$LATEST_BACKUP" "Backup file exists"

# Test 2: Check if stack_states.json is in the backup
printf "\n${CYAN}Checking for stack_states.json in backup:${NC}\n"

if tar -tzf "$LATEST_BACKUP" stack_states.json >/dev/null 2>&1; then
    assert_true "0" "stack_states.json found in backup archive"
else
    assert_true "1" "stack_states.json should be in backup archive"
    print_test_summary
    exit 1
fi

# Test 3: Extract and validate stack_states.json
printf "\n${CYAN}Extracting and validating stack_states.json:${NC}\n"

TEMP_DIR=$(mktemp -d)
tar -xzf "$LATEST_BACKUP" -C "$TEMP_DIR" stack_states.json 2>/dev/null

if [[ -f "$TEMP_DIR/stack_states.json" ]]; then
    assert_file_exists "$TEMP_DIR/stack_states.json" "stack_states.json extracted successfully"
else
    assert_true "1" "Failed to extract stack_states.json"
    rm -rf "$TEMP_DIR"
    print_test_summary
    exit 1
fi

# Test 4: Validate JSON structure
printf "\n${CYAN}Validating JSON structure:${NC}\n"

if jq empty "$TEMP_DIR/stack_states.json" 2>/dev/null; then
    assert_true "0" "stack_states.json is valid JSON"
else
    assert_true "1" "stack_states.json should be valid JSON"
    rm -rf "$TEMP_DIR"
    print_test_summary
    exit 1
fi

# Test 5: Check required fields
printf "\n${CYAN}Checking required fields:${NC}\n"

CAPTURE_TIMESTAMP=$(jq -r '.capture_timestamp // empty' "$TEMP_DIR/stack_states.json")
CAPTURE_VERSION=$(jq -r '.capture_version // empty' "$TEMP_DIR/stack_states.json")
TOTAL_STACKS=$(jq -r '.total_stacks // 0' "$TEMP_DIR/stack_states.json")

if [[ -n "$CAPTURE_TIMESTAMP" ]]; then
    assert_true "0" "capture_timestamp exists: $CAPTURE_TIMESTAMP"
else
    print_test_result "WARN" "capture_timestamp not found"
fi

if [[ -n "$CAPTURE_VERSION" ]]; then
    assert_true "0" "capture_version exists: $CAPTURE_VERSION"
else
    print_test_result "WARN" "capture_version not found"
fi

printf "  Total stacks captured: %s\n" "$TOTAL_STACKS"

if [[ "$TOTAL_STACKS" =~ ^[0-9]+$ ]] && [[ $TOTAL_STACKS -gt 0 ]]; then
    assert_true "0" "At least one stack was captured"
else
    print_test_result "WARN" "No stacks found in backup (this may be expected if no stacks are deployed)"
fi

# Test 6: Verify stack details are captured
printf "\n${CYAN}Checking stack details:${NC}\n"

if [[ $TOTAL_STACKS -gt 0 ]]; then
    # Check first stack has required fields
    FIRST_STACK_NAME=$(jq -r '.stacks[0].name // empty' "$TEMP_DIR/stack_states.json")
    FIRST_STACK_ID=$(jq -r '.stacks[0].id // empty' "$TEMP_DIR/stack_states.json")
    FIRST_STACK_STATUS=$(jq -r '.stacks[0].status // empty' "$TEMP_DIR/stack_states.json")
    FIRST_STACK_COMPOSE=$(jq -r '.stacks[0].compose_file_content // empty' "$TEMP_DIR/stack_states.json")

    if [[ -n "$FIRST_STACK_NAME" ]]; then
        printf "  Stack name: %s\n" "$FIRST_STACK_NAME"
        assert_true "0" "Stack has name field"
    else
        print_test_result "WARN" "Stack missing name field"
    fi

    if [[ -n "$FIRST_STACK_ID" ]]; then
        printf "  Stack ID: %s\n" "$FIRST_STACK_ID"
        assert_true "0" "Stack has id field"
    else
        print_test_result "WARN" "Stack missing id field"
    fi

    if [[ -n "$FIRST_STACK_STATUS" ]]; then
        printf "  Stack status: %s\n" "$FIRST_STACK_STATUS"
        assert_true "0" "Stack has status field"
    else
        print_test_result "WARN" "Stack missing status field"
    fi

    if [[ -n "$FIRST_STACK_COMPOSE" ]]; then
        printf "  Compose file captured: Yes (%d bytes)\n" "${#FIRST_STACK_COMPOSE}"
        assert_true "0" "Stack has compose_file_content"
    else
        assert_true "1" "Stack should have compose_file_content"
    fi
fi

# Test 7: List all captured stacks
printf "\n${CYAN}Captured stacks summary:${NC}\n"

jq -r '.stacks[] | "  - \(.name) (ID: \(.id), Status: \(.status))"' "$TEMP_DIR/stack_states.json" 2>/dev/null | head -10

# Cleanup
rm -rf "$TEMP_DIR"

print_test_summary
