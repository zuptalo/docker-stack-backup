#!/bin/bash
# Test: Check DNS Resolution

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check DNS Resolution"

# Load configuration if it exists
DEFAULT_CONFIG="/etc/docker-backup-manager.conf"
if [[ -f "$DEFAULT_CONFIG" ]]; then
    source "$DEFAULT_CONFIG"
fi

# Test 1: Check if dig/nslookup is available
if ! command -v dig >/dev/null 2>&1 && ! command -v nslookup >/dev/null 2>&1; then
    print_test_result "SKIP" "Neither dig nor nslookup available"
    print_test_summary
    exit 0
fi

# Test 2: Test external DNS resolution
printf "\n${CYAN}Testing external DNS resolution:${NC}\n"

if command -v dig >/dev/null 2>&1; then
    if dig +short google.com @8.8.8.8 | grep -q '[0-9]'; then
        assert_true "0" "Can resolve external domains (google.com)"
    else
        assert_true "1" "Should be able to resolve external domains"
    fi
else
    if nslookup google.com 8.8.8.8 >/dev/null 2>&1; then
        assert_true "0" "Can resolve external domains (google.com)"
    else
        assert_true "1" "Should be able to resolve external domains"
    fi
fi

# Test 3: Test local domain resolution (if DOMAIN_NAME is set)
if [[ -n "${DOMAIN_NAME:-}" ]]; then
    printf "\n${CYAN}Testing local domain resolution:${NC}\n"
    printf "  Domain: %s\n" "$DOMAIN_NAME"

    # Check if domain ends with .local (test mode)
    if [[ "$DOMAIN_NAME" == *.local ]]; then
        print_test_result "INFO" "Using .local domain (test mode) - DNS resolution not expected"
        assert_true "0" "Test mode domain detected"
    else
        # Try to resolve the configured domain
        if command -v dig >/dev/null 2>&1; then
            if dig +short "$DOMAIN_NAME" | grep -q '[0-9]'; then
                assert_true "0" "Can resolve configured domain: $DOMAIN_NAME"
            else
                print_test_result "WARN" "Cannot resolve $DOMAIN_NAME (expected if DNS not configured)"
            fi
        else
            if nslookup "$DOMAIN_NAME" >/dev/null 2>&1; then
                assert_true "0" "Can resolve configured domain: $DOMAIN_NAME"
            else
                print_test_result "WARN" "Cannot resolve $DOMAIN_NAME (expected if DNS not configured)"
            fi
        fi
    fi
fi

# Test 4: Test reverse DNS lookup
printf "\n${CYAN}Testing reverse DNS:${NC}\n"
LOCAL_IP=$(hostname -I | awk '{print $1}')
printf "  Local IP: %s\n" "$LOCAL_IP"

if command -v dig >/dev/null 2>&1; then
    HOSTNAME=$(dig +short -x "$LOCAL_IP" 2>/dev/null | head -1)
    if [[ -n "$HOSTNAME" ]]; then
        printf "  Reverse lookup: %s\n" "$HOSTNAME"
        assert_true "0" "Reverse DNS lookup works"
    else
        print_test_result "WARN" "No reverse DNS configured (this is normal)"
    fi
fi

# Test 5: Check /etc/hosts for any custom entries
printf "\n${CYAN}Checking /etc/hosts for custom entries:${NC}\n"
if grep -qE "portainer|npm|docker" /etc/hosts 2>/dev/null; then
    assert_true "0" "Found custom entries in /etc/hosts"
    grep -E "portainer|npm|docker" /etc/hosts | head -5 | while read line; do
        printf "  %s\n" "$line"
    done
else
    print_test_result "INFO" "No custom entries in /etc/hosts (this is normal)"
fi

print_test_summary
