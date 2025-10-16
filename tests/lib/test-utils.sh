#!/bin/bash
# Test Utilities Library
# Common functions for test scripts

set -euo pipefail

# Colors for test output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    NC=''
fi

# Test state tracking
TEST_NAME="${TEST_NAME:-Unknown Test}"
TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0
ASSERTION_COUNT=0

# Initialize test environment
setup_test_env() {
    local test_file="${1:-}"
    if [[ -n "$test_file" ]]; then
        TEST_NAME=$(basename "$test_file" .sh)
    fi
    TEST_PASSED=0
    TEST_FAILED=0
    TEST_SKIPPED=0
    ASSERTION_COUNT=0
}

# Cleanup test environment
cleanup_test_env() {
    # Override this in test files if cleanup is needed
    :
}

# Print test header
print_test_header() {
    local test_name="${1:-$TEST_NAME}"
    printf "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
    printf "${CYAN}TEST: %s${NC}\n" "$test_name"
    printf "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n\n"
}

# Print test result
print_test_result() {
    local status="$1"
    local message="${2:-}"

    case "$status" in
        PASS)
            printf "${GREEN}✓ PASS${NC}"
            ;;
        FAIL)
            printf "${RED}✗ FAIL${NC}"
            ;;
        SKIP)
            printf "${YELLOW}⊘ SKIP${NC}"
            ;;
    esac

    if [[ -n "$message" ]]; then
        printf ": %s" "$message"
    fi
    printf "\n"
}

# Skip test with reason
skip_test() {
    local reason="${1:-No reason provided}"
    TEST_SKIPPED=1
    print_test_result "SKIP" "$reason"
    exit 0
}

# Assert equals
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '$expected', got '$actual'}"

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

    if [[ "$expected" == "$actual" ]]; then
        TEST_PASSED=$((TEST_PASSED + 1))
        print_test_result "PASS" "Assert equals: $message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        print_test_result "FAIL" "Assert equals: $message"
        return 1
    fi
}

# Assert not equals
assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-Expected NOT '$not_expected', got '$actual'}"

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

    if [[ "$not_expected" != "$actual" ]]; then
        TEST_PASSED=$((TEST_PASSED + 1))
        print_test_result "PASS" "Assert not equals: $message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        print_test_result "FAIL" "Assert not equals: $message"
        return 1
    fi
}

# Assert true
assert_true() {
    local condition="$1"
    local message="${2:-Condition should be true}"

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

    if [[ "$condition" == "true" ]] || [[ "$condition" == "0" ]] || [[ "$condition" -eq 0 ]] 2>/dev/null; then
        TEST_PASSED=$((TEST_PASSED + 1))
        print_test_result "PASS" "Assert true: $message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        print_test_result "FAIL" "Assert true: $message"
        return 1
    fi
}

# Assert false
assert_false() {
    local condition="$1"
    local message="${2:-Condition should be false}"

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

    if [[ "$condition" == "false" ]] || [[ "$condition" == "1" ]] || [[ "$condition" -ne 0 ]] 2>/dev/null; then
        TEST_PASSED=$((TEST_PASSED + 1))
        print_test_result "PASS" "Assert false: $message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        print_test_result "FAIL" "Assert false: $message"
        return 1
    fi
}

# Assert file exists
assert_file_exists() {
    local file="$1"
    local message="${2:-File '$file' should exist}"

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

    if [[ -f "$file" ]]; then
        TEST_PASSED=$((TEST_PASSED + 1))
        print_test_result "PASS" "Assert file exists: $message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        print_test_result "FAIL" "Assert file exists: $message"
        return 1
    fi
}

# Assert directory exists
assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory '$dir' should exist}"

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

    if [[ -d "$dir" ]]; then
        TEST_PASSED=$((TEST_PASSED + 1))
        print_test_result "PASS" "Assert dir exists: $message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        print_test_result "FAIL" "Assert dir exists: $message"
        return 1
    fi
}

# Assert command succeeds
assert_command_succeeds() {
    local message="${1:-Command should succeed}"
    shift

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

    if "$@" >/dev/null 2>&1; then
        TEST_PASSED=$((TEST_PASSED + 1))
        print_test_result "PASS" "Assert command succeeds: $message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        print_test_result "FAIL" "Assert command succeeds: $message (command: $*)"
        return 1
    fi
}

# Assert command fails
assert_command_fails() {
    local message="${1:-Command should fail}"
    shift

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

    if ! "$@" >/dev/null 2>&1; then
        TEST_PASSED=$((TEST_PASSED + 1))
        print_test_result "PASS" "Assert command fails: $message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        print_test_result "FAIL" "Assert command fails: $message (command: $*)"
        return 1
    fi
}

# Assert string contains
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain '$needle'}"

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

    if [[ "$haystack" == *"$needle"* ]]; then
        TEST_PASSED=$((TEST_PASSED + 1))
        print_test_result "PASS" "Assert contains: $message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        print_test_result "FAIL" "Assert contains: $message"
        return 1
    fi
}

# Assert string does not contain
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should NOT contain '$needle'}"

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

    if [[ "$haystack" != *"$needle"* ]]; then
        TEST_PASSED=$((TEST_PASSED + 1))
        print_test_result "PASS" "Assert not contains: $message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        print_test_result "FAIL" "Assert not contains: $message"
        return 1
    fi
}

# Assert service is running
assert_service_running() {
    local service_name="$1"
    local message="${2:-Service '$service_name' should be running}"

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

    if sudo docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${service_name}$"; then
        TEST_PASSED=$((TEST_PASSED + 1))
        print_test_result "PASS" "Assert service running: $message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        print_test_result "FAIL" "Assert service running: $message"
        return 1
    fi
}

# Assert port is open
assert_port_open() {
    local port="$1"
    local host="${2:-localhost}"
    local message="${3:-Port $port on $host should be open}"

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

    if timeout 2 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null; then
        TEST_PASSED=$((TEST_PASSED + 1))
        print_test_result "PASS" "Assert port open: $message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        print_test_result "FAIL" "Assert port open: $message"
        return 1
    fi
}

# Assert user exists
assert_user_exists() {
    local username="$1"
    local message="${2:-User '$username' should exist}"

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

    if id "$username" >/dev/null 2>&1; then
        TEST_PASSED=$((TEST_PASSED + 1))
        print_test_result "PASS" "Assert user exists: $message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        print_test_result "FAIL" "Assert user exists: $message"
        return 1
    fi
}

# Assert group membership
assert_user_in_group() {
    local username="$1"
    local groupname="$2"
    local message="${3:-User '$username' should be in group '$groupname'}"

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))

    if groups "$username" 2>/dev/null | grep -qw "$groupname"; then
        TEST_PASSED=$((TEST_PASSED + 1))
        print_test_result "PASS" "Assert user in group: $message"
        return 0
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        print_test_result "FAIL" "Assert user in group: $message"
        return 1
    fi
}

# Print test summary
print_test_summary() {
    printf "\n${BLUE}───────────────────────────────────────────────────────────────${NC}\n"
    printf "${CYAN}TEST SUMMARY: %s${NC}\n" "$TEST_NAME"
    printf "${BLUE}───────────────────────────────────────────────────────────────${NC}\n"
    printf "Total Assertions: %d\n" "$ASSERTION_COUNT"
    printf "${GREEN}Passed: %d${NC}\n" "$TEST_PASSED"
    printf "${RED}Failed: %d${NC}\n" "$TEST_FAILED"
    printf "${YELLOW}Skipped: %d${NC}\n" "$TEST_SKIPPED"

    if [[ $TEST_FAILED -eq 0 && $TEST_SKIPPED -eq 0 ]]; then
        printf "\n${GREEN}✓ ALL TESTS PASSED${NC}\n"
        return 0
    elif [[ $TEST_FAILED -eq 0 && $TEST_SKIPPED -gt 0 ]]; then
        printf "\n${YELLOW}⊘ TESTS SKIPPED${NC}\n"
        return 0
    else
        printf "\n${RED}✗ SOME TESTS FAILED${NC}\n"
        return 1
    fi
}

# Wait for service to be ready
wait_for_service() {
    local service_name="$1"
    local max_wait="${2:-60}"
    local interval="${3:-2}"

    local elapsed=0
    printf "Waiting for service '%s' to be ready" "$service_name"

    while [[ $elapsed -lt $max_wait ]]; do
        if sudo docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${service_name}$"; then
            printf " ${GREEN}✓${NC}\n"
            return 0
        fi
        printf "."
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    printf " ${RED}✗${NC}\n"
    return 1
}

# Wait for port to be open
wait_for_port() {
    local port="$1"
    local host="${2:-localhost}"
    local max_wait="${3:-60}"
    local interval="${4:-2}"

    local elapsed=0
    printf "Waiting for port %s on %s to be open" "$port" "$host"

    while [[ $elapsed -lt $max_wait ]]; do
        if timeout 2 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null; then
            printf " ${GREEN}✓${NC}\n"
            return 0
        fi
        printf "."
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    printf " ${RED}✗${NC}\n"
    return 1
}

# Get backup-manager.sh path
get_backup_manager_path() {
    local test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    echo "${test_dir}/../backup-manager.sh"
}

# Run backup-manager command
run_backup_manager() {
    local backup_manager="$(get_backup_manager_path)"
    sudo "$backup_manager" "$@"
}

# Export functions for use in test scripts
export -f setup_test_env
export -f cleanup_test_env
export -f print_test_header
export -f print_test_result
export -f print_test_summary
export -f skip_test
export -f assert_equals
export -f assert_not_equals
export -f assert_true
export -f assert_false
export -f assert_file_exists
export -f assert_dir_exists
export -f assert_command_succeeds
export -f assert_command_fails
export -f assert_contains
export -f assert_not_contains
export -f assert_service_running
export -f assert_port_open
export -f assert_user_exists
export -f assert_user_in_group
export -f wait_for_service
export -f wait_for_port
export -f get_backup_manager_path
export -f run_backup_manager
