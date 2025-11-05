#!/bin/bash
# Test: Check NAS Script Generation Command

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check NAS Script Generation Command"

SCRIPT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Test 1: Check if generate-nas-script command exists in help
printf "\n${CYAN}Checking for generate-nas-script command:${NC}\n"

if grep -q "generate-nas-script" "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "generate-nas-script command exists in script"
else
    assert_true "1" "generate-nas-script command should exist"
    print_test_summary
    exit 1
fi

# Test 2: Check if function is defined
printf "\n${CYAN}Checking for NAS script generation function:${NC}\n"

if grep -q "^generate_nas_script()" "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "generate_nas_script function is defined"
else
    assert_true "1" "generate_nas_script function should be defined"
fi

# Test 3: Check help text exists for the command
printf "\n${CYAN}Checking help documentation:${NC}\n"

HELP_OUTPUT=$("$SCRIPT_ROOT/backup-manager.sh" help generate-nas-script 2>&1 || echo "")

if echo "$HELP_OUTPUT" | grep -qi "generate-nas-script"; then
    assert_true "0" "Help documentation exists for generate-nas-script"
else
    print_test_result "WARN" "Help documentation may be missing"
fi

print_test_summary
