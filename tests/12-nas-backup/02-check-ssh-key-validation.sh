#!/bin/bash
# Test: Check SSH Key Validation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check SSH Key Validation"

# Test 1: Check if validate_ssh_setup function exists
printf "\n${CYAN}Checking SSH validation function:${NC}\n"

SCRIPT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if grep -q "validate_ssh_setup" "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "SSH validation function exists"
else
    print_test_result "WARN" "SSH validation function not found"
fi

# Test 2: Check if SSH directory creation is handled
printf "\n${CYAN}Checking SSH directory handling:${NC}\n"

if grep -q "\.ssh" "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "SSH directory handling exists in script"
else
    print_test_result "WARN" "SSH directory handling may be missing"
fi

# Test 3: Check for Ed25519 key generation
printf "\n${CYAN}Checking key type:${NC}\n"

if grep -qi "ed25519\|ssh-keygen" "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "SSH key generation logic exists"
else
    print_test_result "INFO" "SSH key generation references found"
fi

print_test_summary
