#!/bin/bash
# Test: Check Docker Network Exists

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Docker Network Exists"

# Test 1: Verify Docker is running
if ! docker info >/dev/null 2>&1; then
    print_test_result "SKIP" "Docker is not running - cannot test network"
    print_test_summary
    exit 0
fi

# Test 2: Check if prod-network exists
NETWORK_NAME="prod-network"
printf "\n${CYAN}Checking for Docker network: ${NETWORK_NAME}${NC}\n"

if docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
    assert_true "0" "Docker network '$NETWORK_NAME' exists"
else
    print_test_result "WARN" "Docker network '$NETWORK_NAME' doesn't exist (expected on fresh install)"
fi

# Test 3: If network exists, verify it's a bridge network
if docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
    NETWORK_DRIVER=$(docker network inspect "$NETWORK_NAME" --format '{{.Driver}}' 2>/dev/null || echo "unknown")
    printf "  Network driver: %s\n" "$NETWORK_DRIVER"

    assert_equals "bridge" "$NETWORK_DRIVER" "Network should use bridge driver"
fi

# Test 4: If network exists, check its configuration
if docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
    printf "\n${CYAN}Network configuration:${NC}\n"

    NETWORK_SUBNET=$(docker network inspect "$NETWORK_NAME" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "none")
    NETWORK_GATEWAY=$(docker network inspect "$NETWORK_NAME" --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || echo "none")

    printf "  Subnet: %s\n" "$NETWORK_SUBNET"
    printf "  Gateway: %s\n" "$NETWORK_GATEWAY"

    if [[ "$NETWORK_SUBNET" != "none" ]]; then
        assert_true "0" "Network has subnet configuration"
    fi
fi

# Test 5: List containers connected to the network
if docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
    printf "\n${CYAN}Containers on ${NETWORK_NAME}:${NC}\n"

    CONTAINERS=$(docker network inspect "$NETWORK_NAME" --format '{{range $k,$v := .Containers}}{{$v.Name}} {{end}}' 2>/dev/null || echo "")

    if [[ -n "$CONTAINERS" ]]; then
        for container in $CONTAINERS; do
            printf "  - %s\n" "$container"
        done
        assert_true "0" "Network has connected containers"
    else
        print_test_result "WARN" "No containers connected to network (expected if services not deployed)"
    fi
fi

print_test_summary
