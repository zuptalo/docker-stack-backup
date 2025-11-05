# Docker Stack Backup Manager - Complete Testing Guide

## Overview

This guide explains how to properly test the entire Docker Stack Backup Manager system, including the **end-to-end NAS backup workflow**.

## Understanding the NAS Backup Workflow

### The Real-World Workflow

In production:
1. **Primary Server**: Generates self-contained NAS client script with embedded SSH key
2. **User**: Copies script to NAS machine (manual step)
3. **NAS Machine**: Runs script to pull backups from Primary server
4. **NAS Script**: 
   - Connects back to Primary using embedded SSH key
   - Syncs backups using rsync
   - Applies retention policy (removes old backups)
   - Cleans up temporary SSH keys

### What We Test

Our E2E test validates:
- ✅ Script generation with embedded SSH key
- ✅ Script execution on NAS (via shared mount in test environment)
- ✅ SSH connection from NAS back to Primary
- ✅ Backup synchronization (Primary → NAS)
- ✅ Backup integrity verification
- ✅ Retention cleanup
- ✅ Security (temp key cleanup)

### What We DON'T Test

- ❌ Manual copy step (user's responsibility in production)
  - In our test environment, both VMs mount `~/docker-stack-backup`
  - Script is automatically accessible to NAS VM

## Quick Start - Full Automated Test

```bash
# Run complete lifecycle test (recommended)
./tests/full-lifecycle-test.sh
```

This single command will:
1. Destroy and recreate VMs
2. Install system on Primary
3. Create backups
4. Start NAS VM
5. Run end-to-end NAS backup sync test
6. Execute all 53 tests
7. Display comprehensive summary

**Expected result: 53 passed, 0 failed, 0 skipped** ✅

## Manual Testing Steps

### 1. Fresh VM Tests (21 pass, 32 skip)

```bash
vagrant destroy -f primary
vagrant up primary
vagrant ssh primary -c "cd ~/docker-stack-backup && sudo ./tests/run-tests.sh"
```

**Tests validate:**
- System prerequisites (Ubuntu, sudo, ports, disk space)
- Dependencies availability (curl, jq, dig, rsync)
- Read-only checks (no system modification)

### 2. Post-Installation Tests (41 pass, 12 skip)

```bash
vagrant ssh primary -c "cd ~/docker-stack-backup && ./backup-manager.sh install --non-interactive --yes"
vagrant ssh primary -c "cd ~/docker-stack-backup && sudo ./tests/run-tests.sh"
```

**Tests validate:**
- Docker installation
- User creation (portainer user)
- Network setup
- Portainer deployment
- NPM deployment
- Configuration loading

### 3. Post-Backup Tests (49 pass, 4 skip)

```bash
vagrant ssh primary -c "cd ~/docker-stack-backup && ./backup-manager.sh backup --non-interactive"
vagrant ssh primary -c "cd ~/docker-stack-backup && sudo ./tests/run-tests.sh"
```

**Tests validate:**
- Backup creation
- Backup metadata
- Backup integrity
- Restore prerequisites
- End-to-end backup/restore cycle

### 4. NAS Tests (53 pass, 0 skip)

```bash
vagrant up nas
vagrant ssh primary -c "cd ~/docker-stack-backup && sudo ./tests/run-tests.sh"
```

**Tests validate:**
- NAS connectivity
- NAS script generation
- **End-to-end NAS backup sync workflow**

## Testing the NAS E2E Workflow Manually

### Step-by-Step NAS Test

```bash
# 1. Ensure prerequisites
vagrant up primary nas
vagrant ssh primary -c "cd ~/docker-stack-backup && ./backup-manager.sh install --non-interactive --yes"
vagrant ssh primary -c "cd ~/docker-stack-backup && ./backup-manager.sh backup --non-interactive"

# 2. Run just the NAS E2E test
vagrant ssh primary -c "cd ~/docker-stack-backup && sudo ./tests/12-nas-backup/05-test-nas-backup-e2e.sh"
```

**What happens:**
1. ✓ Generates NAS client script on Primary
2. ✓ Verifies script is accessible on NAS (via shared mount)
3. ✓ Runs script on NAS VM
4. ✓ Script connects back to Primary using embedded SSH key
5. ✓ Syncs backups from Primary to NAS
6. ✓ Verifies backup integrity
7. ✓ Tests retention cleanup
8. ✓ Verifies security (key cleanup)

### Verifying the NAS Sync

```bash
# Check backups on Primary
vagrant ssh primary -c "ls -lh /opt/backup/"

# Check backups on NAS (after running E2E test)
vagrant ssh nas -c "ls -lh /mnt/nas-backup/"

# They should match!
```

## Environment Variables

```bash
# Full lifecycle test options
CLEAN_START=true         # Destroy VMs before testing (default: true)
RUN_NAS_TESTS=true       # Include NAS tests (default: true)
VERBOSE=true             # Show detailed output
STOP_ON_FAILURE=true     # Stop on first failure

# Examples:
RUN_NAS_TESTS=false ./tests/full-lifecycle-test.sh        # Skip NAS (faster)
CLEAN_START=false ./tests/full-lifecycle-test.sh          # Keep VMs
VERBOSE=true STOP_ON_FAILURE=true ./tests/run-tests.sh    # Debug mode
```

## Test Lifecycle Summary

| Stage | Tests | Duration | What's Validated |
|-------|-------|----------|-----------------|
| **Fresh VM** | 21 pass, 32 skip | ~30s | System prerequisites, no artifacts |
| **Post-Install** | 41 pass, 12 skip | ~1.5m | Installation, Docker, users, network |
| **Post-Backup** | 49 pass, 4 skip | ~1.5m | Backup creation, E2E cycle |
| **With NAS** | 53 pass, 0 skip | ~30s | NAS connectivity, E2E sync |

## Troubleshooting

### NAS Test Skips

**Problem**: NAS test shows `SKIP: NAS VM not running`

**Solution**:
```bash
vagrant up nas
vagrant ssh primary -c "ping -c 1 192.168.56.20"  # Verify connectivity
```

### SSH Connection Fails

**Problem**: `Cannot SSH to NAS without password`

**Solution**: This shouldn't happen with Vagrant. Check:
```bash
vagrant ssh nas -c "systemctl status ssh"
```

### Backups Not Syncing

**Problem**: E2E test fails at backup sync step

**Debug**:
```bash
# Run NAS script manually with verbose output
vagrant ssh primary -c "cd ~/docker-stack-backup && printf '192.168.56.20\nvagrant\n/mnt/nas-backup\n/tmp/nas-test.sh\n30\n' | ./backup-manager.sh nas-backup"
vagrant ssh nas -c "/tmp/nas-test.sh"  # Run script on NAS
```

## CI/CD Integration

```yaml
name: Full Test Suite
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v3
      - name: Setup
        run: brew install --cask vagrant virtualbox
      - name: Run Tests
        run: ./tests/full-lifecycle-test.sh
```

## Performance Benchmarks

- Full lifecycle (with NAS): ~8-10 minutes
- Full lifecycle (without NAS): ~6-8 minutes
- Single test category: ~5-30 seconds
- Individual test: ~1-5 seconds

## Next Steps

After all tests pass:
1. Review test logs in `/tmp/*-tests.log`
2. Check VM status: `vagrant status`
3. Test manual operations on Primary VM
4. Test NAS script in real-world scenario
5. Clean up: `vagrant destroy -f`
