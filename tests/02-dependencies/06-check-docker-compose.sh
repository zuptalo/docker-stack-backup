#!/bin/bash
# Test: Check Docker Compose Availability

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Docker Compose Availability"

# Docker Compose can be either:
# 1. docker-compose (standalone)
# 2. docker compose (plugin)

# Test 1: Check if docker compose plugin exists (preferred)
if sudo docker compose version >/dev/null 2>&1; then
    assert_command_succeeds "docker compose plugin is available" sudo docker compose version
    COMPOSE_VERSION=$(sudo docker compose version)
    printf "\n${CYAN}Docker Compose Information:${NC}\n"
    printf "  %s (plugin)\n" "$COMPOSE_VERSION"
elif command -v docker-compose >/dev/null 2>&1; then
    # Test 2: Check if standalone docker-compose exists
    assert_command_succeeds "docker-compose standalone is available" command -v docker-compose
    COMPOSE_VERSION=$(docker-compose --version)
    printf "\n${CYAN}Docker Compose Information:${NC}\n"
    printf "  %s (standalone)\n" "$COMPOSE_VERSION"
else
    printf "${YELLOW}  Docker Compose not installed - will be installed by backup-manager.sh setup${NC}\n"
    skip_test "Docker Compose not installed yet (expected at this stage)"
fi

# Test 3: Test compose functionality (version command)
if sudo docker compose version >/dev/null 2>&1 || docker-compose --version >/dev/null 2>&1; then
    assert_true "0" "Docker Compose version command works"
else
    assert_true "1" "Docker Compose should be functional"
fi

print_test_summary
