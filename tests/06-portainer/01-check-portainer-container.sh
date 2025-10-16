#!/bin/bash
# Test: Check Portainer Container

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Portainer Container"

# Test 1: Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_test_result "SKIP" "Docker is not running"
    print_test_summary
    exit 0
fi

# Test 2: Check if Portainer container exists
printf "\n${CYAN}Checking for Portainer container:${NC}\n"

PORTAINER_CONTAINER=$(docker ps -a --filter "name=portainer" --format '{{.Names}}' | head -1)

if [[ -n "$PORTAINER_CONTAINER" ]]; then
    assert_true "0" "Portainer container exists: $PORTAINER_CONTAINER"
else
    print_test_result "WARN" "Portainer container not found (expected if not deployed)"
    print_test_summary
    exit 0
fi

# Test 3: Check if Portainer is running
PORTAINER_STATUS=$(docker ps --filter "name=portainer" --format '{{.Status}}' | head -1)

if [[ -n "$PORTAINER_STATUS" ]]; then
    assert_true "0" "Portainer container is running"
    printf "  Status: %s\n" "$PORTAINER_STATUS"
else
    assert_true "1" "Portainer container should be running"
fi

# Test 4: Check Portainer container health
HEALTH_STATUS=$(docker inspect "$PORTAINER_CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")

printf "\n${CYAN}Container health status:${NC}\n"
if [[ "$HEALTH_STATUS" != "none" ]]; then
    printf "  Health: %s\n" "$HEALTH_STATUS"

    if [[ "$HEALTH_STATUS" == "healthy" ]]; then
        assert_equals "healthy" "$HEALTH_STATUS" "Portainer is healthy"
    else
        print_test_result "WARN" "Portainer health status: $HEALTH_STATUS"
    fi
else
    print_test_result "INFO" "No health check configured (this is normal)"
fi

# Test 5: Check Portainer port mapping
printf "\n${CYAN}Port mappings:${NC}\n"
docker port "$PORTAINER_CONTAINER" 2>/dev/null | while read line; do
    printf "  %s\n" "$line"
done

# Verify port 9000 is mapped
if docker port "$PORTAINER_CONTAINER" 2>/dev/null | grep -q '9000'; then
    assert_true "0" "Port 9000 is mapped"
else
    assert_true "1" "Port 9000 should be mapped"
fi

# Test 6: Check Portainer volumes
printf "\n${CYAN}Volume mounts:${NC}\n"
docker inspect "$PORTAINER_CONTAINER" --format '{{range .Mounts}}{{.Type}}: {{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
        printf "  %s\n" "$line"
    fi
done

# Check for data volume
if docker inspect "$PORTAINER_CONTAINER" --format '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' 2>/dev/null | grep -q '/data'; then
    assert_true "0" "Portainer data volume is mounted"
else
    assert_true "1" "Portainer should have /data volume mounted"
fi

# Test 7: Check Docker socket mount
if docker inspect "$PORTAINER_CONTAINER" --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' 2>/dev/null | grep -q 'docker.sock'; then
    assert_true "0" "Docker socket is mounted"
else
    assert_true "1" "Docker socket should be mounted"
fi

print_test_summary
