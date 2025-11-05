#!/bin/bash
# Test: Check Sudo Configuration Capabilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Sudo Configuration Capabilities"

PORTAINER_USER="portainer"
SUDOERS_FILE="/etc/sudoers.d/${PORTAINER_USER}"

# Test 1: Check if portainer user exists
if ! id "$PORTAINER_USER" >/dev/null 2>&1; then
    print_test_result "SKIP" "Portainer user does not exist yet (will be created during installation)"
    print_test_summary
    exit 0
fi

# Test 2: Check if sudoers.d directory exists
assert_dir_exists "/etc/sudoers.d" "Sudoers.d directory exists"

# Test 3: Check if sudoers file exists (read-only - no creation)
if [[ -f "$SUDOERS_FILE" ]]; then
    assert_file_exists "$SUDOERS_FILE" "Sudoers file exists"

    # Test 4: Verify sudoers file syntax
    if sudo visudo -c -f "$SUDOERS_FILE" >/dev/null 2>&1; then
        assert_command_succeeds "Sudoers file syntax is valid" sudo visudo -c -f "$SUDOERS_FILE"
    else
        assert_command_succeeds "Sudoers file should be valid" false
    fi

    # Test 5: Check file permissions (should be 440)
    FILE_PERMS=$(stat -c "%a" "$SUDOERS_FILE" 2>/dev/null || stat -f "%A" "$SUDOERS_FILE" 2>/dev/null)
    if [[ "$FILE_PERMS" == "440" ]] || [[ "$FILE_PERMS" == "0440" ]]; then
        assert_true "0" "Sudoers file has correct permissions: $FILE_PERMS"
    else
        print_test_result "WARN" "Sudoers file permissions: $FILE_PERMS (expected: 440)"
    fi

    printf "\n${CYAN}Sudoers Configuration:${NC}\n"
    sudo cat "$SUDOERS_FILE" 2>/dev/null || printf "  (cannot read file)\n"
else
    print_test_result "SKIP" "Sudoers file not created yet (will be created during installation)"

    # Check if required commands are available
    if command -v visudo >/dev/null 2>&1; then
        assert_true "0" "visudo command available for sudoers validation"
    else
        assert_true "1" "visudo command should be available"
    fi

    # Check if we have sudo privileges to create sudoers files
    if sudo -n true 2>/dev/null; then
        assert_true "0" "Have sudo privileges for sudoers configuration"
    else
        print_test_result "INFO" "Tests running with sudo (sudoers configuration will require sudo)"
    fi
fi

print_test_summary
