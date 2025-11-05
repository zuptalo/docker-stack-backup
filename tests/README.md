# Docker Stack Backup - Test Suite

## Overview

This directory contains the comprehensive test suite for the Docker Stack Backup Manager, with **53 tests** covering all aspects of the system, including system preparation, dependencies, configuration, networking, backup/restore operations, and disaster recovery scenarios.

## Test Status

✅ **All core tests passing** (some may be skipped based on environment)
⏱️ **~10 seconds** total execution time on a fresh installation.

## Quick Start

```bash
# Run all tests (from project root)
sudo ./tests/run-tests.sh

# Run a specific category of tests (e.g., backup)
sudo ./tests/run-tests.sh 08

# Run an individual test file
sudo ./tests/08-backup/04-test-stack-states-capture.sh
```

## Test Organization

The test suite is organized into categories by number. The `run-tests.sh` script discovers and runs them in order.

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
├── 10-end-to-end/            # E2E tests (1 test)
├── 11-scheduling/            # Cron scheduling (1 test)
├── 12-nas-backup/            # NAS operations (4 tests)
├── 13-update/                # Update checks (2 tests)
├── 14-error-handling/        # Error handling (2 tests)
├── 15-logging/               # Logging (1 test)
└── 16-integration/           # Integration tests (1 test)
```

## Writing and Understanding Tests

For a complete guide on the testing infrastructure, how to write new tests, and detailed explanations of disaster recovery testing, please see the main testing guide:

- **[TESTING.md](TESTING.md)**