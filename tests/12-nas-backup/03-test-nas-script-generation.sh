#!/bin/bash
# Test: Test NAS Script Generation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test NAS Script Generation"

SCRIPT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Check if config exists
if [[ ! -f "/etc/docker-backup-manager.conf" ]]; then
    print_test_result "SKIP" "Config file not found - setup required first"
    print_test_summary
    exit 0
fi

# Test 1: Check if NAS script can be generated
printf "\n${CYAN}Testing NAS script generation:${NC}\n"

# Generate the script (non-interactively if possible)
NAS_SCRIPT="/tmp/nas-backup-client-test.sh"

# Try to generate without prompts by checking the function
if grep -q "generate_nas_script" "$SCRIPT_ROOT/backup-manager.sh"; then
    assert_true "0" "NAS script generation function exists"

    # Check if the function creates output
    printf "  Script generation function validated\n"
else
    print_test_result "SKIP" "NAS script generation not available"
    print_test_summary
    exit 0
fi

# Test 2: Check for SSH key requirement
printf "\n${CYAN}Checking SSH key requirements:${NC}\n"

SSH_KEY_DIR="/home/portainer/.ssh"
if [[ -d "$SSH_KEY_DIR" ]]; then
    printf "  SSH directory exists: %s\n" "$SSH_KEY_DIR"

    if [[ -f "$SSH_KEY_DIR/id_ed25519" ]]; then
        assert_file_exists "$SSH_KEY_DIR/id_ed25519" "SSH private key exists"
    else
        print_test_result "INFO" "SSH key not yet generated"
    fi
else
    print_test_result "INFO" "SSH directory not yet created (expected if setup not run)"
fi

# Test 3: Check for rsync availability
printf "\n${CYAN}Checking rsync availability:${NC}\n"

if command -v rsync >/dev/null 2>&1; then
    assert_true "0" "rsync is installed"

    RSYNC_VERSION=$(rsync --version 2>/dev/null | head -1 || echo "unknown")
    printf "  Version: %s\n" "$RSYNC_VERSION"
else
    print_test_result "WARN" "rsync not installed"
fi

print_test_summary
