#!/bin/bash
# Test: Check Adequate Disk Space

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Adequate Disk Space"

# Minimum required space in GB
MIN_ROOT_SPACE=10
MIN_OPT_SPACE=5

# Get available space in GB
get_available_space_gb() {
    local path="$1"
    df -BG "$path" 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$4); print $4}'
}

# Test 1: Check root filesystem has enough space
ROOT_SPACE=$(get_available_space_gb "/")
if [[ -n "$ROOT_SPACE" ]] && (( ROOT_SPACE >= MIN_ROOT_SPACE )); then
    assert_true "0" "Root filesystem has adequate space: ${ROOT_SPACE}GB (min: ${MIN_ROOT_SPACE}GB)"
else
    assert_true "1" "Root filesystem needs at least ${MIN_ROOT_SPACE}GB, found: ${ROOT_SPACE}GB"
fi

# Test 2: Check /opt has enough space (may be same as root)
if [[ -d /opt ]]; then
    OPT_SPACE=$(get_available_space_gb "/opt")
    if [[ -n "$OPT_SPACE" ]] && (( OPT_SPACE >= MIN_OPT_SPACE )); then
        assert_true "0" "/opt has adequate space: ${OPT_SPACE}GB (min: ${MIN_OPT_SPACE}GB)"
    else
        printf "${YELLOW}  ⚠ /opt has limited space: ${OPT_SPACE}GB (min recommended: ${MIN_OPT_SPACE}GB)${NC}\n"
    fi
fi

# Test 3: Check /var has enough space for Docker
VAR_SPACE=$(get_available_space_gb "/var")
if [[ -n "$VAR_SPACE" ]] && (( VAR_SPACE >= MIN_ROOT_SPACE )); then
    assert_true "0" "/var has adequate space: ${VAR_SPACE}GB (min: ${MIN_ROOT_SPACE}GB)"
else
    assert_true "1" "/var needs at least ${MIN_ROOT_SPACE}GB for Docker, found: ${VAR_SPACE}GB"
fi

# Test 4: Check total system memory
TOTAL_MEM_MB=$(free -m | awk 'NR==2 {print $2}')
MIN_MEM_MB=1024
if [[ -n "$TOTAL_MEM_MB" ]] && (( TOTAL_MEM_MB >= MIN_MEM_MB )); then
    assert_true "0" "System has adequate memory: ${TOTAL_MEM_MB}MB (min: ${MIN_MEM_MB}MB)"
else
    assert_true "1" "System needs at least ${MIN_MEM_MB}MB RAM, found: ${TOTAL_MEM_MB}MB"
fi

printf "\n${CYAN}Disk Space Summary:${NC}\n"
df -h / /opt /var 2>/dev/null | grep -v "^Filesystem" || df -h /

printf "\n${CYAN}Memory Summary:${NC}\n"
free -h

print_test_summary
