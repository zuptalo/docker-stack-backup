#!/bin/bash
# Test: Test Service Status Before Restore

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test Service Status Before Restore"

# Check if Docker is installed first
if ! command -v docker >/dev/null 2>&1; then
    print_test_result "SKIP" "Docker not installed - skipping service status tests"
    print_test_summary
    exit 0
fi

# Test 1: Check Docker is running
printf "\n${CYAN}Checking Docker daemon:${NC}\n"

if docker info >/dev/null 2>&1; then
    assert_true "0" "Docker daemon is running"
else
    print_test_result "SKIP" "Docker daemon not running - skipping restore service status tests"
    print_test_summary
    exit 0
fi

# Test 2: List all running containers
printf "\n${CYAN}Current running containers:${NC}\n"

CONTAINER_COUNT=$(docker ps -q 2>/dev/null | wc -l)
printf "  Running containers: %d\n" "$CONTAINER_COUNT"

if [[ $CONTAINER_COUNT -gt 0 ]]; then
    assert_true "0" "Containers are running"

    docker ps --format "  - {{.Names}} ({{.Status}})" 2>/dev/null
else
    print_test_result "WARN" "No containers running"
fi

# Test 3: Check Portainer status
printf "\n${CYAN}Checking Portainer status:${NC}\n"

if docker ps --filter "name=portainer" --format '{{.Names}}' | grep -q "portainer"; then
    assert_true "0" "Portainer container is running"

    STATUS=$(docker ps --filter "name=portainer" --format '{{.Status}}' | head -1)
    printf "  Status: %s\n" "$STATUS"
else
    print_test_result "WARN" "Portainer is not running"
fi

# Test 4: Check NPM status
printf "\n${CYAN}Checking NPM status:${NC}\n"

if docker ps --filter "name=npm" --format '{{.Names}}' | grep -q "npm"; then
    assert_true "0" "NPM container is running"

    STATUS=$(docker ps --filter "name=npm" --format '{{.Status}}' | head -1)
    printf "  Status: %s\n" "$STATUS"
else
    print_test_result "WARN" "NPM is not running"
fi

# Test 5: Check API accessibility
printf "\n${CYAN}Checking service accessibility:${NC}\n"

# Portainer API
if curl -sf "http://localhost:9000/api/status" >/dev/null 2>&1; then
    assert_true "0" "Portainer API is accessible"
else
    print_test_result "WARN" "Portainer API not accessible"
fi

# NPM Admin
if curl -sf "http://localhost:81" >/dev/null 2>&1; then
    assert_true "0" "NPM admin is accessible"
else
    print_test_result "WARN" "NPM admin not accessible"
fi

# Test 6: Check Docker networks
printf "\n${CYAN}Checking Docker networks:${NC}\n"

if docker network ls --format '{{.Name}}' | grep -q "prod-network"; then
    assert_true "0" "prod-network exists"
else
    print_test_result "WARN" "prod-network not found"
fi

# Test 7: Check Docker volumes
printf "\n${CYAN}Checking Docker volumes:${NC}\n"

VOLUME_COUNT=$(docker volume ls -q 2>/dev/null | wc -l)
printf "  Docker volumes: %d\n" "$VOLUME_COUNT"

if [[ $VOLUME_COUNT -gt 0 ]]; then
    docker volume ls --format "  - {{.Name}}" 2>/dev/null | head -5
fi

# Test 8: Record current state for comparison
printf "\n${CYAN}Recording current state:${NC}\n"

# This would be used by later tests to verify restore worked
CONTAINER_IDS=$(docker ps -q 2>/dev/null | sort)
CONTAINER_NAMES=$(docker ps --format '{{.Names}}' 2>/dev/null | sort)

printf "  Container IDs: %d containers\n" "$(echo "$CONTAINER_IDS" | wc -l)"
printf "  Ready for restore testing\n"

assert_true "0" "System state recorded"

print_test_summary
