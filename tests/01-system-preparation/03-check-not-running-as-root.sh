#!/bin/bash
# Test: Ensure NOT Running as Root

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Ensure NOT Running as Root"

# Test 1: Check if actual user (not sudo) is root
# When run with sudo, EUID is 0 but SUDO_USER tells us the real user
REAL_USER="${SUDO_USER:-${USER:-$(whoami)}}"
if [[ "$REAL_USER" != "root" ]]; then
    assert_true "0" "Not running as root user (actual user: $REAL_USER)"
elif [[ $EUID -ne 0 ]]; then
    assert_true "0" "Not running as root (EUID: $EUID)"
else
    assert_true "1" "Should NOT run as root user"
fi

# Test 2: Check username is not 'root'
REAL_USER="${SUDO_USER:-${USER:-$(whoami)}}"
if [[ "$REAL_USER" != "root" ]]; then
    assert_not_equals "root" "$REAL_USER" "Username is not root"
else
    assert_not_equals "root" "$REAL_USER" "Should not run as root user"
fi

# Test 3: Check real user's HOME is not /root
REAL_USER_HOME=$(eval echo ~$REAL_USER)
if [[ "$REAL_USER_HOME" != "/root" ]]; then
    assert_not_equals "/root" "$REAL_USER_HOME" "Real user HOME is not /root"
else
    assert_not_equals "/root" "$REAL_USER_HOME" "Real user HOME should not be /root"
fi

printf "\n${CYAN}Current User Context:${NC}\n"
printf "  Real User: %s\n" "$REAL_USER"
printf "  Effective UID: %s\n" "$(id -u)"
printf "  Real User HOME: %s\n" "$(eval echo ~$REAL_USER)"

print_test_summary
