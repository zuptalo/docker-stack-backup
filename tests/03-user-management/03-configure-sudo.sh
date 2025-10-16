#!/bin/bash
# Test: Configure Passwordless Sudo for Portainer User

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Configure Passwordless Sudo for Portainer User"

PORTAINER_USER="portainer"
SUDOERS_FILE="/etc/sudoers.d/${PORTAINER_USER}"

# Test 1: Check if portainer user exists
if ! id "$PORTAINER_USER" >/dev/null 2>&1; then
    skip_test "Portainer user does not exist yet"
fi

# Test 2: Check if sudoers.d directory exists
assert_dir_exists "/etc/sudoers.d" "Sudoers.d directory exists"

# Test 3: Create sudoers file for portainer user
if [[ -f "$SUDOERS_FILE" ]]; then
    assert_file_exists "$SUDOERS_FILE" "Sudoers file already exists"
else
    printf "${YELLOW}  Creating sudoers configuration...${NC}\n"
    echo "${PORTAINER_USER} ALL=(ALL) NOPASSWD: ALL" | sudo tee "$SUDOERS_FILE" > /dev/null
    sudo chmod 440 "$SUDOERS_FILE"
    assert_file_exists "$SUDOERS_FILE" "Sudoers file created"
fi

# Test 4: Verify sudoers file syntax
if sudo visudo -c -f "$SUDOERS_FILE" >/dev/null 2>&1; then
    assert_command_succeeds "Sudoers file syntax is valid" sudo visudo -c -f "$SUDOERS_FILE"
else
    assert_command_succeeds "Sudoers file should be valid" false
fi

# Test 5: Check file permissions (should be 440)
FILE_PERMS=$(stat -c "%a" "$SUDOERS_FILE" 2>/dev/null || stat -f "%A" "$SUDOERS_FILE" 2>/dev/null)
if [[ "$FILE_PERMS" == "440" ]] || [[ "$FILE_PERMS" == "0440" ]]; then
    assert_true "0" "Sudoers file has correct permissions: $FILE_PERMS"
else
    printf "${YELLOW}  ⚠ Sudoers file permissions: $FILE_PERMS (expected: 440)${NC}\n"
fi

printf "\n${CYAN}Sudoers Configuration:${NC}\n"
sudo cat "$SUDOERS_FILE" 2>/dev/null || printf "  (cannot read file)\n"

print_test_summary
