#!/bin/bash
# Test: Check jq Installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check jq Installation"

# Test 1: Check if jq command exists
if command -v jq >/dev/null 2>&1; then
    assert_command_succeeds "jq is installed" command -v jq
else
    printf "${YELLOW}  Installing jq...${NC}\n"
    sudo apt-get update -qq
    sudo apt-get install -y jq
    assert_command_succeeds "jq installed successfully" command -v jq
fi

# Test 2: Test jq functionality
TEST_JSON='{"test": "value", "number": 42}'
RESULT=$(echo "$TEST_JSON" | jq -r '.test' 2>/dev/null)
if assert_equals "value" "$RESULT" "jq can parse JSON"; then
    :
fi

# Test 3: Check jq version
JQ_VERSION=$(jq --version 2>&1)
printf "\n${CYAN}jq Information:${NC}\n"
printf "  %s\n" "$JQ_VERSION"

print_test_summary
