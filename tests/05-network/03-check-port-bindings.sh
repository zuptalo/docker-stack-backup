#!/bin/bash
# Test: Check Port Bindings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Port Bindings"

# Test 1: Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_test_result "SKIP" "Docker is not running"
    print_test_summary
    exit 0
fi

# Test 2: Check Portainer port (9000)
printf "\n${CYAN}Checking Portainer port (9000):${NC}\n"

if ss -tuln 2>/dev/null | grep -q ':9000 ' || netstat -tuln 2>/dev/null | grep -q ':9000 '; then
    assert_true "0" "Portainer port 9000 is bound"

    # Find which container is using this port
    CONTAINER=$(docker ps --format '{{.Names}}' --filter "publish=9000" 2>/dev/null | head -1)
    if [[ -n "$CONTAINER" ]]; then
        printf "  Container: %s\n" "$CONTAINER"
    fi
else
    print_test_result "WARN" "Portainer port 9000 not bound (expected if not deployed)"
fi

# Test 3: Check NPM HTTP port (80)
printf "\n${CYAN}Checking NPM HTTP port (80):${NC}\n"

if ss -tuln 2>/dev/null | grep -q ':80 ' || netstat -tuln 2>/dev/null | grep -q ':80 '; then
    assert_true "0" "NPM HTTP port 80 is bound"

    CONTAINER=$(docker ps --format '{{.Names}}' --filter "publish=80" 2>/dev/null | head -1)
    if [[ -n "$CONTAINER" ]]; then
        printf "  Container: %s\n" "$CONTAINER"
    fi
else
    print_test_result "WARN" "NPM port 80 not bound (expected if not deployed)"
fi

# Test 4: Check NPM HTTPS port (443)
printf "\n${CYAN}Checking NPM HTTPS port (443):${NC}\n"

if ss -tuln 2>/dev/null | grep -q ':443 ' || netstat -tuln 2>/dev/null | grep -q ':443 '; then
    assert_true "0" "NPM HTTPS port 443 is bound"

    CONTAINER=$(docker ps --format '{{.Names}}' --filter "publish=443" 2>/dev/null | head -1)
    if [[ -n "$CONTAINER" ]]; then
        printf "  Container: %s\n" "$CONTAINER"
    fi
else
    print_test_result "WARN" "NPM port 443 not bound (expected if not deployed)"
fi

# Test 5: Check NPM Admin port (81)
printf "\n${CYAN}Checking NPM Admin port (81):${NC}\n"

if ss -tuln 2>/dev/null | grep -q ':81 ' || netstat -tuln 2>/dev/null | grep -q ':81 '; then
    assert_true "0" "NPM Admin port 81 is bound"

    CONTAINER=$(docker ps --format '{{.Names}}' --filter "publish=81" 2>/dev/null | head -1)
    if [[ -n "$CONTAINER" ]]; then
        printf "  Container: %s\n" "$CONTAINER"
    fi
else
    print_test_result "WARN" "NPM port 81 not bound (expected if not deployed)"
fi

# Test 6: List all Docker container port bindings
printf "\n${CYAN}All Docker container port bindings:${NC}\n"
docker ps --format "table {{.Names}}\t{{.Ports}}" 2>/dev/null | grep -v "^NAMES" | while read line; do
    if [[ -n "$line" ]]; then
        printf "  %s\n" "$line"
    fi
done

if [[ $(docker ps -q 2>/dev/null | wc -l) -eq 0 ]]; then
    print_test_result "INFO" "No containers running"
fi

print_test_summary
