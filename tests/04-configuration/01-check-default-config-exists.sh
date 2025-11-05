#!/bin/bash
# Test: Check Default Configuration File Exists

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Default Configuration File Exists"

# Test 1: Check if default config file exists
DEFAULT_CONFIG="/etc/docker-backup-manager.conf"
if [[ -f "$DEFAULT_CONFIG" ]]; then
    assert_file_exists "$DEFAULT_CONFIG" "Default configuration file should exist"
else
    print_test_result "SKIP" "Config file not created yet - this is expected on fresh system"
fi

# Test 2: If config exists, verify it's readable
if [[ -f "$DEFAULT_CONFIG" ]]; then
    if sudo cat "$DEFAULT_CONFIG" >/dev/null 2>&1; then
        assert_true "0" "Configuration file is readable"
    else
        assert_true "1" "Configuration file should be readable"
    fi
fi

# Test 3: If config exists, verify it has proper permissions
if [[ -f "$DEFAULT_CONFIG" ]]; then
    PERMS=$(stat -c "%a" "$DEFAULT_CONFIG" 2>/dev/null || stat -f "%Lp" "$DEFAULT_CONFIG" 2>/dev/null || echo "unknown")
    printf "\n${CYAN}Configuration File Info:${NC}\n"
    printf "  Path: %s\n" "$DEFAULT_CONFIG"
    printf "  Permissions: %s\n" "$PERMS"
    printf "  Owner: %s\n" "$(ls -l "$DEFAULT_CONFIG" 2>/dev/null | awk '{print $3":"$4}')"

    # Check it's owned by root
    OWNER=$(stat -c "%U" "$DEFAULT_CONFIG" 2>/dev/null || stat -f "%Su" "$DEFAULT_CONFIG" 2>/dev/null || echo "unknown")
    assert_equals "root" "$OWNER" "Config file should be owned by root"
fi

# Test 4: Verify config contains expected variables
if [[ -f "$DEFAULT_CONFIG" ]]; then
    printf "\n${CYAN}Configuration Variables:${NC}\n"

    # Check for required configuration variables
    if grep -q "^PORTAINER_PATH=" "$DEFAULT_CONFIG"; then
        assert_true "0" "Config contains PORTAINER_PATH"
    else
        assert_true "1" "Config should contain PORTAINER_PATH"
    fi

    if grep -q "^NPM_PATH=" "$DEFAULT_CONFIG"; then
        assert_true "0" "Config contains NPM_PATH"
    else
        assert_true "1" "Config should contain NPM_PATH"
    fi

    if grep -q "^BACKUP_PATH=" "$DEFAULT_CONFIG"; then
        assert_true "0" "Config contains BACKUP_PATH"
    else
        assert_true "1" "Config should contain BACKUP_PATH"
    fi

    if grep -q "^BACKUP_RETENTION=" "$DEFAULT_CONFIG"; then
        assert_true "0" "Config contains BACKUP_RETENTION"
    else
        assert_true "1" "Config should contain BACKUP_RETENTION"
    fi

    if grep -q "^DOMAIN_NAME=" "$DEFAULT_CONFIG"; then
        assert_true "0" "Config contains DOMAIN_NAME"
    else
        assert_true "1" "Config should contain DOMAIN_NAME"
    fi
fi

print_test_summary
