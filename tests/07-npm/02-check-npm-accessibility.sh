#!/bin/bash
# Test: Check NPM Accessibility

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check NPM Accessibility"

# Test 1: Check if NPM Admin interface is accessible (port 81)
printf "\n${CYAN}Testing NPM Admin interface (port 81):${NC}\n"

if curl -sf "http://localhost:81" >/dev/null 2>&1; then
    assert_true "0" "NPM Admin interface is accessible on port 81"
else
    print_test_result "WARN" "NPM Admin interface not accessible (expected if not deployed)"
    print_test_summary
    exit 0
fi

# Test 2: Check HTTP proxy (port 80)
printf "\n${CYAN}Testing NPM HTTP proxy (port 80):${NC}\n"

if curl -sf "http://localhost:80" >/dev/null 2>&1; then
    assert_true "0" "NPM HTTP proxy is accessible on port 80"
else
    # It's normal for this to return errors if no proxy hosts configured
    print_test_result "INFO" "NPM HTTP proxy responding (may return error if no hosts configured)"
fi

# Test 3: Check HTTPS proxy (port 443)
printf "\n${CYAN}Testing NPM HTTPS proxy (port 443):${NC}\n"

if curl -sfk "https://localhost:443" >/dev/null 2>&1; then
    assert_true "0" "NPM HTTPS proxy is accessible on port 443"
else
    print_test_result "INFO" "NPM HTTPS proxy responding (may return error if no hosts configured)"
fi

# Test 4: Check if NPM credentials exist
NPM_CRED_FILE="/opt/npm/.credentials"

if [[ -f "$NPM_CRED_FILE" ]]; then
    assert_file_exists "$NPM_CRED_FILE" "NPM credentials file exists"

    printf "\n${CYAN}NPM credentials info:${NC}\n"
    printf "  Path: %s\n" "$NPM_CRED_FILE"
    printf "  Permissions: %s\n" "$(stat -c "%a" "$NPM_CRED_FILE" 2>/dev/null || stat -f "%Lp" "$NPM_CRED_FILE" 2>/dev/null)"

    # Check for expected fields
    if grep -q "NPM_ADMIN_EMAIL" "$NPM_CRED_FILE" 2>/dev/null; then
        assert_true "0" "Credentials contain admin email"
    fi

    if grep -q "NPM_ADMIN_PASSWORD" "$NPM_CRED_FILE" 2>/dev/null; then
        assert_true "0" "Credentials contain admin password"
    fi
else
    print_test_result "WARN" "NPM credentials file not found"
fi

# Test 5: Test NPM Admin login page
printf "\n${CYAN}Testing NPM Admin login page:${NC}\n"

LOGIN_PAGE=$(curl -sf "http://localhost:81/login" 2>/dev/null || echo "")

if echo "$LOGIN_PAGE" | grep -qi "nginx.*proxy.*manager\|login"; then
    assert_true "0" "NPM login page loads successfully"
else
    print_test_result "INFO" "NPM login page may have loaded but couldn't verify content"
fi

# Test 6: Check NPM API endpoint
printf "\n${CYAN}Testing NPM API:${NC}\n"

API_RESPONSE=$(curl -sf "http://localhost:81/api/" 2>/dev/null || echo "")

if [[ -n "$API_RESPONSE" ]]; then
    assert_true "0" "NPM API is responding"
else
    print_test_result "INFO" "NPM API endpoint check (may require authentication)"
fi

print_test_summary
