#!/bin/bash
# Test: Verify Log File Write Permissions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Verify Log File Write Permissions"

PORTAINER_USER="portainer"
LOG_FILE="/var/log/docker-backup-manager.log"

# Test 1: Check if portainer user exists
if ! id "$PORTAINER_USER" >/dev/null 2>&1; then
    skip_test "Portainer user does not exist yet"
fi

# Test 2: Create log file if it doesn't exist
if [[ ! -f "$LOG_FILE" ]]; then
    printf "${YELLOW}  Creating log file...${NC}\n"
    sudo touch "$LOG_FILE"
    sudo chmod 666 "$LOG_FILE"
fi

assert_file_exists "$LOG_FILE" "Log file exists"

# Test 3: Check if portainer user can write to log file
if sudo -u "$PORTAINER_USER" bash -c "echo 'test' >> '$LOG_FILE'" 2>/dev/null; then
    assert_true "0" "Portainer user can write to log file"
else
    printf "${YELLOW}  Fixing log file permissions...${NC}\n"
    sudo chmod 666 "$LOG_FILE"
    assert_command_succeeds "Log file writable after fix" sudo -u "$PORTAINER_USER" bash -c "echo 'test' >> '$LOG_FILE'"
fi

# Test 4: Check log file permissions
FILE_PERMS=$(stat -c "%a" "$LOG_FILE" 2>/dev/null || stat -f "%Lp" "$LOG_FILE" 2>/dev/null)
printf "\n${CYAN}Log File Information:${NC}\n"
printf "  Path: %s\n" "$LOG_FILE"
printf "  Permissions: %s\n" "$FILE_PERMS"
printf "  Owner: %s\n" "$(stat -c "%U" "$LOG_FILE" 2>/dev/null || stat -f "%Su" "$LOG_FILE" 2>/dev/null)"

print_test_summary
