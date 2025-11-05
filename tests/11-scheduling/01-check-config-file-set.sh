#!/bin/bash
# Test: Check CONFIG_FILE is properly set and working

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check CONFIG_FILE is Properly Set and Working"

# Test 1: Verify CONFIG_FILE is hardcoded correctly
printf "\n${CYAN}Testing hardcoded CONFIG_FILE value:${NC}\n"

EXPECTED_CONFIG="/etc/docker-backup-manager.conf"
# Check if config file exists after installation
if [[ -f "$EXPECTED_CONFIG" ]]; then
    assert_true "0" "Config file exists at expected location: $EXPECTED_CONFIG"

    # Verify it's readable
    if sudo cat "$EXPECTED_CONFIG" >/dev/null 2>&1; then
        assert_true "0" "Config file is readable"
    else
        assert_true "1" "Config file should be readable"
    fi
else
    print_test_result "SKIP" "Config file doesn't exist yet - skipping test"
fi

# Test 2: Verify schedule command doesn't fail with tee error
# This tests the bug fix where CONFIG_FILE was empty causing "tee: '': No such file"
if command -v timeout >/dev/null 2>&1; then
    printf "\n${CYAN}Testing schedule command doesn't produce tee errors:${NC}\n"

    # Run schedule command with option 7 (remove schedules) in non-interactive mode
    # This should complete without "tee: '': No such file or directory" error
    TEST_OUTPUT=$(echo "7" | timeout 10s sudo ./backup-manager.sh schedule 2>&1 || true)

    if echo "$TEST_OUTPUT" | grep -q "tee:.*No such file"; then
        assert_true "1" "schedule command should not produce tee errors"
        printf "  Error output: %s\n" "$TEST_OUTPUT"
    else
        assert_true "0" "schedule command runs without tee errors"
    fi
else
    print_test_result "SKIP" "timeout command not available - skipping schedule test"
fi

# Test 3: Verify config file can be updated in test mode
if [[ -f "/etc/docker-backup-manager.conf" ]]; then
    printf "\n${CYAN}Testing config file update in schedule test mode:${NC}\n"

    # Check if we can read the config file
    if sudo cat /etc/docker-backup-manager.conf >/dev/null 2>&1; then
        assert_true "0" "Config file is readable"

        # Verify it has proper permissions for writing
        CONFIG_PERMS=$(stat -c "%a" /etc/docker-backup-manager.conf 2>/dev/null || stat -f "%Lp" /etc/docker-backup-manager.conf 2>/dev/null || echo "unknown")
        printf "  Config file permissions: %s\n" "$CONFIG_PERMS"

        # Test that we can update the config with sudo
        if echo 'TEST_RETENTION="2"' | sudo tee -a /etc/docker-backup-manager.conf.test >/dev/null 2>&1; then
            sudo rm -f /etc/docker-backup-manager.conf.test
            assert_true "0" "Can write to config directory with sudo"
        else
            assert_true "1" "Should be able to write to config directory"
        fi
    else
        assert_true "1" "Config file should be readable"
    fi
else
    print_test_result "SKIP" "Config file doesn't exist - skipping update test"
fi

printf "\n${CYAN}Test Summary:${NC}\n"
printf "  This test verifies that CONFIG_FILE is hardcoded and working correctly\n"
printf "  CONFIG_FILE is now set to: /etc/docker-backup-manager.conf (by convention)\n"
printf "  \n"
printf "  Tests:\n"
printf "  1. Config file exists at expected location\n"
printf "  2. Schedule command works without tee errors\n"
printf "  3. Config file can be updated with sudo\n"

print_test_summary
