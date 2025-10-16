#!/bin/bash
# Docker Stack Backup - Test Runner
# Dynamically discovers and runs all tests

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Source test utilities
source "${LIB_DIR}/test-utils.sh"

# Test statistics
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
FAILED_TESTS=()

# Test execution mode
RUN_MODE="${1:-all}"  # all, category name, or test file
VERBOSE="${VERBOSE:-false}"
STOP_ON_FAILURE="${STOP_ON_FAILURE:-false}"

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    MAGENTA=''
    NC=''
fi

# Print banner
print_banner() {
    printf "\n"
    printf "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${MAGENTA}║${NC}  ${CYAN}Docker Stack Backup - Test Suite Runner${NC}                    ${MAGENTA}║${NC}\n"
    printf "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
}

# Print usage
usage() {
    cat << EOF
Usage: $0 [MODE] [OPTIONS]

MODES:
    all                     Run all tests (default)
    <category-number>       Run specific category (e.g., 01, 02)
    <category-name>         Run category by name (e.g., system-preparation)
    <test-file>             Run specific test file

OPTIONS:
    VERBOSE=true            Show detailed output
    STOP_ON_FAILURE=true    Stop on first failure

EXAMPLES:
    $0                                  # Run all tests
    $0 01                               # Run category 01
    $0 system-preparation               # Run system preparation tests
    $0 01-system-preparation/01-*.sh    # Run specific test
    VERBOSE=true $0 all                 # Run all with verbose output
    STOP_ON_FAILURE=true $0 all         # Stop on first failure

EOF
}

# Discover test categories
discover_categories() {
    find "${SCRIPT_DIR}" -maxdepth 1 -type d -name "[0-9][0-9]-*" | sort
}

# Discover tests in category
discover_tests() {
    local category_dir="$1"
    find "${category_dir}" -maxdepth 1 -type f -name "[0-9][0-9]-*.sh" | sort
}

# Extract category name
get_category_name() {
    local category_dir="$1"
    basename "$category_dir" | sed 's/^[0-9][0-9]-//'
}

# Extract test name
get_test_name() {
    local test_file="$1"
    basename "$test_file" .sh | sed 's/^[0-9][0-9]-//'
}

# Run single test
run_test() {
    local test_file="$1"
    local test_name
    test_name=$(get_test_name "$test_file")

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    printf "${CYAN}► Running:${NC} %s\n" "$test_name"

    # Create temporary file for test output
    local test_output
    test_output=$(mktemp)

    # Run test with timeout
    local exit_code=0
    if [[ "$VERBOSE" == "true" ]]; then
        bash "$test_file" 2>&1 | tee "$test_output" || exit_code=$?
    else
        bash "$test_file" > "$test_output" 2>&1 || exit_code=$?
    fi

    # Check test result
    if [[ $exit_code -eq 0 ]]; then
        # Check if test was skipped
        if grep -q "SKIP" "$test_output"; then
            TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
            printf "${YELLOW}  ⊘ SKIPPED${NC}\n"
        else
            TOTAL_PASSED=$((TOTAL_PASSED + 1))
            printf "${GREEN}  ✓ PASSED${NC}\n"
        fi
    else
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        FAILED_TESTS+=("$test_name")
        printf "${RED}  ✗ FAILED${NC}\n"

        # Show failure output if not verbose
        if [[ "$VERBOSE" != "true" ]]; then
            printf "${RED}  Error output:${NC}\n"
            tail -20 "$test_output" | sed 's/^/    /'
        fi

        # Stop on failure if requested
        if [[ "$STOP_ON_FAILURE" == "true" ]]; then
            printf "\n${RED}Stopping due to test failure${NC}\n"
            rm -f "$test_output"
            exit 1
        fi
    fi

    rm -f "$test_output"
    printf "\n"
}

# Run category
run_category() {
    local category_dir="$1"
    local category_name
    category_name=$(get_category_name "$category_dir")

    printf "\n${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║${NC} Category: ${YELLOW}%-50s${NC} ${BLUE}║${NC}\n" "$category_name"
    printf "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}\n\n"

    local tests
    tests=$(discover_tests "$category_dir")

    if [[ -z "$tests" ]]; then
        printf "${YELLOW}  No tests found in this category${NC}\n\n"
        return
    fi

    while IFS= read -r test_file; do
        run_test "$test_file"
    done <<< "$tests"
}

# Run all tests
run_all_tests() {
    local categories
    categories=$(discover_categories)

    if [[ -z "$categories" ]]; then
        printf "${RED}No test categories found${NC}\n"
        exit 1
    fi

    while IFS= read -r category_dir; do
        run_category "$category_dir"
    done <<< "$categories"
}

# Run specific category by number or name
run_specific_category() {
    local search_term="$1"
    local categories
    categories=$(discover_categories)

    local found=false
    while IFS= read -r category_dir; do
        local category_num
        category_num=$(basename "$category_dir" | cut -d'-' -f1)
        local category_name
        category_name=$(get_category_name "$category_dir")

        if [[ "$category_num" == "$search_term" ]] || [[ "$category_name" == "$search_term" ]]; then
            run_category "$category_dir"
            found=true
            break
        fi
    done <<< "$categories"

    if [[ "$found" == "false" ]]; then
        printf "${RED}Category not found: %s${NC}\n" "$search_term"
        exit 1
    fi
}

# Print final summary
print_final_summary() {
    local duration="$1"

    printf "\n"
    printf "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${MAGENTA}║${NC}  ${CYAN}FINAL TEST SUMMARY${NC}                                          ${MAGENTA}║${NC}\n"
    printf "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}\n"
    printf "${MAGENTA}║${NC}  Total Tests:    %-43d ${MAGENTA}║${NC}\n" "$TOTAL_TESTS"
    printf "${MAGENTA}║${NC}  ${GREEN}Passed:${NC}         %-43d ${MAGENTA}║${NC}\n" "$TOTAL_PASSED"
    printf "${MAGENTA}║${NC}  ${RED}Failed:${NC}         %-43d ${MAGENTA}║${NC}\n" "$TOTAL_FAILED"
    printf "${MAGENTA}║${NC}  ${YELLOW}Skipped:${NC}        %-43d ${MAGENTA}║${NC}\n" "$TOTAL_SKIPPED"
    printf "${MAGENTA}║${NC}  Duration:       %-43s ${MAGENTA}║${NC}\n" "${duration}s"
    printf "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}\n"

    if [[ $TOTAL_FAILED -gt 0 ]]; then
        printf "\n${RED}Failed Tests:${NC}\n"
        for test in "${FAILED_TESTS[@]}"; do
            printf "  ${RED}✗${NC} %s\n" "$test"
        done
    fi

    printf "\n"

    if [[ $TOTAL_FAILED -eq 0 ]]; then
        printf "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}\n"
        printf "${GREEN}║${NC}  ${GREEN}✓ ALL TESTS PASSED!${NC}                                         ${GREEN}║${NC}\n"
        printf "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}\n\n"
        return 0
    else
        printf "${RED}╔════════════════════════════════════════════════════════════════╗${NC}\n"
        printf "${RED}║${NC}  ${RED}✗ SOME TESTS FAILED${NC}                                         ${RED}║${NC}\n"
        printf "${RED}╚════════════════════════════════════════════════════════════════╝${NC}\n\n"
        return 1
    fi
}

# Main execution
main() {
    print_banner

    # Check if running inside VM
    if [[ ! -f /etc/os-release ]] || ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        printf "${YELLOW}⚠ WARNING: Tests should be run inside Vagrant VM${NC}\n"
        printf "${YELLOW}  Run: vagrant up && vagrant ssh${NC}\n"
        printf "${YELLOW}  Then: cd ~/docker-stack-backup && sudo ./tests/run-tests.sh${NC}\n\n"
    fi

    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        printf "${YELLOW}⚠ WARNING: Some tests may require sudo privileges${NC}\n"
        printf "${YELLOW}  Consider running: sudo ./tests/run-tests.sh${NC}\n\n"
    fi

    # Start timer
    local start_time
    start_time=$(date +%s)

    # Handle run mode
    case "$RUN_MODE" in
        help|--help|-h)
            usage
            exit 0
            ;;
        all)
            run_all_tests
            ;;
        [0-9][0-9])
            run_specific_category "$RUN_MODE"
            ;;
        *-*)
            run_specific_category "$RUN_MODE"
            ;;
        *.sh)
            if [[ -f "$RUN_MODE" ]]; then
                run_test "$RUN_MODE"
            else
                printf "${RED}Test file not found: %s${NC}\n" "$RUN_MODE"
                exit 1
            fi
            ;;
        *)
            printf "${RED}Invalid run mode: %s${NC}\n" "$RUN_MODE"
            usage
            exit 1
            ;;
    esac

    # Calculate duration
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Print summary
    print_final_summary "$duration"
}

# Run main
main "$@"
