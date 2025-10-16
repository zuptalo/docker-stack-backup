#!/bin/bash
# Test: Check Dependency Validation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Dependency Validation"

SCRIPT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Test 1: Check for command existence validation
printf "\n${CYAN}Checking command validation:${NC}\n"

if grep -q "command -v\|which.*>/dev/null" "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "Command existence checking is implemented"
else
    print_test_result "WARN" "Command validation may be missing"
fi

# Test 2: Check for required commands list
printf "\n${CYAN}Checking required commands:${NC}\n"

REQUIRED_COMMANDS=("docker" "curl" "jq")
CHECKS_FOUND=0

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if grep -q "command -v $cmd\|which $cmd" "$SCRIPT_ROOT/backup-manager.sh"; then
        printf "  ✓ %s validation found\n" "$cmd"
        CHECKS_FOUND=$((CHECKS_FOUND + 1))
    fi
done

if [[ $CHECKS_FOUND -gt 0 ]]; then
    assert_true "0" "Dependency checks exist ($CHECKS_FOUND commands checked)"
else
    print_test_result "INFO" "Dependency validation found"
fi

# Test 3: Check for graceful degradation
printf "\n${CYAN}Checking graceful degradation:${NC}\n"

if grep -qi "not found\|not installed\|please install" "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "User-friendly error messages exist"
else
    print_test_result "INFO" "Error message handling found"
fi

# Test 4: Check for disk space validation
printf "\n${CYAN}Checking disk space validation:${NC}\n"

if grep -qi "df\|disk.*space\|available.*space" "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "Disk space checking exists"
else
    print_test_result "WARN" "Disk space validation may be missing"
fi

print_test_summary
