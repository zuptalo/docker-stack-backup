#!/bin/bash
# Test: Stack Data Directory Backup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test Stack Data Backup"

# Load configuration
DEFAULT_CONFIG="/etc/docker-backup-manager.conf"
if [[ ! -f "$DEFAULT_CONFIG" ]]; then
    skip_test "Config file not found"
fi

source "$DEFAULT_CONFIG"

# Test 1: Find latest backup
printf "\n${CYAN}Finding latest backup:${NC}\n"

LATEST_BACKUP=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | sort -r | head -1)

if [[ -z "$LATEST_BACKUP" ]]; then
    skip_test "No backup files found"
fi

printf "  Latest: %s\n" "$(basename "$LATEST_BACKUP")"

# Test 2: Check for Portainer data directory
printf "\n${CYAN}Checking Portainer data in backup:${NC}\n"

# Avoid pipefail issue with grep -q by using grep with output redirect
if tar -tzf "$LATEST_BACKUP" 2>/dev/null | grep "opt/portainer/" >/dev/null 2>&1; then
    assert_true "0" "Portainer data directory found in backup"

    # List some Portainer files
    printf "  Portainer files in backup:\n"
    tar -tzf "$LATEST_BACKUP" 2>/dev/null | grep "opt/portainer/" | head -10 | while read file; do
        printf "    - %s\n" "$file"
    done
else
    assert_true "1" "Portainer data directory should be in backup"
fi

# Test 3: Check for Portainer compose directory
printf "\n${CYAN}Checking Portainer compose directory:${NC}\n"

if tar -tzf "$LATEST_BACKUP" 2>/dev/null | grep "opt/portainer/data/compose/" >/dev/null 2>&1; then
    assert_true "0" "Portainer compose directory found in backup"

    # List compose files
    COMPOSE_FILES=$(tar -tzf "$LATEST_BACKUP" 2>/dev/null | grep "^opt/portainer/data/compose/.*/docker-compose.yml$" | wc -l)
    printf "  Compose files found: %d\n" "$COMPOSE_FILES"

    if [[ $COMPOSE_FILES -gt 0 ]]; then
        assert_true "0" "At least one docker-compose.yml file found"

        # List the compose files
        tar -tzf "$LATEST_BACKUP" 2>/dev/null | grep "^opt/portainer/data/compose/.*/docker-compose.yml$" | while read file; do
            printf "    - %s\n" "$file"
        done
    else
        print_test_result "WARN" "No docker-compose.yml files found in backup"
    fi
else
    print_test_result "WARN" "Portainer compose directory not found in backup"
fi

# Test 4: Check for NPM data directory
printf "\n${CYAN}Checking NPM data in backup:${NC}\n"

if tar -tzf "$LATEST_BACKUP" 2>/dev/null | grep "opt/nginx-proxy-manager/" >/dev/null 2>&1; then
    assert_true "0" "NPM data directory found in backup"

    # Check for specific NPM files
    if tar -tzf "$LATEST_BACKUP" 2>/dev/null | grep "opt/nginx-proxy-manager/data/database.sqlite$" >/dev/null 2>&1; then
        assert_true "0" "NPM database file found in backup"
    else
        print_test_result "WARN" "NPM database.sqlite not found in backup"
    fi
else
    print_test_result "WARN" "NPM data directory not found in backup"
fi

# Test 5: Check for tools directory (custom stacks)
printf "\n${CYAN}Checking tools directory for custom stacks:${NC}\n"

if tar -tzf "$LATEST_BACKUP" 2>/dev/null | grep "opt/tools/" >/dev/null 2>&1; then
    assert_true "0" "Tools directory found in backup"

    # List stack directories in tools
    STACK_DIRS=$(tar -tzf "$LATEST_BACKUP" 2>/dev/null | grep "^opt/tools/[^/]*/$" | sed 's|opt/tools/||' | sed 's|/$||' | sort -u)

    if [[ -n "$STACK_DIRS" ]]; then
        printf "  Stack directories found:\n"
        echo "$STACK_DIRS" | while read stack_dir; do
            printf "    - %s\n" "$stack_dir"

            # Check if this stack has data
            DATA_FILES=$(tar -tzf "$LATEST_BACKUP" 2>/dev/null | grep "^opt/tools/$stack_dir/" | wc -l)
            printf "      Files: %d\n" "$DATA_FILES"
        done

        assert_true "0" "Custom stack directories found in backup"
    else
        print_test_result "INFO" "No custom stack directories found (this is OK if no custom stacks deployed)"
    fi
else
    print_test_result "INFO" "Tools directory not in backup (no custom stacks deployed)"
fi

# Test 6: Verify specific test files if they exist
printf "\n${CYAN}Checking for test marker files:${NC}\n"

# Check if nginx-web stack data exists
if [[ -d "/opt/tools/nginx-web" ]]; then
    printf "  nginx-web stack data exists on filesystem\n"

    if tar -tzf "$LATEST_BACKUP" 2>/dev/null | grep "opt/tools/nginx-web/html/index.html$" >/dev/null 2>&1; then
        assert_true "0" "nginx-web index.html found in backup"

        # Extract and show file size
        TEMP_DIR=$(mktemp -d)
        tar -xzf "$LATEST_BACKUP" -C "$TEMP_DIR" "opt/tools/nginx-web/html/index.html" 2>/dev/null

        if [[ -f "$TEMP_DIR/opt/tools/nginx-web/html/index.html" ]]; then
            FILE_SIZE=$(wc -c < "$TEMP_DIR/opt/tools/nginx-web/html/index.html")
            printf "    File size: %d bytes\n" "$FILE_SIZE"

            if [[ $FILE_SIZE -gt 0 ]]; then
                assert_true "0" "nginx-web index.html has content"
            else
                print_test_result "WARN" "nginx-web index.html is empty"
            fi
        fi

        rm -rf "$TEMP_DIR"
    else
        print_test_result "WARN" "nginx-web index.html not found in backup"
    fi
else
    printf "  nginx-web stack not deployed (skipping)\n"
fi

# Test 7: Verify directory structure is preserved
printf "\n${CYAN}Verifying directory structure preservation:${NC}\n"

# Check that directories exist with trailing slashes
DIRS_IN_BACKUP=$(tar -tzf "$LATEST_BACKUP" 2>/dev/null | grep "/$" | wc -l)
printf "  Total directories in backup: %d\n" "$DIRS_IN_BACKUP"

if [[ $DIRS_IN_BACKUP -gt 0 ]]; then
    assert_true "0" "Directory structure is preserved in backup"
else
    print_test_result "WARN" "No directories found in backup listing"
fi

# Test 8: Check for critical subdirectories
printf "\n${CYAN}Checking critical subdirectories:${NC}\n"

CRITICAL_DIRS=(
    "opt/portainer/data/"
    "opt/nginx-proxy-manager/data/"
)

for dir in "${CRITICAL_DIRS[@]}"; do
    if tar -tzf "$LATEST_BACKUP" 2>/dev/null | grep "^$dir" >/dev/null 2>&1; then
        printf "  ✓ %s\n" "$dir"
    else
        printf "  ✗ %s (not found)\n" "$dir"
    fi
done

print_test_summary
