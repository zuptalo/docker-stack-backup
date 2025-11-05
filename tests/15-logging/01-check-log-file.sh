#!/bin/bash
# Test: Check Log File

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Log File"

LOG_FILE="/var/log/docker-backup-manager.log"

# Test 1: Check if log file exists
printf "\n${CYAN}Checking log file existence:${NC}\n"

if [[ -f "$LOG_FILE" ]]; then
    assert_file_exists "$LOG_FILE" "Log file exists"
else
    print_test_result "WARN" "Log file doesn't exist yet (expected if no operations run)"
    print_test_summary
    exit 0
fi

# Test 2: Check log file permissions
printf "\n${CYAN}Checking log file permissions:${NC}\n"

PERMS=$(stat -c "%a" "$LOG_FILE" 2>/dev/null || stat -f "%Lp" "$LOG_FILE" 2>/dev/null)
OWNER=$(stat -c "%U:%G" "$LOG_FILE" 2>/dev/null || stat -f "%Su:%Sg" "$LOG_FILE" 2>/dev/null)

printf "  Permissions: %s\n" "$PERMS"
printf "  Owner: %s\n" "$OWNER"

# Log file should be writable
if [[ "$PERMS" =~ ^[67] ]] || [[ "$PERMS" =~ [67]$ ]]; then
    assert_true "0" "Log file has write permissions"
else
    print_test_result "WARN" "Log file may not be writable: $PERMS"
fi

# Test 3: Check log file size
printf "\n${CYAN}Checking log file size:${NC}\n"

SIZE_BYTES=$(stat -c "%s" "$LOG_FILE" 2>/dev/null || stat -f "%z" "$LOG_FILE" 2>/dev/null)
SIZE_KB=$((SIZE_BYTES / 1024))

printf "  Size: %d bytes (%d KB)\n" "$SIZE_BYTES" "$SIZE_KB"

if [[ $SIZE_BYTES -gt 0 ]]; then
    assert_true "0" "Log file contains data"
else
    print_test_result "WARN" "Log file is empty"
fi

# Test 4: Check recent log entries
printf "\n${CYAN}Recent log entries (last 5):${NC}\n"

if [[ -r "$LOG_FILE" ]]; then
    tail -5 "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
        printf "  %s\n" "$line"
    done
    assert_true "0" "Can read log file"
else
    assert_true "1" "Log file should be readable"
fi

# Test 5: Check for log levels in output
printf "\n${CYAN}Checking log format:${NC}\n"

if grep -qE "\[(INFO|SUCCESS|WARN|ERROR)\]" "$LOG_FILE" 2>/dev/null; then
    assert_true "0" "Log file contains formatted log levels"
else
    print_test_result "INFO" "Log format may not include standard levels"
fi

# Test 6: Check for timestamps
if grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{2}:[0-9]{2}:[0-9]{2}" "$LOG_FILE" 2>/dev/null; then
    assert_true "0" "Log entries include timestamps"
else
    print_test_result "INFO" "Log entries may not have timestamps"
fi

print_test_summary
