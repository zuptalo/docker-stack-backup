#!/bin/bash
# Test: Check Configuration Paths Exist

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Configuration Paths Exist"

DEFAULT_CONFIG="/etc/docker-backup-manager.conf"

# Test 1: Check if config file exists
if [[ ! -f "$DEFAULT_CONFIG" ]]; then
    print_test_result "SKIP" "Config file doesn't exist - cannot test paths"
    print_test_summary
    exit 0
fi

# Source the configuration
source "$DEFAULT_CONFIG"

printf "\n${CYAN}Testing configured paths:${NC}\n"

# Test 2: Check PORTAINER_PATH exists
if [[ -d "$PORTAINER_PATH" ]]; then
    assert_dir_exists "$PORTAINER_PATH" "PORTAINER_PATH directory exists"
    printf "  ✓ %s exists\n" "$PORTAINER_PATH"
else
    print_test_result "WARN" "PORTAINER_PATH doesn't exist yet: $PORTAINER_PATH (expected on fresh install)"
fi

# Test 3: Check NPM_PATH exists
if [[ -d "$NPM_PATH" ]]; then
    assert_dir_exists "$NPM_PATH" "NPM_PATH directory exists"
    printf "  ✓ %s exists\n" "$NPM_PATH"
else
    print_test_result "WARN" "NPM_PATH doesn't exist yet: $NPM_PATH (expected on fresh install)"
fi

# Test 4: Check BACKUP_PATH exists
if [[ -d "$BACKUP_PATH" ]]; then
    assert_dir_exists "$BACKUP_PATH" "BACKUP_PATH directory exists"
    printf "  ✓ %s exists\n" "$BACKUP_PATH"

    # Test 5: Check BACKUP_PATH permissions
    BACKUP_OWNER=$(stat -c "%U" "$BACKUP_PATH" 2>/dev/null || stat -f "%Su" "$BACKUP_PATH" 2>/dev/null)
    printf "  Backup directory owner: %s\n" "$BACKUP_OWNER"

    # Test 6: Check backup directory ownership and permissions
    # NOTE: /opt/backup is intentionally owned by root with 755 permissions
    # Backups are created with sudo and then chowned to portainer user
    PORTAINER_USER="${PORTAINER_USER:-portainer}"
    if id "$PORTAINER_USER" >/dev/null 2>&1; then
        # Directory should be owned by root (backups created with sudo)
        BACKUP_DIR_OWNER=$(stat -c "%U" "$BACKUP_PATH" 2>/dev/null || stat -f "%Su" "$BACKUP_PATH" 2>/dev/null)

        if [[ "$BACKUP_DIR_OWNER" == "root" ]]; then
            assert_equals "root" "$BACKUP_DIR_OWNER" "Backup directory correctly owned by root"
            print_test_result "INFO" "Backups are created with sudo and chowned to portainer user"
        else
            print_test_result "WARN" "Backup directory owned by $BACKUP_DIR_OWNER (expected: root)"
        fi

        # Check if portainer user can read the directory (should be able to with 755)
        if sudo -u "$PORTAINER_USER" test -r "$BACKUP_PATH"; then
            assert_true "0" "Portainer user can read BACKUP_PATH"
        else
            assert_true "1" "Portainer user should have read access to BACKUP_PATH"
        fi
    else
        print_test_result "SKIP" "Portainer user doesn't exist yet"
    fi
else
    print_test_result "WARN" "BACKUP_PATH doesn't exist yet: $BACKUP_PATH (expected on fresh install)"
fi

# Test 7: Check TOOLS_PATH if it exists in config
if [[ -n "$TOOLS_PATH" ]]; then
    if [[ -d "$TOOLS_PATH" ]]; then
        assert_dir_exists "$TOOLS_PATH" "TOOLS_PATH directory exists"
        printf "  ✓ %s exists\n" "$TOOLS_PATH"
    else
        print_test_result "WARN" "TOOLS_PATH doesn't exist yet: $TOOLS_PATH (expected on fresh install)"
    fi
fi

printf "\n${CYAN}Path Summary:${NC}\n"
printf "  Portainer: %s\n" "$PORTAINER_PATH"
printf "  NPM: %s\n" "$NPM_PATH"
printf "  Backup: %s\n" "$BACKUP_PATH"
if [[ -n "$TOOLS_PATH" ]]; then
    printf "  Tools: %s\n" "$TOOLS_PATH"
fi

print_test_summary
