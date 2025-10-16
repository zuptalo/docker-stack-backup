#!/bin/bash
# Test: Check Backup Metadata

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Backup Metadata"

# Load configuration
DEFAULT_CONFIG="/etc/docker-backup-manager.conf"
if [[ ! -f "$DEFAULT_CONFIG" ]]; then
    print_test_result "SKIP" "Config file not found"
    print_test_summary
    exit 0
fi

source "$DEFAULT_CONFIG"

# Test 1: Find latest backup
printf "\n${CYAN}Finding latest backup:${NC}\n"

LATEST_BACKUP=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | sort -r | head -1)

if [[ -z "$LATEST_BACKUP" ]]; then
    print_test_result "SKIP" "No backup files found"
    print_test_summary
    exit 0
fi

printf "  Latest: %s\n" "$(basename "$LATEST_BACKUP")"

# Test 2: Check if metadata file exists
METADATA_FILE="${LATEST_BACKUP%.tar.gz}.metadata"

printf "\n${CYAN}Checking metadata file:${NC}\n"
printf "  Expected: %s\n" "$(basename "$METADATA_FILE")"

if [[ -f "$METADATA_FILE" ]]; then
    assert_file_exists "$METADATA_FILE" "Metadata file exists"
else
    print_test_result "WARN" "Metadata file not found (older backup format?)"
    print_test_summary
    exit 0
fi

# Test 3: Validate metadata file is valid JSON
printf "\n${CYAN}Validating metadata JSON:${NC}\n"

if jq empty "$METADATA_FILE" 2>/dev/null; then
    assert_true "0" "Metadata file contains valid JSON"
else
    assert_true "1" "Metadata file should contain valid JSON"
    print_test_summary
    exit 1
fi

# Test 4: Check required metadata fields
printf "\n${CYAN}Checking required fields:${NC}\n"

REQUIRED_FIELDS=("timestamp" "hostname" "backup_path" "portainer_path" "npm_path")

for field in "${REQUIRED_FIELDS[@]}"; do
    VALUE=$(jq -r ".$field // empty" "$METADATA_FILE" 2>/dev/null)

    if [[ -n "$VALUE" ]]; then
        assert_true "0" "Field '$field' exists: $VALUE"
    else
        print_test_result "WARN" "Field '$field' not found in metadata"
    fi
done

# Test 5: Validate backup metadata values
printf "\n${CYAN}Metadata values:${NC}\n"

TIMESTAMP=$(jq -r '.timestamp // "unknown"' "$METADATA_FILE" 2>/dev/null)
HOSTNAME=$(jq -r '.hostname // "unknown"' "$METADATA_FILE" 2>/dev/null)
BACKUP_SIZE=$(jq -r '.backup_size // "unknown"' "$METADATA_FILE" 2>/dev/null)

printf "  Timestamp: %s\n" "$TIMESTAMP"
printf "  Hostname: %s\n" "$HOSTNAME"
printf "  Backup Size: %s\n" "$BACKUP_SIZE"

# Validate timestamp format (should be YYYY-MM-DD HH:MM:SS)
if [[ "$TIMESTAMP" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    assert_true "0" "Timestamp has valid format"
else
    print_test_result "WARN" "Timestamp format may be non-standard"
fi

# Test 6: Check for stack information
printf "\n${CYAN}Checking stack information:${NC}\n"

STACKS=$(jq -r '.stacks // [] | length' "$METADATA_FILE" 2>/dev/null)

if [[ "$STACKS" =~ ^[0-9]+$ ]]; then
    printf "  Stacks captured: %s\n" "$STACKS"
    assert_true "0" "Stack count is numeric"

    if [[ $STACKS -gt 0 ]]; then
        # List stack names
        jq -r '.stacks[]?.Name // .stacks[]?.name // empty' "$METADATA_FILE" 2>/dev/null | head -5 | while read stack_name; do
            printf "    - %s\n" "$stack_name"
        done
    fi
else
    print_test_result "INFO" "No stack information in metadata (older format?)"
fi

# Test 7: Display full metadata structure
printf "\n${CYAN}Metadata structure:${NC}\n"
jq '.' "$METADATA_FILE" 2>/dev/null | head -20 | while read line; do
    printf "  %s\n" "$line"
done

print_test_summary
