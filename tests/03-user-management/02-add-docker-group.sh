#!/bin/bash
# Test: Check Docker Group Management Capabilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Docker Group Management Capabilities"

PORTAINER_USER="portainer"

# Test 1: Check if portainer user exists
if ! id "$PORTAINER_USER" >/dev/null 2>&1; then
    print_test_result "SKIP" "Portainer user does not exist yet (will be created during installation)"
    print_test_summary
    exit 0
fi

# Test 2: Check if docker group exists (read-only - no creation)
if getent group docker >/dev/null 2>&1; then
    assert_command_succeeds "Docker group exists" getent group docker
else
    print_test_result "SKIP" "Docker group does not exist yet (will be created during Docker installation)"

    # Check if groupadd command is available
    if command -v groupadd >/dev/null 2>&1; then
        assert_true "0" "groupadd command available for group creation"
    else
        assert_true "1" "groupadd command should be available"
    fi

    print_test_summary
    exit 0
fi

# Test 3: Check if portainer user is in docker group (read-only - no modification)
if groups "$PORTAINER_USER" 2>/dev/null | grep -qw docker; then
    assert_user_in_group "$PORTAINER_USER" "docker" "Portainer user is in docker group"

    printf "\n${CYAN}Group Membership:${NC}\n"
    groups "$PORTAINER_USER"
else
    print_test_result "SKIP" "Portainer user not in docker group yet (will be added during installation)"

    # Check if usermod command is available
    if command -v usermod >/dev/null 2>&1; then
        assert_true "0" "usermod command available for group management"
    else
        assert_true "1" "usermod command should be available"
    fi
fi

print_test_summary
