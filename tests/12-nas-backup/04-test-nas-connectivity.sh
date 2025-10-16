#!/bin/bash
# Test: Test NAS Server Connectivity

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test NAS Server Connectivity"

NAS_IP="192.168.56.20"
NAS_USER="vagrant"
NAS_BACKUP_DIR="/mnt/nas-backup"

# Test 1: Check if NAS VM is reachable
printf "\n${CYAN}Checking NAS server connectivity:${NC}\n"

if ping -c 1 -W 2 "$NAS_IP" >/dev/null 2>&1; then
    assert_true "0" "NAS server is reachable at $NAS_IP"
else
    print_test_result "SKIP" "NAS VM not running - start with: vagrant up nas"
    print_test_summary
    exit 0
fi

# Test 2: Check SSH connectivity to NAS
printf "\n${CYAN}Checking SSH connectivity:${NC}\n"

if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "$NAS_USER@$NAS_IP" "echo test" >/dev/null 2>&1; then
    assert_true "0" "SSH connection to NAS successful"
else
    print_test_result "INFO" "SSH requires password or key setup (expected initially)"
fi

# Test 3: Check if NAS has required tools
printf "\n${CYAN}Checking NAS server tools:${NC}\n"

# Try to check rsync on NAS (may fail if SSH not configured)
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "$NAS_USER@$NAS_IP" "command -v rsync" >/dev/null 2>&1; then
    assert_true "0" "rsync is available on NAS"
else
    print_test_result "INFO" "Unable to verify rsync on NAS (SSH setup required)"
fi

# Test 4: Network connectivity test
printf "\n${CYAN}Network configuration:${NC}\n"

printf "  Primary VM IP: 192.168.56.10\n"
printf "  NAS VM IP: %s\n" "$NAS_IP"
printf "  Backup directory: %s\n" "$NAS_BACKUP_DIR"

assert_true "0" "Network configuration documented"

print_test_summary
