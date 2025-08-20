# CRUSH.md - Docker Stack Backup Development Guide

## Build/Test Commands

```bash
# Full test suite (creates fresh VMs, runs all 62+ tests)
./dev-test.sh fresh

# Fast test suite (uses existing VMs)
./dev-test.sh run

# Start VMs for manual testing
./dev-test.sh up

# Run single test function (manual execution in VM)
vagrant ssh primary -c "cd /home/vagrant/docker-stack-backup && export DOCKER_BACKUP_TEST=true && source backup-manager.sh && test_backup_creation"

# VM management
./dev-test.sh down      # Suspend VMs
./dev-test.sh destroy   # Destroy VMs completely
./dev-test.sh shell     # Interactive VM access menu
```

## Code Style Guidelines

### Shell Script Standards
- Use `#!/bin/bash` with `set -euo pipefail` for strict error handling
- Functions use snake_case: `install_dependencies()`, `create_backup()`
- Variables use UPPER_CASE for globals: `DEFAULT_PORTAINER_PATH`, `LOG_FILE`
- Local variables use lowercase: `local backup_file="..."`

### Error Handling & Logging
- Use `log()` function with levels: `info()`, `warn()`, `error()`, `success()`
- All errors logged to `/var/log/docker-backup-manager.log`
- Use `die()` for fatal errors that should exit
- Implement `cleanup()` trap for temporary file management

### Function Structure
- Functions start with descriptive comments
- Use `local` for all function variables
- Return meaningful exit codes (0=success, 1=error)
- Validate inputs at function start

### Testing Requirements
- All new features must have corresponding test functions in `dev-test.sh`
- Test functions named `test_feature_name()`
- Use `export DOCKER_BACKUP_TEST=true` for test environment detection
- Mock external dependencies when possible
- Validate both success and failure scenarios