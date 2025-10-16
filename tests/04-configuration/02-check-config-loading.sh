#!/bin/bash
# Test: Check Configuration Loading

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Configuration Loading"

DEFAULT_CONFIG="/etc/docker-backup-manager.conf"

# Test 1: Check if config file exists before testing load
if [[ ! -f "$DEFAULT_CONFIG" ]]; then
    print_test_result "SKIP" "Config file doesn't exist - cannot test loading"
    print_test_summary
    exit 0
fi

# Test 2: Verify config file has valid bash syntax
printf "\n${CYAN}Testing configuration file syntax:${NC}\n"
if bash -n "$DEFAULT_CONFIG" 2>/dev/null; then
    assert_true "0" "Configuration file has valid bash syntax"
else
    assert_true "1" "Configuration file should have valid syntax"
    print_test_summary
    exit 1
fi

# Test 3: Source config and verify variables are set
printf "\n${CYAN}Testing configuration variable loading:${NC}\n"

# Source the config file
source "$DEFAULT_CONFIG"

# Check that key variables are set and not empty
if [[ -n "$PORTAINER_PATH" ]]; then
    assert_not_equals "" "$PORTAINER_PATH" "PORTAINER_PATH should be set"
    printf "  PORTAINER_PATH: %s\n" "$PORTAINER_PATH"
else
    assert_true "1" "PORTAINER_PATH should not be empty"
fi

if [[ -n "$NPM_PATH" ]]; then
    assert_not_equals "" "$NPM_PATH" "NPM_PATH should be set"
    printf "  NPM_PATH: %s\n" "$NPM_PATH"
else
    assert_true "1" "NPM_PATH should not be empty"
fi

if [[ -n "$BACKUP_PATH" ]]; then
    assert_not_equals "" "$BACKUP_PATH" "BACKUP_PATH should be set"
    printf "  BACKUP_PATH: %s\n" "$BACKUP_PATH"
else
    assert_true "1" "BACKUP_PATH should not be empty"
fi

if [[ -n "$BACKUP_RETENTION" ]]; then
    assert_not_equals "" "$BACKUP_RETENTION" "BACKUP_RETENTION should be set"
    printf "  BACKUP_RETENTION: %s\n" "$BACKUP_RETENTION"
else
    assert_true "1" "BACKUP_RETENTION should not be empty"
fi

if [[ -n "$DOMAIN_NAME" ]]; then
    assert_not_equals "" "$DOMAIN_NAME" "DOMAIN_NAME should be set"
    printf "  DOMAIN_NAME: %s\n" "$DOMAIN_NAME"
else
    assert_true "1" "DOMAIN_NAME should not be empty"
fi

# Test 4: Verify BACKUP_RETENTION is a valid number
printf "\n${CYAN}Testing configuration value validation:${NC}\n"
if [[ "$BACKUP_RETENTION" =~ ^[0-9]+$ ]]; then
    assert_true "0" "BACKUP_RETENTION is a valid number: $BACKUP_RETENTION"
else
    assert_true "1" "BACKUP_RETENTION should be a number, got: $BACKUP_RETENTION"
fi

# Test 5: Verify paths are absolute
if [[ "$PORTAINER_PATH" == /* ]]; then
    assert_true "0" "PORTAINER_PATH is an absolute path"
else
    assert_true "1" "PORTAINER_PATH should be absolute, got: $PORTAINER_PATH"
fi

if [[ "$NPM_PATH" == /* ]]; then
    assert_true "0" "NPM_PATH is an absolute path"
else
    assert_true "1" "NPM_PATH should be absolute, got: $NPM_PATH"
fi

if [[ "$BACKUP_PATH" == /* ]]; then
    assert_true "0" "BACKUP_PATH is an absolute path"
else
    assert_true "1" "BACKUP_PATH should be absolute, got: $BACKUP_PATH"
fi

print_test_summary
