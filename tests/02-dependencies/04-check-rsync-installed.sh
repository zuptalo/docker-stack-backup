#!/bin/bash
# Test: Check rsync Installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check rsync Installation"

# Test 1: Check if rsync command exists
if command -v rsync >/dev/null 2>&1; then
    assert_command_succeeds "rsync is installed" command -v rsync
else
    printf "${YELLOW}  Installing rsync...${NC}\n"
    sudo apt-get update -qq
    sudo apt-get install -y rsync
    assert_command_succeeds "rsync installed successfully" command -v rsync
fi

# Test 2: Test rsync functionality
TEST_FILE=$(mktemp)
TEST_DEST=$(mktemp)
echo "test content" > "$TEST_FILE"
if rsync -a "$TEST_FILE" "$TEST_DEST" 2>/dev/null; then
    assert_true "0" "rsync can copy files"
    rm -f "$TEST_FILE" "$TEST_DEST"
else
    assert_true "1" "rsync file copy failed"
fi

# Test 3: Check rsync version
RSYNC_VERSION=$(rsync --version 2>/dev/null | head -1 || echo "rsync (version unknown)")
printf "\n${CYAN}rsync Information:${NC}\n"
printf "  %s\n" "$RSYNC_VERSION"

print_test_summary
