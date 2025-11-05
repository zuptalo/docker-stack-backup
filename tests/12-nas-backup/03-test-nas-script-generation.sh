#!/bin/bash
# Test: Test NAS Script Generation
# This test runs INSIDE the primary VM

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

# Test 1: Check for SSH key requirement
printf "\n${CYAN}Checking SSH key requirements:${NC}\n"

SSH_KEY_DIR="/home/portainer/.ssh"
if [[ -d "$SSH_KEY_DIR" ]]; then
    printf "  SSH directory exists: %s\n" "$SSH_KEY_DIR"

    if [[ -f "$SSH_KEY_DIR/id_ed25519" ]]; then
        assert_file_exists "$SSH_KEY_DIR/id_ed25519" "SSH private key exists"
    else
        print_test_result "SKIP" "SSH key not yet generated - setup required"
        print_test_summary
        exit 0
    fi
else
    print_test_result "SKIP" "SSH directory not created - setup required"
    print_test_summary
    exit 0
fi

# Test 2: Check for rsync availability
printf "\n${CYAN}Checking rsync availability:${NC}\n"

if command -v rsync >/dev/null 2>&1; then
    assert_true "0" "rsync is installed"

    RSYNC_VERSION=$(rsync --version 2>/dev/null | head -1 || echo "unknown")
    printf "  Version: %s\n" "$RSYNC_VERSION"
else
    print_test_result "WARN" "rsync not installed"
fi

# Test 3: Check if backups exist on primary
printf "\n${CYAN}Checking for backups:${NC}\n"

source "/etc/docker-backup-manager.conf"
BACKUP_COUNT=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | wc -l | tr -d ' ')

if [[ $BACKUP_COUNT -eq 0 ]]; then
    print_test_result "SKIP" "No backups available - create one first"
    print_test_summary
    exit 0
fi

printf "  Available backups: %d\n" "$BACKUP_COUNT"
assert_true "0" "Backups available for NAS sync"

# Test 4: Generate NAS script using sudo
printf "\n${CYAN}Generating NAS backup client script:${NC}\n"

NAS_SCRIPT_NAME="nas-backup-client.sh"
NAS_SCRIPT_PATH="$SCRIPT_ROOT/$NAS_SCRIPT_NAME"

# Clean up any existing script
if [[ -f "$NAS_SCRIPT_PATH" ]]; then
    rm -f "$NAS_SCRIPT_PATH"
fi

# Generate the script using the command with predefined inputs
# Note: Test runs as root, but backup-manager.sh needs to run as regular user
# Use su to run as vagrant user (properly sets USER and SUDO_USER)
set +e
if [[ $EUID -eq 0 ]]; then
    # Running as root (via sudo ./tests/run-tests.sh), execute as vagrant user
    # Ensure /tmp is writable and use su to properly set environment
    chmod 1777 /tmp 2>/dev/null || true
    GENERATION_OUTPUT=$(printf "%s\n%s\n%s\n%s\n%s\n" \
        "192.168.56.20" \
        "vagrant" \
        "/mnt/nas-backup" \
        "$NAS_SCRIPT_NAME" \
        "30" \
        | su -s /bin/bash vagrant -c "cd '$SCRIPT_ROOT' && ./backup-manager.sh generate-nas-script" 2>&1)
else
    # Running as regular user
    GENERATION_OUTPUT=$(printf "%s\n%s\n%s\n%s\n%s\n" \
        "192.168.56.20" \
        "vagrant" \
        "/mnt/nas-backup" \
        "$NAS_SCRIPT_NAME" \
        "30" \
        | "$SCRIPT_ROOT/backup-manager.sh" generate-nas-script 2>&1)
fi
GEN_EXIT=$?
set -e

if [[ $GEN_EXIT -eq 0 ]] && [[ -f "$NAS_SCRIPT_PATH" ]]; then
    assert_file_exists "$NAS_SCRIPT_PATH" "NAS client script generated successfully"

    # Verify script is executable
    if [[ -x "$NAS_SCRIPT_PATH" ]]; then
        assert_true "0" "Script is executable"
    else
        assert_true "1" "Script should be executable"
        exit 1
    fi

    # Verify script contains embedded SSH key (base64-encoded)
    if grep -q 'SSH_PRIVATE_KEY_B64="[A-Za-z0-9+/=]\{50,\}"' "$NAS_SCRIPT_PATH"; then
        assert_true "0" "SSH key (base64-encoded) embedded in script"
    else
        assert_true "1" "SSH key should be embedded in script"
        exit 1
    fi

    SCRIPT_SIZE=$(du -h "$NAS_SCRIPT_PATH" | cut -f1)
    printf "  Script size: %s\n" "$SCRIPT_SIZE"
    printf "  Script location: %s\n" "$NAS_SCRIPT_PATH"
else
    printf "  Generation output:\n%s\n" "$GENERATION_OUTPUT"
    assert_true "1" "Failed to generate NAS client script"
    exit 1
fi

print_test_summary
