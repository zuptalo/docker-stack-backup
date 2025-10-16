# Docker Stack Backup - Test Suite

## Overview

Comprehensive test suite with **52 tests** covering all aspects of the Docker Stack Backup Manager, including system preparation, dependencies, configuration, networking, backup/restore operations, and disaster recovery scenarios.

## Test Status

✅ **50/52 tests passing** (2 skipped)
⏱️ **~10 seconds** total execution time

## Quick Start

```bash
# Run all tests
sudo ./tests/run-tests.sh

# Run specific category
sudo ./tests/run-tests.sh 08-backup

# Run individual test
sudo ./tests/08-backup/04-test-stack-states-capture.sh
```

## Test Categories

### System Preparation (6 tests)
- Ubuntu version check
- Sudo privileges verification
- User permissions validation
- Port availability
- Internet connectivity
- Disk space requirements

### Dependencies (7 tests)
- curl, jq, dig, rsync installation
- Docker and Docker Compose verification
- All dependencies validation

### User Management (4 tests)
- Portainer user creation
- Docker group membership
- Sudo configuration
- Log file permissions

### Configuration (3 tests)
- Default config file existence
- Configuration loading
- Path validation

### Network (3 tests)
- Docker network creation
- DNS resolution
- Port bindings

### Portainer (3 tests)
- Container status
- API accessibility
- Endpoint configuration

### NPM - Nginx Proxy Manager (2 tests)
- Stack verification
- API accessibility

### Backup (5 tests)
- **01-check-backup-files-exist**: Verifies backup files are created
- **02-check-backup-metadata**: Validates backup metadata format
- **03-test-backup-integrity**: Tests backup archive integrity
- **04-test-stack-states-capture**: Verifies `stack_states.json` with all stack details
- **05-test-stack-data-backup**: Comprehensive data backup verification
  - Portainer data directory backup
  - Portainer compose directory backup
  - NPM data and database backup
  - Custom stack data backup
  - Directory structure preservation

### Restore (8 tests)
- **01-check-restore-command**: Command availability
- **02-test-list-backups**: Backup listing functionality
- **03-test-backup-selection**: Backup selection logic
- **04-test-backup-extraction**: Backup extraction process
- **05-test-service-status**: Pre-restore service status
- **06-test-restore-prerequisites**: Prerequisites validation
- **07-test-compose-content-parsing**: Double-encoded JSON parsing (bug fix)
- **08-test-multi-stack-restore**: Multi-stack restoration verification
  - All stacks restored with correct status
  - Stack containers running
  - Compose content preserved
  - Stack names matching

### Scheduling (1 test)
- Cron configuration validation

### NAS Backup (4 tests)
- NAS command availability
- SSH key validation
- NAS script generation
- NAS connectivity

### Update (2 tests)
- Update command availability
- Version format validation

### Error Handling (2 tests)
- Error function availability
- Dependency validation

### Logging (1 test)
- Log file creation and permissions

### Integration (1 test)
- Overall system health check

## Disaster Recovery Testing

### Manual Disaster Recovery Verification

The backup/restore functionality has been validated through comprehensive disaster recovery testing:

1. ✅ **Initial Setup**: Fresh VM with Portainer + NPM
2. ✅ **Stack Deployment**: Dashboard and nginx-web stacks via Portainer API
3. ✅ **Proxy Configuration**: 4 NPM proxy hosts created
4. ✅ **Backup Creation**: Full backup with all 3 stacks (30KB)
5. ✅ **NAS Transfer**: Backup copied to NAS VM
6. ✅ **Disaster Simulation**: Primary VM completely destroyed
7. ✅ **Recovery**: Fresh setup + restore from NAS backup
8. ✅ **Verification**: All 4 services accessible with preserved data

**Key Validations:**
- All stacks auto-start after restore (Status=1)
- NPM proxy hosts restored (4/4)
- Custom stack data preserved (index.html verified)
- Stack metadata (compose files) correctly restored
- Containers running and serving content

## Test Environment Setup

### Prerequisites

1. **Vagrant VMs** (optional, for full testing):
   ```bash
   vagrant up primary
   vagrant up nas
   ```

2. **Base Setup**:
   ```bash
   cd /home/vagrant/docker-stack-backup
   sudo ./backup-manager.sh --yes setup
   ```

### Test Snapshots

Create snapshots to quickly reset test environment:

```bash
# After initial setup
./tests/snapshot.sh create base-setup

# Restore to clean state
./tests/snapshot.sh restore base-setup
```

## Writing Tests

### Test Structure

```bash
#!/bin/bash
# Test: Description of what this test validates

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/test-utils.sh"

setup_test_env "${BASH_SOURCE[0]}"
print_test_header "Test Name"

# Test implementation
printf "\n${CYAN}Testing something:${NC}\n"

if [[ condition ]]; then
    assert_true "0" "Success message"
else
    assert_true "1" "Failure message"
fi

print_test_summary
```

### Available Assertions

- `assert_true "0" "message"` - Assert condition passed
- `assert_true "1" "message"` - Assert condition failed (will fail test)
- `assert_file_exists "/path" "message"` - Assert file exists
- `skip_test "reason"` - Skip test with reason
- `print_test_result "PASS|FAIL|WARN|INFO" "message"` - Custom result

### Important Notes

**Avoid pipefail issues with grep:**
```bash
# DON'T do this (will fail with pipefail):
if tar -tzf file.tar.gz | grep -q "pattern"; then

# DO this instead:
if tar -tzf file.tar.gz 2>/dev/null | grep "pattern" >/dev/null 2>&1; then
```

**Handle double-encoded JSON:**
```bash
# compose_file_content is a stringified JSON object
# Use jq's has() instead of trying to extract:
HAS_COMPOSE=$(echo "$stack" | jq 'has("compose_file_content")')
```

## Continuous Integration

Tests are designed to run in CI/CD pipelines:

```yaml
# Example GitHub Actions
- name: Run Tests
  run: |
    cd docker-stack-backup
    sudo ./tests/run-tests.sh
```

## Troubleshooting

### Tests Failing After Changes

1. Check if test fixtures need updating
2. Verify test environment is clean
3. Review recent code changes for breaking changes

### Skipped Tests

Some tests are skipped when:
- Required services not running
- Prerequisites not met
- Test environment incomplete

Use `print_test_result "INFO" "message"` for expected skips.

## Future Test Improvements

- [ ] Add end-to-end automated disaster recovery test
- [ ] Performance benchmarking tests
- [ ] Concurrent backup/restore stress tests
- [ ] Network failure simulation tests
- [ ] Corrupted backup handling tests

## Contributing

When adding new features:

1. Write tests first (TDD)
2. Ensure tests pass: `sudo ./tests/run-tests.sh`
3. Update this documentation
4. Create snapshots if test environment changed
