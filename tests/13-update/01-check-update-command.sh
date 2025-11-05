#!/bin/bash
# Test: Check Update Command

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Update Command"

SCRIPT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Test 1: Check if update command exists (optional feature)
printf "\n${CYAN}Checking for update command:${NC}\n"

if grep -q '"update")' "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "update command exists in script"
else
    print_test_result "INFO" "update command not yet implemented (future feature)"
fi

# Test 2: Check for version checking logic
printf "\n${CYAN}Checking version comparison:${NC}\n"

if grep -qi "version\|VERSION" "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "Version handling exists in script"
else
    assert_true "1" "Version handling should exist"
fi

# Test 3: Check for GitHub connectivity
printf "\n${CYAN}Checking GitHub integration:${NC}\n"

if grep -qi "github\|curl.*http" "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "GitHub/HTTP connectivity logic exists"
else
    print_test_result "WARN" "GitHub integration may be missing"
fi

# Test 4: Check VERSION variable is set
printf "\n${CYAN}Checking VERSION variable:${NC}\n"

VERSION=$(grep "^VERSION=" "$SCRIPT_ROOT/backup-manager.sh" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")

if [[ -n "$VERSION" ]]; then
    assert_true "0" "VERSION variable is defined: $VERSION"
    printf "  Current version: %s\n" "$VERSION"
else
    assert_true "1" "VERSION variable should be defined"
fi

print_test_summary
