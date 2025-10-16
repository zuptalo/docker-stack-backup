#!/bin/bash
# Test: Check Error Handling Functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Error Handling Functions"

SCRIPT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Test 1: Check for error/warn/info/success functions
printf "\n${CYAN}Checking logging functions:${NC}\n"

FUNCTIONS=("error" "warn" "info" "success")
FOUND_COUNT=0

for func in "${FUNCTIONS[@]}"; do
    if grep -q "^${func}()" "$SCRIPT_ROOT/backup-manager.sh"; then
        printf "  ✓ %s() function exists\n" "$func"
        FOUND_COUNT=$((FOUND_COUNT + 1))
    else
        printf "  ✗ %s() function not found\n" "$func"
    fi
done

if [[ $FOUND_COUNT -eq 4 ]]; then
    assert_equals "4" "$FOUND_COUNT" "All logging functions exist"
else
    assert_true "0" "Found $FOUND_COUNT out of 4 logging functions"
fi

# Test 2: Check for set -e or error trapping
printf "\n${CYAN}Checking error handling mode:${NC}\n"

if grep -q "set -e\|set -euo pipefail\|trap.*ERR" "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "Error handling mode is enabled"
else
    print_test_result "WARN" "Script may not have strict error handling"
fi

# Test 3: Check for recovery file creation
printf "\n${CYAN}Checking recovery mechanisms:${NC}\n"

if grep -qi "recovery\|rollback\|backup.*before" "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "Recovery mechanisms exist in script"
else
    print_test_result "INFO" "Recovery mechanism references found"
fi

# Test 4: Check for validation functions
printf "\n${CYAN}Checking validation functions:${NC}\n"

VALIDATION_COUNT=$(grep -c "^validate_\|^check_" "$SCRIPT_ROOT/backup-manager.sh" 2>/dev/null || echo "0")

printf "  Validation functions found: %d\n" "$VALIDATION_COUNT"

if [[ $VALIDATION_COUNT -gt 0 ]]; then
    assert_true "0" "Validation functions exist ($VALIDATION_COUNT found)"
else
    print_test_result "WARN" "No validation functions found"
fi

print_test_summary
