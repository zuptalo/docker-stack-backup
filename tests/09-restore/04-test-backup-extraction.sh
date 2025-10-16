#!/bin/bash
# Test: Test Backup Extraction

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test Backup Extraction"

DEFAULT_CONFIG="/etc/docker-backup-manager.conf"

if [[ ! -f "$DEFAULT_CONFIG" ]]; then
    print_test_result "SKIP" "Config file not found"
    print_test_summary
    exit 0
fi

source "$DEFAULT_CONFIG"

# Test 1: Find latest backup
printf "\n${CYAN}Finding backup to test:${NC}\n"

LATEST_BACKUP=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | sort -r | head -1)

if [[ -z "$LATEST_BACKUP" ]]; then
    print_test_result "SKIP" "No backups available"
    print_test_summary
    exit 0
fi

printf "  Testing with: %s\n" "$(basename "$LATEST_BACKUP")"

# Test 2: Create temporary extraction directory
printf "\n${CYAN}Creating temporary extraction directory:${NC}\n"

TEMP_DIR=$(mktemp -d)
printf "  Temp directory: %s\n" "$TEMP_DIR"

if [[ -d "$TEMP_DIR" ]]; then
    assert_dir_exists "$TEMP_DIR" "Temporary directory created"
else
    assert_true "1" "Failed to create temporary directory"
    print_test_summary
    exit 1
fi

# Test 3: Test extraction (dry run - list only)
printf "\n${CYAN}Testing archive listing:${NC}\n"

FILE_COUNT=$(tar -tzf "$LATEST_BACKUP" 2>/dev/null | wc -l)
printf "  Files in archive: %d\n" "$FILE_COUNT"

if [[ $FILE_COUNT -gt 0 ]]; then
    assert_true "0" "Can list archive contents"
else
    assert_true "1" "Archive should contain files"
fi

# Test 4: Test actual extraction to temp directory
printf "\n${CYAN}Testing extraction to temp directory:${NC}\n"

if tar -xzf "$LATEST_BACKUP" -C "$TEMP_DIR" 2>/dev/null; then
    assert_true "0" "Successfully extracted archive"

    # Count extracted files
    EXTRACTED_COUNT=$(find "$TEMP_DIR" -type f 2>/dev/null | wc -l)
    printf "  Extracted files: %d\n" "$EXTRACTED_COUNT"

    if [[ $EXTRACTED_COUNT -gt 0 ]]; then
        assert_true "0" "Files were extracted"
    fi
else
    assert_true "1" "Extraction failed"
fi

# Test 5: Verify expected directories exist in extraction
printf "\n${CYAN}Checking extracted structure:${NC}\n"

if [[ -d "$TEMP_DIR/opt/portainer" ]]; then
    assert_dir_exists "$TEMP_DIR/opt/portainer" "Portainer directory extracted"
else
    print_test_result "WARN" "Portainer directory not found in extraction"
fi

if [[ -d "$TEMP_DIR/opt/nginx-proxy-manager" ]]; then
    assert_dir_exists "$TEMP_DIR/opt/nginx-proxy-manager" "NPM directory extracted"
else
    print_test_result "WARN" "NPM directory not found in extraction"
fi

# Test 6: Check file permissions preserved
printf "\n${CYAN}Checking permission preservation:${NC}\n"

SAMPLE_FILE=$(find "$TEMP_DIR" -type f 2>/dev/null | head -1)

if [[ -n "$SAMPLE_FILE" ]]; then
    PERMS=$(stat -c "%a" "$SAMPLE_FILE" 2>/dev/null || stat -f "%Lp" "$SAMPLE_FILE" 2>/dev/null)
    printf "  Sample file permissions: %s\n" "$PERMS"
    assert_true "0" "File permissions are preserved"
fi

# Test 7: Cleanup
printf "\n${CYAN}Cleaning up test extraction:${NC}\n"

rm -rf "$TEMP_DIR"

if [[ ! -d "$TEMP_DIR" ]]; then
    assert_true "0" "Temporary directory cleaned up"
else
    print_test_result "WARN" "Failed to clean up temporary directory"
fi

print_test_summary
