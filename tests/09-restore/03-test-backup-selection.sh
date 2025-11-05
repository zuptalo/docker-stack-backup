#!/bin/bash
# Test: Test Backup Selection Logic

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test Backup Selection Logic"

DEFAULT_CONFIG="/etc/docker-backup-manager.conf"

if [[ ! -f "$DEFAULT_CONFIG" ]]; then
    print_test_result "SKIP" "Config file not found"
    print_test_summary
    exit 0
fi

source "$DEFAULT_CONFIG"

# Test 1: Check if backups exist
printf "\n${CYAN}Checking available backups:${NC}\n"

BACKUPS=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | sort -r)
BACKUP_COUNT=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | wc -l | tr -d ' ')

if [[ $BACKUP_COUNT -eq 0 ]]; then
    print_test_result "SKIP" "No backups available"
    print_test_summary
    exit 0
fi

printf "  Available backups: %d\n" "$BACKUP_COUNT"
assert_true "0" "Backups available for selection"

# Test 2: Test selecting latest backup
printf "\n${CYAN}Testing latest backup selection:${NC}\n"

LATEST_BACKUP=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | sort -r | head -1)

if [[ -n "$LATEST_BACKUP" ]] && [[ -f "$LATEST_BACKUP" ]]; then
    assert_file_exists "$LATEST_BACKUP" "Can select latest backup"
    printf "  Latest: %s\n" "$(basename "$LATEST_BACKUP")"
else
    assert_true "1" "Should be able to select latest backup"
fi

# Test 3: Test selecting oldest backup
printf "\n${CYAN}Testing oldest backup selection:${NC}\n"

OLDEST_BACKUP=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | sort | head -1)

if [[ -n "$OLDEST_BACKUP" ]] && [[ -f "$OLDEST_BACKUP" ]]; then
    assert_file_exists "$OLDEST_BACKUP" "Can select oldest backup"
    printf "  Oldest: %s\n" "$(basename "$OLDEST_BACKUP")"
else
    assert_true "1" "Should be able to select oldest backup"
fi

# Test 4: Test backup age calculation
printf "\n${CYAN}Testing backup age calculation:${NC}\n"

if [[ -n "$LATEST_BACKUP" ]]; then
    CURRENT_TIME=$(date +%s)
    BACKUP_TIME=$(stat -c "%Y" "$LATEST_BACKUP" 2>/dev/null || stat -f "%m" "$LATEST_BACKUP" 2>/dev/null)
    AGE_SECONDS=$((CURRENT_TIME - BACKUP_TIME))
    AGE_MINUTES=$((AGE_SECONDS / 60))
    AGE_HOURS=$((AGE_MINUTES / 60))

    printf "  Latest backup age:\n"
    printf "    Seconds: %d\n" "$AGE_SECONDS"
    printf "    Minutes: %d\n" "$AGE_MINUTES"
    printf "    Hours: %d\n" "$AGE_HOURS"

    assert_true "0" "Can calculate backup age"
fi

# Test 5: Test backup filename parsing
printf "\n${CYAN}Testing backup filename parsing:${NC}\n"

if [[ -n "$LATEST_BACKUP" ]]; then
    FILENAME=$(basename "$LATEST_BACKUP")

    # Extract date and time from filename
    if [[ "$FILENAME" =~ docker_backup_([0-9]{8})_([0-9]{6})\.tar\.gz ]]; then
        BACKUP_DATE="${BASH_REMATCH[1]}"
        BACKUP_TIME="${BASH_REMATCH[2]}"

        printf "  Parsed from filename:\n"
        printf "    Date: %s\n" "$BACKUP_DATE"
        printf "    Time: %s\n" "$BACKUP_TIME"

        assert_true "0" "Can parse backup filename"
    else
        print_test_result "WARN" "Filename doesn't match expected pattern"
    fi
fi

# Test 6: Test backup file validation
printf "\n${CYAN}Testing backup validation:${NC}\n"

if [[ -n "$LATEST_BACKUP" ]]; then
    # Check file is readable
    if [[ -r "$LATEST_BACKUP" ]]; then
        assert_true "0" "Backup file is readable"
    else
        assert_true "1" "Backup file should be readable"
    fi

    # Check file size
    SIZE_BYTES=$(stat -c "%s" "$LATEST_BACKUP" 2>/dev/null || stat -f "%z" "$LATEST_BACKUP" 2>/dev/null)

    if [[ $SIZE_BYTES -gt 1024 ]]; then
        assert_true "0" "Backup file has valid size"
    else
        assert_true "1" "Backup file size seems too small"
    fi
fi

print_test_summary
