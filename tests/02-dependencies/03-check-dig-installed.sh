#!/bin/bash
# Test: Check dig/nslookup Installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check dig/nslookup Installation"

# Test 1: Check if dig command exists
if command -v dig >/dev/null 2>&1; then
    assert_command_succeeds "dig is installed" command -v dig
else
    printf "${YELLOW}  Installing dnsutils (dig)...${NC}\n"
    sudo apt-get update -qq
    sudo apt-get install -y dnsutils
    assert_command_succeeds "dig installed successfully" command -v dig
fi

# Test 2: Check if nslookup exists as fallback
if command -v nslookup >/dev/null 2>&1; then
    assert_command_succeeds "nslookup is available" command -v nslookup
else
    printf "${YELLOW}  nslookup not available (dig will be used)${NC}\n"
fi

# Test 3: Test dig functionality
if assert_command_succeeds "dig can resolve domains" dig +short google.com; then
    :
fi

# Test 4: Display DNS resolution info
printf "\n${CYAN}DNS Resolution Test:${NC}\n"
dig +short google.com | head -3

print_test_summary
