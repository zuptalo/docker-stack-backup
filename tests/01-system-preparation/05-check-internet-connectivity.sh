#!/bin/bash
# Test: Check Internet Connectivity

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Internet Connectivity"

# Test 1: Check if we can resolve DNS
if assert_command_succeeds "DNS resolution works" nslookup google.com; then
    :
fi

# Test 2: Check connectivity to GitHub (required for updates)
if assert_command_succeeds "GitHub is accessible" curl -sf --connect-timeout 5 https://github.com -o /dev/null; then
    :
fi

# Test 3: Check connectivity to Docker Hub (required for images)
if assert_command_succeeds "Docker Hub is accessible" curl -sf --connect-timeout 5 https://hub.docker.com -o /dev/null; then
    :
fi

# Test 4: Check connectivity to Ubuntu repositories
if assert_command_succeeds "Ubuntu repos accessible" curl -sf --connect-timeout 5 http://archive.ubuntu.com -o /dev/null; then
    :
fi

printf "\n${CYAN}Network Status:${NC}\n"
printf "  Hostname: %s\n" "$(hostname)"
printf "  IP Address: %s\n" "$(hostname -I | awk '{print $1}')"

# Show available network interfaces
printf "\n${CYAN}Network Interfaces:${NC}\n"
ip -br addr 2>/dev/null | grep -v "lo " || ifconfig -a 2>/dev/null | grep -E "^[a-z]" | head -5

print_test_summary
