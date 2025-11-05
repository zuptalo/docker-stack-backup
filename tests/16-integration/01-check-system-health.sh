#!/bin/bash
# Test: Check Overall System Health

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Check Overall System Health"

# Check if Docker is installed first
if ! command -v docker >/dev/null 2>&1; then
    print_test_result "SKIP" "Docker not installed - skipping system health tests"
    print_test_summary
    exit 0
fi

# Test 1: Check Docker is running
printf "\n${CYAN}Checking Docker status:${NC}\n"

if docker info >/dev/null 2>&1; then
    assert_true "0" "Docker daemon is running"

    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    printf "  Docker version: %s\n" "$DOCKER_VERSION"
else
    print_test_result "SKIP" "Docker daemon not running - skipping system health tests"
    print_test_summary
    exit 0
fi

# Test 2: Check running containers
printf "\n${CYAN}Checking running containers:${NC}\n"

CONTAINER_COUNT=$(docker ps -q 2>/dev/null | wc -l)
printf "  Running containers: %d\n" "$CONTAINER_COUNT"

if [[ $CONTAINER_COUNT -gt 0 ]]; then
    assert_true "0" "At least one container is running"

    docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -v "^NAMES" | while IFS= read -r line; do
        printf "    %s\n" "$line"
    done
else
    print_test_result "WARN" "No containers running"
fi

# Test 3: Check Portainer is accessible
printf "\n${CYAN}Checking Portainer accessibility:${NC}\n"

if curl -sf "http://localhost:9000/api/status" >/dev/null 2>&1; then
    assert_true "0" "Portainer API is accessible"
else
    print_test_result "WARN" "Portainer API not accessible"
fi

# Test 4: Check NPM is accessible
printf "\n${CYAN}Checking NPM accessibility:${NC}\n"

if curl -sf "http://localhost:81" >/dev/null 2>&1; then
    assert_true "0" "NPM admin interface is accessible"
else
    print_test_result "WARN" "NPM not accessible"
fi

# Test 5: Check backups exist
printf "\n${CYAN}Checking backup files:${NC}\n"

if [[ -f "/etc/docker-backup-manager.conf" ]]; then
    source "/etc/docker-backup-manager.conf"

    BACKUP_COUNT=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | wc -l)
    printf "  Backup files: %d\n" "$BACKUP_COUNT"

    if [[ $BACKUP_COUNT -gt 0 ]]; then
        assert_true "0" "Backup files exist"

        # Show most recent backup
        LATEST=$(find "$BACKUP_PATH" -name "docker_backup_*.tar.gz" 2>/dev/null | sort -r | head -1)
        if [[ -n "$LATEST" ]]; then
            AGE_SEC=$(( $(date +%s) - $(stat -c "%Y" "$LATEST" 2>/dev/null || stat -f "%m" "$LATEST" 2>/dev/null) ))
            AGE_MIN=$((AGE_SEC / 60))
            printf "    Latest: %s (%d minutes old)\n" "$(basename "$LATEST")" "$AGE_MIN"
        fi
    else
        print_test_result "WARN" "No backup files found"
    fi
fi

# Test 6: Check scheduled backups
printf "\n${CYAN}Checking scheduled backups:${NC}\n"

if sudo -u portainer crontab -l 2>/dev/null | grep -q "docker-backup-manager.sh backup"; then
    assert_true "0" "Backup schedule is configured"

    SCHEDULE=$(sudo -u portainer crontab -l 2>/dev/null | grep "docker-backup-manager.sh backup")
    printf "  Schedule: %s\n" "$SCHEDULE"
else
    print_test_result "WARN" "No scheduled backups configured"
fi

# Test 7: Check disk space
printf "\n${CYAN}Checking disk space:${NC}\n"

DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
DISK_USED=$(df -h / | awk 'NR==2 {print $5}')

printf "  Available: %s\n" "$DISK_AVAIL"
printf "  Used: %s\n" "$DISK_USED"

# Extract percentage
USED_PCT=$(echo "$DISK_USED" | tr -d '%')

if [[ $USED_PCT -lt 90 ]]; then
    assert_true "0" "Disk space is adequate (< 90% used)"
else
    print_test_result "WARN" "Disk space is low: $DISK_USED used"
fi

# Test 8: System summary
printf "\n${CYAN}System Summary:${NC}\n"

printf "  Hostname: %s\n" "$(hostname)"
printf "  Uptime: %s\n" "$(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}')"
printf "  Load Average: %s\n" "$(uptime | awk -F'load average:' '{print $2}')"

assert_true "0" "System health check complete"

print_test_summary
