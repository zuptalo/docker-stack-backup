#!/bin/bash
# Test: Check Sudo Privileges

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Sudo Privileges"

# Test 1: Check if user has sudo access
if sudo -n true 2>/dev/null; then
    assert_true "0" "User has sudo access (passwordless)"
elif sudo -v 2>/dev/null; then
    assert_true "0" "User has sudo access (with password)"
else
    assert_true "1" "User should have sudo access"
fi

# Test 2: Test sudo command execution
if assert_command_succeeds "sudo true" sudo true; then
    :
fi

# Test 3: Check if user is in sudo/admin group OR has sudoers file
CURRENT_USER="${SUDO_USER:-${USER:-$(whoami)}}"
if groups "$CURRENT_USER" | grep -qE 'sudo|admin|wheel'; then
    assert_true "0" "User is in sudo/admin group"
elif sudo -l -U "$CURRENT_USER" 2>/dev/null | grep -q "NOPASSWD"; then
    assert_true "0" "User has sudo access via sudoers.d (passwordless)"
elif sudo -l -U "$CURRENT_USER" 2>/dev/null | grep -q "ALL"; then
    assert_true "0" "User has sudo access via sudoers configuration"
else
    assert_true "1" "User should have sudo access"
fi

# Test 4: Display current user info
printf "\n${CYAN}User Information:${NC}\n"
printf "  Username: %s\n" "$CURRENT_USER"
printf "  UID: %s\n" "$(id -u)"
printf "  Groups: %s\n" "$(groups "$CURRENT_USER")"

print_test_summary
