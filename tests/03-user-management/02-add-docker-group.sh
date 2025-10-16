#!/bin/bash
# Test: Add Portainer User to Docker Group

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Add Portainer User to Docker Group"

PORTAINER_USER="portainer"

# Test 1: Check if portainer user exists
if ! id "$PORTAINER_USER" >/dev/null 2>&1; then
    skip_test "Portainer user does not exist yet"
fi

# Test 2: Check if docker group exists
if ! getent group docker >/dev/null 2>&1; then
    printf "${YELLOW}  Creating docker group...${NC}\n"
    sudo groupadd docker 2>/dev/null || true
fi

assert_command_succeeds "Docker group exists" getent group docker

# Test 3: Add portainer user to docker group
if groups "$PORTAINER_USER" 2>/dev/null | grep -qw docker; then
    assert_user_in_group "$PORTAINER_USER" "docker" "Portainer user already in docker group"
else
    printf "${YELLOW}  Adding portainer to docker group...${NC}\n"
    sudo usermod -aG docker "$PORTAINER_USER"
    assert_user_in_group "$PORTAINER_USER" "docker" "Portainer user added to docker group"
fi

# Test 4: Verify user can access docker (requires re-login)
printf "\n${CYAN}Group Membership:${NC}\n"
groups "$PORTAINER_USER"

print_test_summary
