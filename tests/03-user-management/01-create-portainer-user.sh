#!/bin/bash
# Test: Check Portainer User Management Capabilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Portainer User Management Capabilities"

PORTAINER_USER="portainer"

# Test 1: Check if portainer user exists (read-only - no creation)
if id "$PORTAINER_USER" >/dev/null 2>&1; then
    assert_user_exists "$PORTAINER_USER" "Portainer user exists"

    # Test 2: Verify user has home directory
    if [[ -d "/home/$PORTAINER_USER" ]] || [[ -d "$(eval echo ~$PORTAINER_USER 2>/dev/null)" ]]; then
        assert_true "0" "Portainer user has home directory"
    else
        print_test_result "WARN" "Portainer user exists but has no home directory"
    fi

    # Test 3: Check if user is a system user (UID < 1000)
    USER_UID=$(id -u "$PORTAINER_USER")
    if [[ $USER_UID -lt 1000 ]]; then
        assert_true "0" "Portainer user is a system user (UID: $USER_UID)"
    else
        print_test_result "WARN" "User UID is >= 1000 (UID: $USER_UID)"
    fi

    printf "\n${CYAN}User Information:${NC}\n"
    printf "  Username: %s\n" "$PORTAINER_USER"
    printf "  UID: %s\n" "$USER_UID"
    printf "  GID: %s\n" "$(id -g "$PORTAINER_USER")"
    printf "  Home: %s\n" "$(eval echo ~$PORTAINER_USER 2>/dev/null)"
    printf "  Shell: %s\n" "$(getent passwd "$PORTAINER_USER" | cut -d: -f7)"
else
    # User doesn't exist - just check we have permission to create users
    print_test_result "SKIP" "Portainer user not created yet (will be created during installation)"

    # Test: Check if we can create system users (requires sudo)
    if command -v useradd >/dev/null 2>&1; then
        assert_true "0" "useradd command available for user creation"
    else
        assert_true "1" "useradd command should be available"
    fi

    # Test: Check if we have sudo privileges
    if sudo -n true 2>/dev/null; then
        assert_true "0" "Have sudo privileges for user creation"
    else
        print_test_result "INFO" "Tests running with sudo (user creation will require sudo)"
    fi
fi

print_test_summary
