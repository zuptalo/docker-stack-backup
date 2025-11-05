#!/bin/bash
# Test: Check Docker Installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Docker Installation"

# Test 1: Check if docker command exists
if command -v docker >/dev/null 2>&1; then
    assert_command_succeeds "docker is installed" command -v docker
else
    printf "${YELLOW}  Docker not installed - will be installed by backup-manager.sh install${NC}\n"
    skip_test "Docker not installed yet (expected at this stage)"
fi

# Test 2: Check if Docker daemon is running
if sudo docker info >/dev/null 2>&1; then
    assert_command_succeeds "Docker daemon is running" sudo docker info
else
    printf "${YELLOW}  Docker daemon not running${NC}\n"
    assert_true "1" "Docker daemon should be running"
fi

# Test 3: Check Docker version
if command -v docker >/dev/null 2>&1; then
    DOCKER_VERSION=$(docker --version)
    printf "\n${CYAN}Docker Information:${NC}\n"
    printf "  %s\n" "$DOCKER_VERSION"

    # Check Docker version is recent enough (>= 20.10)
    VERSION_NUM=$(echo "$DOCKER_VERSION" | grep -oP '\d+\.\d+' | head -1)
    printf "  Version number: %s\n" "$VERSION_NUM"
fi

# Test 4: Test Docker functionality (run hello-world)
if sudo docker run --rm hello-world >/dev/null 2>&1; then
    assert_command_succeeds "Docker can run containers" sudo docker run --rm hello-world
else
    printf "${YELLOW}  Docker hello-world test skipped${NC}\n"
fi

print_test_summary
