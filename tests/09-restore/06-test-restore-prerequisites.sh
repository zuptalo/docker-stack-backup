#!/bin/bash
# Test: Test Restore Prerequisites

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test Restore Prerequisites"

# Load config first
DEFAULT_CONFIG="/etc/docker-backup-manager.conf"
if [[ -f "$DEFAULT_CONFIG" ]]; then
    source "$DEFAULT_CONFIG"
fi

# Test 1: Check Portainer API is accessible (needed for stack restore)
printf "\n${CYAN}Checking Portainer API:${NC}\n"

if curl -sf "http://localhost:9000/api/status" >/dev/null 2>&1; then
    assert_true "0" "Portainer API is accessible for restore operations"
else
    print_test_result "WARN" "Portainer API not accessible (may impact restore)"
fi

# Test 2: Check credentials file exists
printf "\n${CYAN}Checking credentials:${NC}\n"

CRED_FILE="/opt/portainer/.credentials"

if [[ -f "$CRED_FILE" ]]; then
    assert_file_exists "$CRED_FILE" "Credentials file exists"

    # Check if can read credentials
    if [[ -r "$CRED_FILE" ]]; then
        assert_true "0" "Credentials file is readable"
    fi
else
    print_test_result "WARN" "Credentials file not found"
fi

# Test 3: Check sufficient disk space
printf "\n${CYAN}Checking disk space:${NC}\n"

BACKUP_PATH="${BACKUP_PATH:-/opt/backup}"
AVAILABLE_GB=$(df -BG "$BACKUP_PATH" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G' || echo "0")
printf "  Available space: %d GB\n" "$AVAILABLE_GB"

if [[ $AVAILABLE_GB -gt 5 ]]; then
    assert_true "0" "Sufficient disk space for restore (> 5GB)"
else
    print_test_result "WARN" "Low disk space: ${AVAILABLE_GB}GB"
fi

# Test 4: Check target directories exist
printf "\n${CYAN}Checking target directories:${NC}\n"

if [[ -f "$DEFAULT_CONFIG" ]]; then

    for dir in "$PORTAINER_PATH" "$NPM_PATH"; do
        if [[ -d "$dir" ]]; then
            printf "  ✓ %s exists\n" "$dir"
        else
            printf "  ✗ %s missing\n" "$dir"
        fi
    done
fi

# Test 5: Check backup file availability
printf "\n${CYAN}Checking backup availability:${NC}\n"

if [[ -f "$DEFAULT_CONFIG" ]]; then
    BACKUP_COUNT=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | wc -l)

    printf "  Available backups: %d\n" "$BACKUP_COUNT"

    if [[ $BACKUP_COUNT -gt 0 ]]; then
        assert_true "0" "Backups available for restore"
    else
        assert_true "1" "No backups available"
    fi
fi

# Test 6: Check Docker is accessible
printf "\n${CYAN}Checking Docker access:${NC}\n"

if docker ps >/dev/null 2>&1; then
    assert_true "0" "Can access Docker daemon"
else
    assert_true "1" "Cannot access Docker daemon"
fi

# Test 7: Check portainer user permissions
printf "\n${CYAN}Checking user permissions:${NC}\n"

PORTAINER_USER="${PORTAINER_USER:-portainer}"

if id "$PORTAINER_USER" >/dev/null 2>&1; then
    # Check if user can access docker
    if sudo -u "$PORTAINER_USER" docker ps >/dev/null 2>&1; then
        assert_true "0" "Portainer user can access Docker"
    else
        print_test_result "WARN" "Portainer user may not have Docker access"
    fi
fi

# Test 8: Summary
printf "\n${CYAN}Restore readiness summary:${NC}\n"

READY_COUNT=0
ISSUES=0

# Check all prerequisites (use if statements to avoid pipefail issues)
if [[ -f "$CRED_FILE" ]]; then
    READY_COUNT=$((READY_COUNT + 1))
else
    ISSUES=$((ISSUES + 1))
fi

if [[ ${AVAILABLE_GB:-0} -gt 5 ]]; then
    READY_COUNT=$((READY_COUNT + 1))
else
    ISSUES=$((ISSUES + 1))
fi

if [[ ${BACKUP_COUNT:-0} -gt 0 ]]; then
    READY_COUNT=$((READY_COUNT + 1))
else
    ISSUES=$((ISSUES + 1))
fi

printf "  Prerequisites met: %d\n" "$READY_COUNT"
printf "  Issues found: %d\n" "$ISSUES"

if [[ $ISSUES -eq 0 ]]; then
    assert_true "0" "System is ready for restore operations"
else
    print_test_result "WARN" "System has $ISSUES prerequisite issues"
fi

print_test_summary
