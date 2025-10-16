#!/bin/bash
# Test: Verify All Dependencies

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Verify All Dependencies"

# List of required commands
REQUIRED_COMMANDS=(curl jq rsync)
OPTIONAL_COMMANDS=(docker dig nslookup lsof netstat tar gzip)

printf "${CYAN}Checking Required Dependencies:${NC}\n\n"

# Test required commands
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        assert_command_succeeds "$cmd is available" command -v "$cmd"
    else
        assert_command_succeeds "$cmd should be available" false
    fi
done

printf "\n${CYAN}Checking Optional Dependencies:${NC}\n\n"

# Test optional commands
for cmd in "${OPTIONAL_COMMANDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        printf "  ${GREEN}✓${NC} %s: Available\n" "$cmd"
    else
        printf "  ${YELLOW}⊘${NC} %s: Not available\n" "$cmd"
    fi
done

# Summary
printf "\n${CYAN}Dependency Summary:${NC}\n"
ALL_AVAILABLE=true
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        ALL_AVAILABLE=false
        printf "  ${RED}✗${NC} Missing required: %s\n" "$cmd"
    fi
done

if [[ "$ALL_AVAILABLE" == "true" ]]; then
    printf "  ${GREEN}✓${NC} All required dependencies are available\n"
    assert_true "0" "All required dependencies available"
else
    printf "  ${RED}✗${NC} Some required dependencies are missing\n"
    assert_true "1" "All required dependencies should be available"
fi

print_test_summary
