#!/bin/bash
# Test: Check curl Installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check curl Installation"

# Test 1: Check if curl command exists
if command -v curl >/dev/null 2>&1; then
    assert_command_succeeds "curl is installed" command -v curl
else
    printf "${YELLOW}  Installing curl...${NC}\n"
    sudo apt-get update -qq
    sudo apt-get install -y curl
    assert_command_succeeds "curl installed successfully" command -v curl
fi

# Test 2: Test curl functionality
if assert_command_succeeds "curl can make HTTP requests" curl -sf --connect-timeout 5 https://www.google.com -o /dev/null; then
    :
fi

# Test 3: Check curl version
CURL_VERSION=$(curl --version | head -1)
printf "\n${CYAN}curl Information:${NC}\n"
printf "  %s\n" "$CURL_VERSION"

print_test_summary
