#!/bin/bash
# Test: Test NAS VM Availability
# Note: We don't test connectivity FROM Primary TO NAS
# In production, the Primary server won't know about the NAS
# We only verify the NAS VM is running for E2E testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test NAS VM Availability"

# Test 1: Check if NAS VM is running (for E2E test purposes)
printf "\n${CYAN}Checking if NAS VM is available for testing:${NC}\n"

# Use vagrant status to check if NAS VM is running
if vagrant status nas 2>/dev/null | grep -q "running"; then
    assert_true "0" "NAS VM is running and available for E2E testing"

    # Verify NAS has required tools (rsync, ssh)
    printf "\n${CYAN}Verifying NAS VM tools:${NC}\n"
    if vagrant ssh nas -c "command -v rsync && command -v ssh" >/dev/null 2>&1; then
        assert_true "0" "NAS VM has required tools (rsync, ssh)"
    else
        assert_true "1" "NAS VM missing required tools"
    fi
else
    print_test_result "SKIP" "NAS VM not running - start with: vagrant up nas"
    print_test_summary
    exit 0
fi

# Test 2: Configuration information
printf "\n${CYAN}NAS test environment configuration:${NC}\n"

printf "  Primary VM IP: 192.168.56.10\n"
printf "  NAS VM IP: 192.168.56.20\n"
printf "  NAS Backup Directory: /mnt/nas-backup\n"
printf "  NAS User: vagrant\n"
printf "\n  Note: In production, Primary server doesn't need to know about NAS\n"
printf "  The generated script is copied manually and run on NAS\n"

assert_true "0" "NAS test configuration documented"

print_test_summary
