#!/bin/bash
# Full Lifecycle Test - Automated End-to-End Testing
# This script automates the complete test lifecycle:
# 1. Fresh VM setup
# 2. Installation
# 3. Backup creation
# 4. NAS VM setup
# 5. NAS backup sync
# 6. Complete test suite execution

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUN_NAS_TESTS="${RUN_NAS_TESTS:-true}"
CLEAN_START="${CLEAN_START:-true}"

# Test statistics
START_TIME=$(date +%s)
STAGE_TIMES=()

# Print banner
print_banner() {
    printf "\n"
    printf "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${MAGENTA}║${NC}  ${CYAN}Docker Stack Backup - Full Lifecycle Test${NC}                     ${MAGENTA}║${NC}\n"
    printf "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
}

# Print stage header
print_stage() {
    local stage="$1"
    local stage_start=$(date +%s)
    STAGE_TIMES+=("$stage:$stage_start")

    printf "\n"
    printf "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║${NC} ${YELLOW}%-62s${NC} ${BLUE}║${NC}\n" "$stage"
    printf "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
}

# Print stage completion
stage_complete() {
    local stage="$1"
    local end_time=$(date +%s)
    local start_time=0

    # Find start time for this stage (handle array safely)
    if [[ ${#STAGE_TIMES[@]} -gt 0 ]]; then
        for entry in "${STAGE_TIMES[@]}"; do
            # Extract stage name from entry (everything before last colon)
            local entry_stage="${entry%:*}"
            if [[ "$entry_stage" == "$stage" ]]; then
                start_time="${entry##*:}"
                break
            fi
        done
    fi

    local duration=$((end_time - start_time))
    printf "${GREEN}✓ Stage complete${NC} (${duration}s)\n"
}

# Error handler
error_exit() {
    printf "\n${RED}✗ Error: $1${NC}\n" >&2
    exit 1
}

# Main execution
main() {
    cd "$PROJECT_ROOT"

    print_banner

    printf "${CYAN}Configuration:${NC}\n"
    printf "  Clean start: %s\n" "$CLEAN_START"
    printf "  Run NAS tests: %s\n" "$RUN_NAS_TESTS"
    printf "\n"

    # Stage 1: Clean environment (optional)
    if [[ "$CLEAN_START" == "true" ]]; then
        print_stage "Stage 1: Cleaning Environment"

        printf "Destroying existing VMs...\n"
        vagrant destroy -f primary nas 2>/dev/null || true

        stage_complete "Stage 1: Cleaning Environment"
    fi

    # Stage 2: Start Primary VM
    print_stage "Stage 2: Starting Primary VM"

    printf "Bringing up primary VM...\n"
    vagrant up primary || error_exit "Failed to start primary VM"

    stage_complete "Stage 2: Starting Primary VM"

    # Stage 3: Run Pre-Installation Tests
    print_stage "Stage 3: Pre-Installation Tests"

    printf "Running tests on fresh VM...\n"
    vagrant ssh primary -c "cd ~/docker-stack-backup && sudo ./tests/run-tests.sh" | tee /tmp/pre-install-tests.log || error_exit "Pre-installation tests failed"

    # Extract test summary (strip ANSI color codes and keep only digits)
    PRE_INSTALL_PASSED=$(grep "Passed:" /tmp/pre-install-tests.log | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $3}' | tr -cd '0-9')
    PRE_INSTALL_SKIPPED=$(grep "Skipped:" /tmp/pre-install-tests.log | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $3}' | tr -cd '0-9')
    printf "\n${GREEN}Pre-install: %s passed, %s skipped${NC}\n" "$PRE_INSTALL_PASSED" "$PRE_INSTALL_SKIPPED"

    stage_complete "Stage 3: Pre-Installation Tests"

    # Stage 4: Installation
    print_stage "Stage 4: Installing Docker Stack Backup Manager"

    printf "Running installation...\n"
    vagrant ssh primary -c "cd ~/docker-stack-backup && ./backup-manager.sh install --non-interactive --yes" || error_exit "Installation failed"

    printf "${GREEN}✓ Installation complete${NC}\n"
    stage_complete "Stage 4: Installing Docker Stack Backup Manager"

    # Stage 5: Post-Installation Tests (Before Backup)
    print_stage "Stage 5: Post-Installation Tests (No Backups)"

    printf "Running tests after installation...\n"
    vagrant ssh primary -c "cd ~/docker-stack-backup && sudo ./tests/run-tests.sh" | tee /tmp/post-install-tests.log || error_exit "Post-installation tests failed"

    # Strip ANSI color codes and keep only digits
    POST_INSTALL_PASSED=$(grep "Passed:" /tmp/post-install-tests.log | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $3}' | tr -cd '0-9')
    POST_INSTALL_SKIPPED=$(grep "Skipped:" /tmp/post-install-tests.log | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $3}' | tr -cd '0-9')
    printf "\n${GREEN}Post-install: %s passed, %s skipped${NC}\n" "$POST_INSTALL_PASSED" "$POST_INSTALL_SKIPPED"

    stage_complete "Stage 5: Post-Installation Tests (No Backups)"

    # Stage 6: Create First Backup
    print_stage "Stage 6: Creating First Backup"

    printf "Creating backup...\n"
    vagrant ssh primary -c "cd ~/docker-stack-backup && ./backup-manager.sh backup --non-interactive" || error_exit "Backup creation failed"

    printf "${GREEN}✓ Backup created${NC}\n"
    stage_complete "Stage 6: Creating First Backup"

    # Stage 7: Post-Backup Tests
    print_stage "Stage 7: Post-Backup Tests"

    printf "Running tests after backup...\n"
    vagrant ssh primary -c "cd ~/docker-stack-backup && sudo ./tests/run-tests.sh" | tee /tmp/post-backup-tests.log || error_exit "Post-backup tests failed"

    # Strip ANSI color codes and keep only digits
    POST_BACKUP_PASSED=$(grep "Passed:" /tmp/post-backup-tests.log | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $3}' | tr -cd '0-9')
    POST_BACKUP_SKIPPED=$(grep "Skipped:" /tmp/post-backup-tests.log | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $3}' | tr -cd '0-9')
    printf "\n${GREEN}Post-backup: %s passed, %s skipped${NC}\n" "$POST_BACKUP_PASSED" "$POST_BACKUP_SKIPPED"

    stage_complete "Stage 7: Post-Backup Tests"

    # Stage 8: NAS VM Setup and Tests (Optional)
    if [[ "$RUN_NAS_TESTS" == "true" ]]; then
        print_stage "Stage 8: NAS VM Setup and Testing"

        printf "Bringing up NAS VM...\n"
        vagrant up nas || error_exit "Failed to start NAS VM"

        printf "Waiting for NAS VM to be ready...\n"
        sleep 5

        printf "Running NAS connectivity tests...\n"
        vagrant ssh primary -c "cd ~/docker-stack-backup && sudo ./tests/run-tests.sh 12" | tee /tmp/nas-tests.log || error_exit "NAS tests failed"

        printf "Running end-to-end NAS backup workflow test...\n"
        vagrant ssh primary -c "cd ~/docker-stack-backup && sudo ./tests/12-nas-backup/05-test-nas-backup-e2e.sh" || error_exit "NAS E2E test failed"

        # Strip ANSI color codes and keep only digits
        NAS_PASSED=$(grep "Passed:" /tmp/nas-tests.log | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $3}' | tr -cd '0-9')
        printf "\n${GREEN}NAS tests: %s passed${NC}\n" "$NAS_PASSED"

        stage_complete "Stage 8: NAS VM Setup and Testing"
    fi

    # Stage 9: Final Complete Test Run
    print_stage "Stage 9: Final Complete Test Suite"

    printf "Running complete test suite...\n"
    vagrant ssh primary -c "cd ~/docker-stack-backup && sudo ./tests/run-tests.sh" | tee /tmp/final-tests.log || error_exit "Final tests failed"

    # Strip ANSI color codes and keep only digits
    FINAL_PASSED=$(grep "Passed:" /tmp/final-tests.log | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $3}' | tr -cd '0-9')
    FINAL_FAILED=$(grep "Failed:" /tmp/final-tests.log | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $3}' | tr -cd '0-9')
    FINAL_SKIPPED=$(grep "Skipped:" /tmp/final-tests.log | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $3}' | tr -cd '0-9')

    printf "\n${GREEN}Final results: %s passed, %s failed, %s skipped${NC}\n" "$FINAL_PASSED" "$FINAL_FAILED" "$FINAL_SKIPPED"

    stage_complete "Stage 9: Final Complete Test Suite"

    # Print final summary
    print_final_summary
}

# Print final summary
print_final_summary() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))
    local minutes=$((total_duration / 60))
    local seconds=$((total_duration % 60))

    printf "\n"
    printf "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${MAGENTA}║${NC}  ${CYAN}FULL LIFECYCLE TEST COMPLETE${NC}                                 ${MAGENTA}║${NC}\n"
    printf "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}\n"
    printf "${MAGENTA}║${NC}  ${YELLOW}Test Progression:${NC}                                             ${MAGENTA}║${NC}\n"
    printf "${MAGENTA}║${NC}    Pre-install:  ${GREEN}%-2s passed${NC}, ${YELLOW}%-2s skipped${NC}                        ${MAGENTA}║${NC}\n" "$PRE_INSTALL_PASSED" "$PRE_INSTALL_SKIPPED"
    printf "${MAGENTA}║${NC}    Post-install: ${GREEN}%-2s passed${NC}, ${YELLOW}%-2s skipped${NC}                        ${MAGENTA}║${NC}\n" "$POST_INSTALL_PASSED" "$POST_INSTALL_SKIPPED"
    printf "${MAGENTA}║${NC}    Post-backup:  ${GREEN}%-2s passed${NC}, ${YELLOW}%-2s skipped${NC}                        ${MAGENTA}║${NC}\n" "$POST_BACKUP_PASSED" "$POST_BACKUP_SKIPPED"

    if [[ "$RUN_NAS_TESTS" == "true" ]]; then
        printf "${MAGENTA}║${NC}    NAS tests:    ${GREEN}%-2s passed${NC}                                  ${MAGENTA}║${NC}\n" "${NAS_PASSED:-0}"
    fi

    printf "${MAGENTA}║${NC}                                                                ${MAGENTA}║${NC}\n"
    printf "${MAGENTA}║${NC}  ${YELLOW}Final Results:${NC}                                                ${MAGENTA}║${NC}\n"
    printf "${MAGENTA}║${NC}    Total tests:  %-2s                                          ${MAGENTA}║${NC}\n" "$((FINAL_PASSED + FINAL_FAILED + FINAL_SKIPPED))"
    printf "${MAGENTA}║${NC}    Passed:       ${GREEN}%-2s${NC}                                          ${MAGENTA}║${NC}\n" "$FINAL_PASSED"
    printf "${MAGENTA}║${NC}    Failed:       ${RED}%-2s${NC}                                          ${MAGENTA}║${NC}\n" "$FINAL_FAILED"
    printf "${MAGENTA}║${NC}    Skipped:      ${YELLOW}%-2s${NC}                                          ${MAGENTA}║${NC}\n" "$FINAL_SKIPPED"
    printf "${MAGENTA}║${NC}                                                                ${MAGENTA}║${NC}\n"
    printf "${MAGENTA}║${NC}  Total Duration: ${CYAN}%dm %ds${NC}                                      ${MAGENTA}║${NC}\n" "$minutes" "$seconds"
    printf "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}\n"

    if [[ "$FINAL_FAILED" -eq 0 ]]; then
        printf "\n${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}\n"
        printf "${GREEN}║${NC}  ${GREEN}✓ ALL TESTS PASSED - SYSTEM FULLY VALIDATED!${NC}                 ${GREEN}║${NC}\n"
        printf "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}\n\n"
        return 0
    else
        printf "\n${RED}╔════════════════════════════════════════════════════════════════╗${NC}\n"
        printf "${RED}║${NC}  ${RED}✗ SOME TESTS FAILED - CHECK LOGS ABOVE${NC}                        ${RED}║${NC}\n"
        printf "${RED}╚════════════════════════════════════════════════════════════════╝${NC}\n\n"
        return 1
    fi
}

# Run main
main "$@"
