#!/bin/bash
# Test: Test List Backups Functionality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test List Backups Functionality"

SCRIPT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_CONFIG="/etc/docker-backup-manager.conf"

# Test 1: Check config exists
if [[ ! -f "$DEFAULT_CONFIG" ]]; then
    print_test_result "SKIP" "Config file not found"
    print_test_summary
    exit 0
fi

source "$DEFAULT_CONFIG"

# Test 2: Check backup directory
printf "\n${CYAN}Checking backup directory:${NC}\n"

if [[ ! -d "$BACKUP_PATH" ]]; then
    print_test_result "SKIP" "Backup directory doesn't exist"
    print_test_summary
    exit 0
fi

# Test 3: List backup files directly
printf "\n${CYAN}Listing backup files:${NC}\n"

BACKUPS=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | sort -r)
BACKUP_COUNT=$(echo "$BACKUPS" | grep -c "docker_backup" || echo "0")

printf "  Total backups: %d\n" "$BACKUP_COUNT"

if [[ $BACKUP_COUNT -eq 0 ]]; then
    print_test_result "SKIP" "No backup files available"
    print_test_summary
    exit 0
fi

assert_true "0" "Found $BACKUP_COUNT backup file(s)"

# Test 4: Display backup information
printf "\n${CYAN}Backup details:${NC}\n"

echo "$BACKUPS" | head -5 | while IFS= read -r backup; do
    if [[ -n "$backup" ]]; then
        FILENAME=$(basename "$backup")
        SIZE=$(du -h "$backup" 2>/dev/null | cut -f1)
        DATE=$(echo "$FILENAME" | grep -oP '\d{8}' || echo "unknown")
        TIME=$(echo "$FILENAME" | grep -oP '\d{6}' || echo "unknown")

        printf "  - %s\n" "$FILENAME"
        printf "    Size: %s\n" "$SIZE"
        printf "    Date: %s %s\n" "$DATE" "$TIME"
    fi
done

# Test 5: Check backup file integrity
printf "\n${CYAN}Checking backup integrity:${NC}\n"

LATEST_BACKUP=$(echo "$BACKUPS" | head -1)

if [[ -n "$LATEST_BACKUP" ]] && [[ -f "$LATEST_BACKUP" ]]; then
    if tar -tzf "$LATEST_BACKUP" >/dev/null 2>&1; then
        assert_true "0" "Latest backup is a valid tar archive"
    else
        assert_true "1" "Latest backup archive is invalid"
    fi
fi

# Test 6: Check for metadata files
printf "\n${CYAN}Checking for metadata files:${NC}\n"

METADATA_COUNT=0
echo "$BACKUPS" | head -3 | while IFS= read -r backup; do
    if [[ -n "$backup" ]]; then
        METADATA="${backup%.tar.gz}.metadata"
        if [[ -f "$METADATA" ]]; then
            ((METADATA_COUNT++))
            printf "  ✓ %s has metadata\n" "$(basename "$backup")"
        fi
    fi
done

if [[ $METADATA_COUNT -gt 0 ]]; then
    assert_true "0" "Backups have metadata files"
else
    print_test_result "INFO" "No metadata files found (older backup format?)"
fi

print_test_summary
