#!/bin/bash
# Test: Create Portainer System User

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Create Portainer System User"

PORTAINER_USER="portainer"

# Test 1: Check if portainer user exists (or create it)
if id "$PORTAINER_USER" >/dev/null 2>&1; then
    assert_user_exists "$PORTAINER_USER" "Portainer user already exists"
else
    printf "${YELLOW}  Creating portainer user...${NC}\n"
    sudo useradd -r -m -s /bin/bash "$PORTAINER_USER" 2>/dev/null || true
    assert_user_exists "$PORTAINER_USER" "Portainer user created"
fi

# Test 2: Check if user has home directory
if [[ -d "/home/$PORTAINER_USER" ]] || [[ -d "$(eval echo ~$PORTAINER_USER)" ]]; then
    assert_true "0" "Portainer user has home directory"
else
    assert_true "1" "Portainer user should have home directory"
fi

# Test 3: Check if user is a system user (UID < 1000)
USER_UID=$(id -u "$PORTAINER_USER")
if [[ $USER_UID -lt 1000 ]]; then
    assert_true "0" "Portainer user is a system user (UID: $USER_UID)"
else
    printf "${YELLOW}  ⚠ User UID is >= 1000 (UID: $USER_UID)${NC}\n"
fi

printf "\n${CYAN}User Information:${NC}\n"
printf "  Username: %s\n" "$PORTAINER_USER"
printf "  UID: %s\n" "$USER_UID"
printf "  GID: %s\n" "$(id -g "$PORTAINER_USER")"
printf "  Home: %s\n" "$(eval echo ~$PORTAINER_USER)"
printf "  Shell: %s\n" "$(getent passwd "$PORTAINER_USER" | cut -d: -f7)"

print_test_summary
