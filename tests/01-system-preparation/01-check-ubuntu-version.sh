#!/bin/bash
# Test: Check Ubuntu Version Compatibility

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Ubuntu Version Compatibility"

# Check if /etc/os-release exists
if [[ ! -f /etc/os-release ]]; then
    skip_test "Not running on a system with /etc/os-release"
fi

# Source OS release info
source /etc/os-release

# Test 1: Check if running Ubuntu
if [[ "$ID" == "ubuntu" ]]; then
    assert_equals "ubuntu" "$ID" "System is Ubuntu"
else
    assert_equals "ubuntu" "$ID" "System should be Ubuntu, found: $ID"
fi

# Test 2: Check if Ubuntu LTS (version should be even number like 20.04, 22.04, 24.04)
VERSION_NUM="${VERSION_ID%.*}"
if (( VERSION_NUM % 2 == 0 )); then
    assert_true "0" "Ubuntu version is LTS: $VERSION_ID"
else
    assert_true "1" "Ubuntu version should be LTS, found: $VERSION_ID"
fi

# Test 3: Check if version is recent enough (>= 20.04)
if [[ "${VERSION_ID}" == "20.04" ]] || [[ "${VERSION_ID}" == "22.04" ]] || [[ "${VERSION_ID}" == "24.04" ]] || [[ "${VERSION_NUM}" -ge 24 ]]; then
    assert_true "0" "Ubuntu version is recent enough: $VERSION_ID"
else
    assert_true "1" "Ubuntu version should be >= 20.04, found: $VERSION_ID"
fi

# Test 4: Display system information
printf "\n${CYAN}System Information:${NC}\n"
printf "  OS: %s\n" "$NAME"
printf "  Version: %s\n" "$VERSION_ID"
printf "  Codename: %s\n" "${VERSION_CODENAME:-unknown}"
printf "  Architecture: %s\n" "$(uname -m)"

print_test_summary
