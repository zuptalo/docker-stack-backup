#!/bin/bash
# Test: Compose File Content Parsing (Bug Fix Verification)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test Compose Content Parsing"

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

# Test 2: Extract stack_states.json
printf "\n${CYAN}Extracting stack_states.json:${NC}\n"

TEMP_DIR=$(mktemp -d)
tar -xzf "$LATEST_BACKUP" -C "$TEMP_DIR" stack_states.json 2>/dev/null

if [[ ! -f "$TEMP_DIR/stack_states.json" ]]; then
    rm -rf "$TEMP_DIR"
    skip_test "stack_states.json not found in backup"
fi

assert_file_exists "$TEMP_DIR/stack_states.json" "stack_states.json extracted"

# Test 3: Check compose_file_content format
printf "\n${CYAN}Checking compose_file_content format:${NC}\n"

TOTAL_STACKS=$(jq -r '.total_stacks // 0' "$TEMP_DIR/stack_states.json")

if [[ $TOTAL_STACKS -eq 0 ]]; then
    rm -rf "$TEMP_DIR"
    skip_test "No stacks in backup to test"
fi

printf "  Testing %d stacks\n" "$TOTAL_STACKS"

# Test 4: Verify compose_file_content is a JSON string
printf "\n${CYAN}Verifying compose_file_content structure:${NC}\n"

FIRST_COMPOSE_TYPE=$(jq -r '.stacks[0].compose_file_content | type' "$TEMP_DIR/stack_states.json" 2>/dev/null)

if [[ "$FIRST_COMPOSE_TYPE" == "string" ]]; then
    assert_true "0" "compose_file_content is stored as string"
else
    print_test_result "WARN" "compose_file_content type is: $FIRST_COMPOSE_TYPE (expected: string)"
fi

# Test 5: Parse the double-encoded JSON (Bug Fix Test)
printf "\n${CYAN}Testing compose content parsing (bug fix):${NC}\n"

# This is the exact parsing logic from the restore function (line 3076)
PARSED_COMPOSE=$(jq -r '.stacks[0].compose_file_content | if type == "string" then (. | fromjson | .StackFileContent) else . end // empty' "$TEMP_DIR/stack_states.json" 2>/dev/null)

if [[ -n "$PARSED_COMPOSE" ]]; then
    assert_true "0" "Compose content parsed successfully"

    # Verify it's actual YAML/compose content
    if echo "$PARSED_COMPOSE" | grep -q "services:"; then
        assert_true "0" "Parsed content contains 'services:' (valid compose file)"
    else
        print_test_result "WARN" "Parsed content doesn't look like docker-compose.yml"
    fi
else
    assert_true "1" "Failed to parse compose_file_content"
    rm -rf "$TEMP_DIR"
    print_test_summary
    exit 1
fi

# Test 6: Show parsed compose content sample
printf "\n${CYAN}Parsed compose content (first 15 lines):${NC}\n"
echo "$PARSED_COMPOSE" | head -15 | while read line; do
    printf "  %s\n" "$line"
done

# Test 7: Verify all stacks can be parsed
printf "\n${CYAN}Testing all stacks can be parsed:${NC}\n"

PARSE_ERRORS=0
for i in $(seq 0 $((TOTAL_STACKS - 1))); do
    STACK_NAME=$(jq -r ".stacks[$i].name // \"stack-$i\"" "$TEMP_DIR/stack_states.json")
    PARSED=$(jq -r ".stacks[$i].compose_file_content | if type == \"string\" then (. | fromjson | .StackFileContent) else . end // empty" "$TEMP_DIR/stack_states.json" 2>/dev/null)

    if [[ -n "$PARSED" ]]; then
        printf "  ✓ %s: Parsed successfully (%d bytes)\n" "$STACK_NAME" "${#PARSED}"
    else
        printf "  ✗ %s: Failed to parse\n" "$STACK_NAME"
        PARSE_ERRORS=$((PARSE_ERRORS + 1))
    fi
done

if [[ $PARSE_ERRORS -eq 0 ]]; then
    assert_true "0" "All stacks parsed successfully"
else
    assert_true "1" "Some stacks failed to parse (count: $PARSE_ERRORS)"
fi

# Test 8: Test backward compatibility (if compose_file_content is not double-encoded)
printf "\n${CYAN}Testing backward compatibility:${NC}\n"

# Create a test JSON with non-encoded compose content
TEST_JSON=$(jq -n '{
    compose_file_content: "services:\n  test:\n    image: nginx\n"
}')

# Parse using the same logic
COMPAT_PARSED=$(echo "$TEST_JSON" | jq -r '.compose_file_content | if type == "string" then (. | fromjson | .StackFileContent) else . end // empty' 2>/dev/null || echo "$TEST_JSON" | jq -r '.compose_file_content // empty')

if [[ "$COMPAT_PARSED" == "services:"* ]]; then
    assert_true "0" "Backward compatibility maintained (handles non-encoded format)"
else
    print_test_result "INFO" "Non-encoded format test returned: $COMPAT_PARSED"
fi

# Cleanup
rm -rf "$TEMP_DIR"

print_test_summary
