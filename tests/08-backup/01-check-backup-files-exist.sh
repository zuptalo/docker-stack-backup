#!/bin/bash
# Test: Check Backup Files Exist

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Backup Files Exist"

# Load configuration
DEFAULT_CONFIG="/etc/docker-backup-manager.conf"
if [[ ! -f "$DEFAULT_CONFIG" ]]; then
    print_test_result "SKIP" "Config file not found"
    print_test_summary
    exit 0
fi

source "$DEFAULT_CONFIG"

# Test 1: Check if backup directory exists
printf "\n${CYAN}Checking backup directory:${NC}\n"

if [[ -d "$BACKUP_PATH" ]]; then
    assert_dir_exists "$BACKUP_PATH" "Backup directory exists"
    printf "  Path: %s\n" "$BACKUP_PATH"
else
    print_test_result "SKIP" "Backup directory doesn't exist yet"
    print_test_summary
    exit 0
fi

# Test 2: Check for backup files
printf "\n${CYAN}Checking for backup files:${NC}\n"

BACKUP_COUNT=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | wc -l)
printf "  Backup files found: %d\n" "$BACKUP_COUNT"

if [[ $BACKUP_COUNT -gt 0 ]]; then
    assert_true "0" "At least one backup file exists"
else
    print_test_result "WARN" "No backup files found (expected if backup hasn't run yet)"
    print_test_summary
    exit 0
fi

# Test 3: Check backup file naming convention
printf "\n${CYAN}Validating backup file names:${NC}\n"

INVALID_NAMES=0
find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | while read backup_file; do
    filename=$(basename "$backup_file")

    # Check format: docker_backup_YYYYMMDD_HHMMSS.tar.gz
    if [[ "$filename" =~ ^docker_backup_[0-9]{8}_[0-9]{6}\.tar\.gz$ ]]; then
        printf "  ✓ %s (valid format)\n" "$filename"
    else
        printf "  ✗ %s (invalid format)\n" "$filename"
        INVALID_NAMES=$((INVALID_NAMES + 1))
    fi
done

if [[ $INVALID_NAMES -eq 0 ]]; then
    assert_equals "0" "$INVALID_NAMES" "All backup files have valid naming"
else
    assert_equals "0" "$INVALID_NAMES" "Found $INVALID_NAMES invalid backup file names"
fi

# Test 4: Check backup file ownership
printf "\n${CYAN}Checking backup file ownership:${NC}\n"

PORTAINER_USER="${PORTAINER_USER:-portainer}"
WRONG_OWNER=0

find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | head -3 | while read backup_file; do
    filename=$(basename "$backup_file")
    owner=$(stat -c "%U" "$backup_file" 2>/dev/null || stat -f "%Su" "$backup_file" 2>/dev/null)

    printf "  %s: owner=%s\n" "$filename" "$owner"

    if [[ "$owner" != "$PORTAINER_USER" ]]; then
        WRONG_OWNER=$((WRONG_OWNER + 1))
    fi
done

# Test 5: Check backup file permissions
printf "\n${CYAN}Checking backup file permissions:${NC}\n"

find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | head -1 | while read backup_file; do
    perms=$(stat -c "%a" "$backup_file" 2>/dev/null || stat -f "%Lp" "$backup_file" 2>/dev/null)
    printf "  Permissions: %s\n" "$perms"

    # Should be readable by owner (at minimum 400)
    if [[ "$perms" =~ ^[4567] ]]; then
        printf "  ✓ Backup file is readable\n"
    else
        printf "  ✗ Backup file permissions may be incorrect\n"
    fi
done

# Test 6: Check most recent backup size
printf "\n${CYAN}Checking backup file sizes:${NC}\n"

LATEST_BACKUP=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | sort -r | head -1)

if [[ -n "$LATEST_BACKUP" ]]; then
    SIZE=$(du -h "$LATEST_BACKUP" | cut -f1)
    SIZE_BYTES=$(stat -c "%s" "$LATEST_BACKUP" 2>/dev/null || stat -f "%z" "$LATEST_BACKUP" 2>/dev/null)

    printf "  Latest backup: %s\n" "$(basename "$LATEST_BACKUP")"
    printf "  Size: %s (%s bytes)\n" "$SIZE" "$SIZE_BYTES"

    # Backup should be at least 1KB (not empty)
    if [[ $SIZE_BYTES -gt 1024 ]]; then
        assert_true "0" "Backup file has reasonable size (> 1KB)"
    else
        assert_true "1" "Backup file seems too small: $SIZE_BYTES bytes"
    fi
fi

# Test 7: List recent backups
printf "\n${CYAN}Recent backups:${NC}\n"

find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | sort -r | head -5 | while read backup_file; do
    filename=$(basename "$backup_file")
    size=$(du -h "$backup_file" | cut -f1)
    date=$(echo "$filename" | grep -oP '\d{8}_\d{6}' | sed 's/_/ /')
    printf "  - %s (%s)\n" "$filename" "$size"
done

print_test_summary
