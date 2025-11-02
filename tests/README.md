# Docker Stack Backup - Test Suite

## Quick Start

```bash
# Run all tests (from project root)
sudo ./tests/run-tests.sh

# Run specific category
sudo ./tests/run-tests.sh 08-backup

# Run individual test
sudo ./tests/08-backup/04-test-stack-states-capture.sh
```

## Test Status

✅ **All core tests passing** (some may be skipped based on environment)
📊 **53 total tests** across 16 categories

## Test Organization

```
tests/
├── run-tests.sh              # Main test runner
├── lib/
│   └── test-utils.sh         # Shared test utilities
├── 01-system-preparation/    # System checks (6 tests)
├── 02-dependencies/          # Dependency validation (7 tests)
├── 03-user-management/       # User & permissions (4 tests)
├── 04-configuration/         # Config validation (3 tests)
├── 05-network/               # Network setup (3 tests)
├── 06-portainer/             # Portainer checks (3 tests)
├── 07-npm/                   # NPM checks (2 tests)
├── 08-backup/                # Backup functionality (5 tests)
├── 09-restore/               # Restore functionality (8 tests)
├── 10-end-to-end/            # E2E tests (experimental)
├── 11-scheduling/            # Cron scheduling (1 test)
├── 12-nas-backup/            # NAS operations (4 tests)
├── 13-update/                # Update checks (2 tests)
├── 14-error-handling/        # Error handling (2 tests)
├── 15-logging/               # Logging (1 test)
└── 16-integration/           # Integration tests (1 test)
```

## Key Tests

### Backup Tests (Category 08)

- **Stack States Capture**: Verifies all stack metadata is captured
- **Stack Data Backup**: Validates data directory backup (Portainer, NPM, custom stacks)

### Restore Tests (Category 09)

- **Compose Content Parsing**: Validates double-encoded JSON parsing (bug fix)
- **Multi-Stack Restore**: Verifies multiple stacks restore and auto-start correctly

## Test Utilities

Located in `lib/test-utils.sh`:

- `setup_test_env` - Initialize test environment
- `print_test_header` - Display test header
- `assert_true` - Basic assertion
- `assert_file_exists` - File existence check
- `skip_test` - Skip test with reason
- `print_test_result` - Custom result output
- `print_test_summary` - Display test results

## Writing Tests

See [../TESTING.md](../TESTING.md) for detailed guide on writing tests.

## Common Patterns

### Pipefail-Safe Grep
```bash
# Use this pattern to avoid pipefail issues:
if tar -tzf "$file" 2>/dev/null | grep "pattern" >/dev/null 2>&1; then
```

### Double-Encoded JSON
```bash
# Handle compose_file_content (stringified JSON):
HAS_COMPOSE=$(echo "$stack" | jq 'has("compose_file_content")')
```

### Error Handling
```bash
# Disable errexit for commands that might fail:
set +e
command_that_might_fail
EXIT_CODE=$?
set -e
```
