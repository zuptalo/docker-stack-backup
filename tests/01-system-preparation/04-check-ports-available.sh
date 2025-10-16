#!/bin/bash
# Test: Check Required Ports Available

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Required Ports Available"

# Required ports for the application
REQUIRED_PORTS=(80 443)
OPTIONAL_PORTS=(9000 81)

# Function to check if port is in use
check_port_available() {
    local port="$1"
    if sudo lsof -i ":${port}" -sTCP:LISTEN >/dev/null 2>&1 || \
       sudo netstat -tuln 2>/dev/null | grep -q ":${port} "; then
        return 1  # Port is in use
    else
        return 0  # Port is available
    fi
}

# Test 1: Check port 80 is available
if check_port_available 80; then
    assert_true "0" "Port 80 is available"
else
    printf "${YELLOW}  ⚠ Port 80 is in use (may need to stop existing service)${NC}\n"
    sudo lsof -i :80 2>/dev/null | head -5
fi

# Test 2: Check port 443 is available
if check_port_available 443; then
    assert_true "0" "Port 443 is available"
else
    printf "${YELLOW}  ⚠ Port 443 is in use (may need to stop existing service)${NC}\n"
    sudo lsof -i :443 2>/dev/null | head -5
fi

# Test 3: Check optional port 9000 (Portainer)
if check_port_available 9000; then
    assert_true "0" "Port 9000 is available (Portainer)"
else
    printf "${YELLOW}  ⚠ Port 9000 is in use${NC}\n"
fi

# Test 4: Check optional port 81 (NPM admin)
if check_port_available 81; then
    assert_true "0" "Port 81 is available (NPM admin)"
else
    printf "${YELLOW}  ⚠ Port 81 is in use${NC}\n"
fi

printf "\n${CYAN}Port Status:${NC}\n"
for port in "${REQUIRED_PORTS[@]}" "${OPTIONAL_PORTS[@]}"; do
    if check_port_available "$port"; then
        printf "  ${GREEN}✓${NC} Port %d: Available\n" "$port"
    else
        printf "  ${RED}✗${NC} Port %d: In Use\n" "$port"
    fi
done

print_test_summary
