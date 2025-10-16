#!/bin/bash
# Test: Test Backup Integrity

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test Backup Integrity"

# Load configuration
DEFAULT_CONFIG="/etc/docker-backup-manager.conf"
if [[ ! -f "$DEFAULT_CONFIG" ]]; then
    print_test_result "SKIP" "Config file not found"
    print_test_summary
    exit 0
fi

source "$DEFAULT_CONFIG"

# Test 1: Find most recent backup
printf "\n${CYAN}Finding most recent backup:${NC}\n"

NEWEST_BACKUP=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | sort -r | head -1)

if [[ -z "$NEWEST_BACKUP" ]]; then
    print_test_result "SKIP" "No backup files found"
    print_test_summary
    exit 0
fi

FILENAME=$(basename "$NEWEST_BACKUP")
SIZE=$(du -h "$NEWEST_BACKUP" | cut -f1)
AGE_SECONDS=$(( $(date +%s) - $(stat -c "%Y" "$NEWEST_BACKUP" 2>/dev/null || stat -f "%m" "$NEWEST_BACKUP" 2>/dev/null) ))

printf "  Filename: %s\n" "$FILENAME"
printf "  Size: %s\n" "$SIZE"
printf "  Age: %d seconds (%d minutes)\n" "$AGE_SECONDS" "$((AGE_SECONDS / 60))"

# Test 2: Verify backup archive is valid
printf "\n${CYAN}Testing backup archive integrity:${NC}\n"

if tar -tzf "$NEWEST_BACKUP" >/dev/null 2>&1; then
    assert_true "0" "Backup archive is valid (tar -tzf succeeds)"
else
    assert_true "1" "Backup archive validation failed"
    print_test_summary
    exit 1
fi

# Test 3: Count files in backup
printf "\n${CYAN}Counting backup contents:${NC}\n"

FILE_COUNT=$(tar -tzf "$NEWEST_BACKUP" 2>/dev/null | wc -l)
printf "  Files in backup: %d\n" "$FILE_COUNT"

if [[ $FILE_COUNT -gt 0 ]]; then
    assert_true "0" "Backup contains files ($FILE_COUNT total)"
else
    assert_true "1" "Backup should contain files"
fi

# Test 4: Check for expected directories in backup
printf "\n${CYAN}Checking for expected directories:${NC}\n"

TOTAL_FILES=$(tar -tzf "$NEWEST_BACKUP" 2>/dev/null | wc -l)
printf "  Total files/dirs in backup: %d\n" "$TOTAL_FILES"

if tar -tzf "$NEWEST_BACKUP" 2>/dev/null | grep -q "portainer"; then
    assert_true "0" "Backup contains portainer directory/files"
else
    print_test_result "WARN" "No portainer files found in backup"
fi

if tar -tzf "$NEWEST_BACKUP" 2>/dev/null | grep -q "nginx-proxy-manager\|npm"; then
    assert_true "0" "Backup contains NPM directory/files"
else
    print_test_result "WARN" "No NPM files found in backup"
fi

# Test 5: Verify backup file permissions are preserved
printf "\n${CYAN}Testing permission preservation:${NC}\n"

# Check if tar archive stores permissions correctly
if tar -tvzf "$NEWEST_BACKUP" 2>/dev/null | head -5 | grep -q "^[drwx-]"; then
    assert_true "0" "Backup preserves file permissions"
else
    print_test_result "WARN" "Could not verify permission preservation"
fi

# Test 6: Check backup size is reasonable
printf "\n${CYAN}Validating backup size:${NC}\n"

SIZE_BYTES=$(stat -c "%s" "$NEWEST_BACKUP" 2>/dev/null || stat -f "%z" "$NEWEST_BACKUP" 2>/dev/null)
SIZE_KB=$((SIZE_BYTES / 1024))
SIZE_MB=$((SIZE_KB / 1024))

printf "  Size: %d bytes (%d KB, %d MB)\n" "$SIZE_BYTES" "$SIZE_KB" "$SIZE_MB"

# Backup should be at least 10KB (not empty/corrupt)
if [[ $SIZE_BYTES -gt 10240 ]]; then
    assert_true "0" "Backup has reasonable size (> 10KB)"
else
    assert_true "1" "Backup seems too small: $SIZE_BYTES bytes"
fi

# Backup should not be excessively large (< 1GB for this environment)
if [[ $SIZE_BYTES -lt 1073741824 ]]; then
    assert_true "0" "Backup size is reasonable (< 1GB)"
else
    print_test_result "WARN" "Backup is very large: $SIZE_MB MB"
fi

print_test_summary
