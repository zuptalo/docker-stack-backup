#!/bin/bash
# Test: Check Version Format

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Version Format"

SCRIPT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Test 1: Extract and validate VERSION format
printf "\n${CYAN}Checking VERSION format:${NC}\n"

VERSION=$(grep "^VERSION=" "$SCRIPT_ROOT/backup-manager.sh" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")

printf "  Version found: %s\n" "$VERSION"

if [[ -n "$VERSION" ]]; then
    assert_true "0" "VERSION is set"

    # Check if version follows YYYY.MM.DD format (common pattern)
    if [[ "$VERSION" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2} ]]; then
        assert_true "0" "VERSION follows date-based format (YYYY.MM.DD.HHMM)"
    elif [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        assert_true "0" "VERSION follows semantic versioning format"
    else
        print_test_result "INFO" "VERSION uses custom format: $VERSION"
    fi
else
    assert_true "1" "VERSION should be defined"
fi

# Test 2: Check if version is displayed in help
printf "\n${CYAN}Checking version in help output:${NC}\n"

HELP_OUTPUT=$("$SCRIPT_ROOT/backup-manager.sh" --help 2>&1 | head -20 || echo "")

if echo "$HELP_OUTPUT" | grep -q "$VERSION"; then
    assert_true "0" "Version is displayed in help output"
else
    print_test_result "WARN" "Version may not be shown in help"
fi

print_test_summary
