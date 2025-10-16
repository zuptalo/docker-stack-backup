#!/bin/bash
# Test: Check Restore Command Available

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Restore Command Available"

SCRIPT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Test 1: Check if backup-manager.sh exists
printf "\n${CYAN}Checking backup-manager.sh:${NC}\n"

if [[ -f "$SCRIPT_ROOT/backup-manager.sh" ]]; then
    assert_file_exists "$SCRIPT_ROOT/backup-manager.sh" "backup-manager.sh exists"
else
    assert_true "1" "backup-manager.sh should exist"
    print_test_summary
    exit 1
fi

# Test 2: Check if restore command is available
printf "\n${CYAN}Checking restore command:${NC}\n"

if grep -q "restore)" "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "Restore command is implemented"
else
    assert_true "1" "Restore command should be implemented"
fi

# Test 3: Check restore help text
printf "\n${CYAN}Checking restore help:${NC}\n"

HELP_OUTPUT=$(cd "$SCRIPT_ROOT" && ./backup-manager.sh restore --help 2>&1 || true)

if echo "$HELP_OUTPUT" | grep -qi "restore"; then
    assert_true "0" "Restore help is available"
else
    print_test_result "WARN" "Restore help may not be available"
fi

# Test 4: Check for restore-related functions
printf "\n${CYAN}Checking restore functions:${NC}\n"

RESTORE_FUNCTIONS=$(grep -c "^restore_" "$SCRIPT_ROOT/backup-manager.sh" 2>/dev/null || echo "0")
printf "  Restore functions found: %d\n" "$RESTORE_FUNCTIONS"

if [[ $RESTORE_FUNCTIONS -gt 0 ]]; then
    assert_true "0" "Restore functions exist"

    # List function names
    grep "^restore_" "$SCRIPT_ROOT/backup-manager.sh" | sed 's/().*//' | head -5 | while IFS= read -r func; do
        printf "    - %s\n" "$func"
    done
else
    print_test_result "WARN" "No restore functions found"
fi

# Test 5: Check if backup files exist (needed for restore)
printf "\n${CYAN}Checking for backup files:${NC}\n"

DEFAULT_CONFIG="/etc/docker-backup-manager.conf"
if [[ -f "$DEFAULT_CONFIG" ]]; then
    source "$DEFAULT_CONFIG"

    BACKUP_COUNT=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | wc -l)
    printf "  Available backups: %d\n" "$BACKUP_COUNT"

    if [[ $BACKUP_COUNT -gt 0 ]]; then
        assert_true "0" "Backup files available for restore testing"
    else
        print_test_result "WARN" "No backup files available (restore tests may skip)"
    fi
else
    print_test_result "WARN" "Config file not found"
fi

print_test_summary
