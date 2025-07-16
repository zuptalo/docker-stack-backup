# Docker Stack Backup - TODO List

## Implementation Progress

This document tracks the implementation of missing features and improvements identified by comparing the current codebase against the requirements document.

---

## Phase 1: Critical Missing Functionality (High Priority)

### ✅ **1. DNS Verification in Setup Command**
- **Status**: ✅ Completed
- **Priority**: High
- **Description**: Implement DNS verification during setup to check domain resolution, detect public IP, provide DNS record instructions, and offer HTTP-only fallback
- **Requirements**:
  - ✅ Use `dig` or `nslookup` to verify domain resolution
  - ✅ Detect server's public IP address
  - ✅ Provide DNS record instructions to user
  - ✅ Offer HTTP-only fallback if DNS not ready
  - ✅ Warn about SSL certificate requirements
- **Test Cases Implemented**:
  - ✅ Test DNS resolution check
  - ✅ Test public IP detection
  - ✅ Test DNS verification skip in test environment
  - ✅ Test SSL certificate skip flag functionality
  - ✅ Test DNS verification with misconfigured DNS (real-world scenario)
- **Implementation Details**:
  - Added `get_public_ip()` function with multiple IP detection methods (curl, wget fallbacks)
  - Added `check_dns_resolution()` function using dig/nslookup with proper error handling
  - Added `verify_dns_and_ssl()` function with interactive user flow and three options
  - Added `setup_log_file()` function to fix permission issues
  - Integrated DNS verification into setup command flow after configuration
  - Added `SKIP_SSL_CERTIFICATES` flag for HTTP-only fallback mode
  - Modified SSL certificate requests to respect the skip flag in both proxy host functions
  - Enhanced script to allow sourcing for testing without triggering main execution
  - Added comprehensive test coverage (5 new tests, total now 27 tests)
  - Fixed log file permission issues that were causing test failures

### ✅ **2. Update Command Implementation**
- **Status**: ✅ Completed
- **Priority**: High
- **Description**: Implement complete update command with internet connectivity check, version comparison, dual update options, and backup current version before update
- **Requirements**:
  - ✅ Check internet connectivity to GitHub
  - ✅ Compare current vs latest version
  - ✅ Dual update options (user script + system script)
  - ✅ Backup current version before updating
  - ✅ Handle update failures gracefully
- **Test Cases Implemented**:
  - ✅ Test internet connectivity check
  - ✅ Test version comparison logic (fixed exit code handling)
  - ✅ Test dual update process
  - ✅ Test update command help
- **Implementation Details**:
  - Added `check_internet_connectivity()` function with GitHub connectivity test
  - Added `get_latest_version()` function to fetch latest release from GitHub API
  - Added `compare_versions()` function with proper semantic version comparison
  - Added `backup_current_version()` function to backup before updating
  - Added `download_latest_version()` and `update_script_file()` functions
  - Added complete `update_script()` function with user interaction for dual update options
  - Added update command to main dispatcher with proper help text
  - Fixed Version Comparison test by handling `set -e` interaction with function return codes
  - Added 4 comprehensive test cases for update functionality (total now 31 tests)

### ✅ **3. Fix VM Startup Issue in Development Environment**
- **Status**: ✅ Completed
- **Priority**: High
- **Description**: Fix issue where `./dev-test.sh up` doesn't start VMs properly and improve development workflow
- **Requirements**:
  - ✅ Investigate why `smart_start_vms()` function isn't working correctly
  - ✅ Fix VM startup logic to ensure both VMs start properly
  - ✅ Test that `./dev-test.sh up` command works as expected
  - ✅ Implement suspend/resume for faster development cycles
  - ✅ Add intelligent state handling for different VM states
- **Implementation Details**:
  - Root cause identified: `vagrant status` parsing with `set -euo pipefail` causing hangs
  - Implemented simplified `smart_start_vms()` function using try-resume-first approach
  - Added `./dev-test.sh resume` command for direct VM resuming
  - Changed `./dev-test.sh down` to use `vagrant suspend` instead of `vagrant halt`
  - Updated help documentation with new workflow and commands
- **Test Results**: ✅ All scenarios tested and working:
  - ✅ VM startup from suspended state (fast resume)
  - ✅ VM startup from poweroff state (full start)
  - ✅ VM startup when already running (graceful handling)
  - ✅ Suspend/resume workflow for faster development cycles

### ✅ **4. Path Migration in Config Command**
- **Status**: ✅ Completed
- **Priority**: High
- **Description**: Implement path migration functionality in config command - inventory stacks, warn about complexity, pre-migration backup, move data, update configurations
- **Requirements**:
  - ✅ Inventory deployed stacks via Portainer API
  - ✅ Warn about complexity with additional stacks
  - ✅ Create pre-migration backup
  - ✅ Move data folders to new paths
  - ✅ Update stack configurations with new paths
  - ✅ Validate all services restart successfully
- **Implementation Details**:
  - Enhanced `configure_paths()` function to detect existing installations
  - Added comprehensive `migrate_paths()` function with interactive UI
  - Implemented `perform_path_migration()` with 6-step process
  - Added `get_stack_inventory()` for detailed Portainer API integration
  - Added `create_migration_backup()` for comprehensive pre-migration backups
  - Added `migrate_data_folders()` with proper permission preservation
  - Added `update_configurations_for_migration()` for config updates
  - Added `restart_and_validate_services()` with API-based service management
  - Added rollback information generation for recovery scenarios
- **Test Cases Implemented**:
  - ✅ Test config command with existing installation detection
  - ✅ Test path migration validation logic
  - ✅ Test stack inventory API functionality
  - ✅ Test migration backup creation
  - ✅ Test configuration updates after migration
- **Manual Verification**: ✅ Confirmed migration mode detection and interactive flow work correctly

### ✅ **5. Dual Backup Approach for Reliability**
- **Status**: ✅ Completed
- **Priority**: High
- **Description**: Add metadata file generation for ownership/permissions alongside tar archive to ensure 100% reliability
- **Requirements**:
  - ✅ Generate metadata file with detailed ownership/permissions
  - ✅ Include metadata file in backup archive
  - ✅ Use metadata file during restore process
  - ✅ Maintain tar.gz as primary method with metadata as backup
- **Implementation Details**:
  - Added `generate_backup_metadata()` function to capture system information, paths, and detailed permissions
  - Enhanced `create_backup()` to generate and include metadata file in backup archives
  - Added `restore_using_metadata()` function to restore permissions and detect architecture mismatches
  - Integrated metadata generation into backup process and metadata usage into restore process
  - Added architecture detection and compatibility warnings during restore
  - Supports graceful fallback when metadata is not available (backwards compatibility)
- **Test Cases Implemented**:
  - ✅ Test metadata file generation with proper JSON structure
  - ✅ Test backup creation with metadata file included
  - ✅ Test restore functionality with metadata file usage
  - ✅ Test architecture detection and mismatch warnings
  - ✅ Test permission restoration from metadata
- **Manual Verification**: ✅ Confirmed backup archives contain metadata files with complete system information

### 🔴 **6. Architecture Detection in Restore Process**
- **Status**: ❌ Not Started
- **Priority**: High
- **Description**: Detect CPU architecture mismatch and warn user about potential image compatibility issues
- **Requirements**:
  - Detect current system architecture
  - Store architecture info in backup metadata
  - Compare architectures during restore
  - Warn user about potential Docker image incompatibilities
- **Test Cases Needed**:
  - Test architecture detection
  - Test architecture comparison
  - Test warning display for mismatches

---

## Phase 2: Enhanced Testing (High Priority)

### 🔴 **7. Comprehensive Config Command Tests**
- **Status**: ❌ Not Started
- **Priority**: High
- **Description**: Add test cases for config command including interactive configuration, current state display, and path migration scenarios
- **Test Cases Needed**:
  - `test_config_command_interactive()`
  - `test_config_migration_with_existing_stacks()`
  - `test_config_validation()`
  - `test_config_rollback_on_failure()`

### 🔴 **8. Comprehensive Restore Functionality Tests**
- **Status**: ❌ Not Started
- **Priority**: High
- **Description**: Add test cases for restore functionality including backup selection, stack state restoration, and permission preservation
- **Test Cases Needed**:
  - `test_restore_backup_selection()`
  - `test_restore_with_stack_state()`
  - `test_restore_permission_preservation()`
  - `test_restore_cross_architecture_warning()`

### 🔴 **9. API Integration Tests**
- **Status**: ❌ Not Started
- **Priority**: High
- **Description**: Add comprehensive API integration tests for Portainer API authentication, stack operations, and nginx-proxy-manager API interactions
- **Test Cases Needed**:
  - `test_portainer_api_authentication()`
  - `test_stack_state_capture()`
  - `test_stack_recreation_from_backup()`
  - `test_npm_api_configuration()`

---

## Phase 3: Functional Improvements (Medium Priority)

### 🔴 **10. Fix Hardcoded Credentials**
- **Status**: ❌ Not Started
- **Priority**: Medium
- **Description**: Use admin@domain.com format with user's actual domain instead of hardcoded values
- **Current Issue**: Lines 608, 610, 388-392 use hardcoded credentials instead of domain-based ones
- **Requirements**:
  - Use `admin@${DOMAIN_NAME}` format
  - Maintain `AdminPassword123!` as password
  - Update both Portainer and NPM credential generation
- **Test Cases Needed**:
  - Test credential format with various domains
  - Test credential storage and retrieval

### 🔴 **11. Help Command for Bare Script Execution**
- **Status**: ❌ Not Started
- **Priority**: Medium
- **Description**: Show usage when no arguments provided to the script
- **Requirements**:
  - Show help output when script run without arguments
  - Include version information
  - Include usage examples
- **Test Cases Needed**:
  - `test_help_display_no_arguments()`
  - `test_help_includes_version()`

### 🔴 **12. Custom Cron Expression Support**
- **Status**: ❌ Not Started
- **Priority**: Medium
- **Description**: Allow users to specify custom cron schedules beyond predefined options in schedule command
- **Requirements**:
  - Add option for custom cron expression input
  - Validate cron expression format
  - Provide examples of valid cron expressions
- **Test Cases Needed**:
  - `test_custom_cron_expression()`
  - `test_cron_expression_validation()`

### 🔴 **13. Enhanced Stack State Capture**
- **Status**: ❌ Not Started
- **Priority**: Medium
- **Description**: Ensure complete stack configurations, environment variables, and stack-level settings are captured
- **Requirements**:
  - Capture complete compose YAML files
  - Capture environment variables set in Portainer UI
  - Capture stack-level settings (auto-update policies, etc.)
  - Store in structured format for reliable restoration
- **Test Cases Needed**:
  - `test_complete_stack_state_capture()`
  - `test_stack_environment_variables()`
  - `test_stack_settings_preservation()`

---

## Phase 4: Enhanced Testing Coverage (Medium Priority)

### 🔴 **14. Error Handling Tests**
- **Status**: ❌ Not Started
- **Priority**: Medium
- **Description**: Add comprehensive error handling tests for various failure scenarios
- **Test Cases Needed**:
  - `test_docker_daemon_failure()`
  - `test_api_service_unavailable()`
  - `test_insufficient_permissions()`
  - `test_disk_space_exhaustion()`

### 🔴 **15. Security and Permissions Tests**
- **Status**: ❌ Not Started
- **Priority**: Medium
- **Description**: Add comprehensive security and permissions testing
- **Test Cases Needed**:
  - `test_ssh_key_restrictions()`
  - `test_backup_file_permissions()`
  - `test_portainer_user_isolation()`
  - `test_credential_file_security()`

### 🔴 **16. Enhanced Integration Tests**
- **Status**: ❌ Not Started
- **Priority**: Medium
- **Description**: Add comprehensive integration tests for end-to-end scenarios
- **Test Cases Needed**:
  - `test_full_backup_restore_cycle()`
  - `test_multi_stack_backup_scenario()`
  - `test_retention_policy_enforcement()`
  - `test_cron_job_execution()`

---

## Phase 5: Quality Improvements (Low Priority)

### 🔴 **17. Improved Error Handling and API Fallbacks**
- **Status**: ❌ Not Started
- **Priority**: Low
- **Description**: Add graceful handling for API failures and service unavailability
- **Requirements**:
  - Implement retry logic for API calls
  - Provide fallback methods when APIs unavailable
  - Better error messages with recovery suggestions

### 🔴 **18. Enhanced Post-Operation Validation**
- **Status**: ❌ Not Started
- **Priority**: Low
- **Description**: Enhance validation after backup, restore, and configuration operations
- **Requirements**:
  - Verify all services are accessible after operations
  - Check service health endpoints
  - Validate data integrity after restore

### 🔴 **19. Version Information in Help Output**
- **Status**: ❌ Not Started
- **Priority**: Low
- **Description**: Include version and enhanced usage examples in help display
- **Requirements**:
  - Show version information in help
  - Include practical usage examples
  - Add links to documentation

---

## Implementation Guidelines

### For Each Item:
1. **Code Implementation**: Update `backup-manager.sh` with new functionality
2. **Test Implementation**: Add corresponding test cases to `dev-test.sh`
3. **Testing**: Run `./dev-test.sh fresh` to validate implementation
4. **Documentation**: Update this TODO.md with completion status

### Testing Strategy:
- **Primary**: Vagrant-based testing for realistic environment validation
- **Secondary**: Consider BATS for unit testing individual functions
- **Validation**: Each feature must pass comprehensive tests before moving to next item

### Status Legend:
- ❌ **Not Started**: No work done
- 🔄 **In Progress**: Currently being implemented
- ✅ **Completed**: Implementation done and tested
- 🧪 **Testing**: Implementation done, testing in progress
- 📝 **Review**: Ready for review and validation

---

## Phase 6: Real-World User Issues (Critical Priority)

### ✅ **20. Missing jq Dependency Auto-Installation**
- **Status**: ✅ Completed (Already Working)
- **Priority**: Critical
- **Description**: Script fails on fresh Ubuntu systems because jq is not automatically installed
- **Requirements**:
  - ✅ Detect missing jq dependency during setup
  - ✅ Automatically install jq during setup process
  - ✅ Provide clear error message with installation instructions if auto-install fails
- **Impact**: Blocks all functionality on fresh systems
- **Implementation Details**:
  - Already implemented in `install_dependencies()` function (lines 121-192)
  - Called at the beginning of every major command
  - Automatically detects missing tools (curl, wget, jq)
  - Auto-installs in test environment, prompts user in production
  - Comprehensive error handling and verification
- **Test Results**: ✅ Verified working in fresh VM environment

### ✅ **21. Interactive Command Timeout Issues**
- **Status**: ✅ Completed
- **Priority**: High
- **Description**: Commands hang indefinitely waiting for user input without timeout or non-interactive options
- **Requirements**:
  - ✅ Add timeout mechanism for interactive prompts
  - ✅ Implement non-interactive mode flags (e.g., `--yes`, `--default`)
  - ✅ Add environment variable support for non-interactive usage
  - ✅ Provide clear progress indicators during long operations
- **Affected Commands**: setup, restore, schedule, config
- **Impact**: Poor user experience, especially in automation scenarios
- **Implementation Details**:
  - Added `prompt_user()` and `prompt_yes_no()` helper functions with timeout support
  - Implemented command-line flags: `--yes`, `--non-interactive`, `--quiet`, `--timeout=SECONDS`
  - Added environment variable support: `NON_INTERACTIVE`, `AUTO_YES`, `QUIET_MODE`, `PROMPT_TIMEOUT`
  - Updated key interactive prompts throughout the script to use new helper functions
  - Added comprehensive test coverage with 3 new test functions
- **Test Results**: ✅ All 3 new tests passing (Prompt Timeout, Environment Variables, Flag Parsing)

### 🔴 **22. DNS Verification Hang During Setup**
- **Status**: ❌ Not Started
- **Priority**: High
- **Description**: Setup command hangs during DNS verification phase with no timeout
- **Requirements**:
  - Add timeout for DNS resolution checks
  - Implement retry mechanism with exponential backoff
  - Allow skipping DNS verification with command-line flag
  - Provide clear messaging about DNS verification status
- **Impact**: Setup process cannot complete reliably

### 🔴 **23. Restore Permission Failures**
- **Status**: ❌ Not Started
- **Priority**: High
- **Description**: Restore process fails with multiple permission errors when extracting backups
- **Requirements**:
  - Fix permission handling during backup extraction
  - Implement proper sudo escalation for restore operations
  - Add validation of extracted files after restore
  - Provide rollback mechanism if restore fails
- **Impact**: Restore functionality is broken, defeating the purpose of backups

### 🔴 **24. Missing SSH Key Setup During Installation**
- **Status**: ❌ Not Started
- **Priority**: Medium
- **Description**: generate-nas-script fails because SSH keys are not properly set up during initial setup
- **Requirements**:
  - Ensure SSH key generation during setup process
  - Add SSH key validation in setup verification
  - Provide manual SSH key setup instructions if auto-setup fails
  - Test SSH connectivity during setup process
- **Impact**: NAS backup functionality unusable

### 🔴 **25. Non-Interactive Mode Support**
- **Status**: ❌ Not Started
- **Priority**: Medium
- **Description**: No support for automation-friendly non-interactive execution
- **Requirements**:
  - Add `--yes` flag for automatic confirmation
  - Add `--config-file` option for non-interactive setup
  - Add `--quiet` flag for minimal output
  - Support environment variable configuration
- **Impact**: Cannot be used in automation scripts or CI/CD pipelines

### 🔴 **26. Command-Specific Help and Error Messages**
- **Status**: ❌ Not Started
- **Priority**: Medium
- **Description**: Commands provide generic help instead of context-specific guidance
- **Requirements**:
  - Add `--help` flag support for individual commands
  - Provide command-specific error messages
  - Include usage examples for complex commands
  - Add troubleshooting tips for common failures
- **Impact**: Poor user experience when commands fail

### 🔴 **27. Dependency Installation Automation**
- **Status**: ❌ Not Started
- **Priority**: Medium
- **Description**: Script should automatically install required dependencies during setup
- **Requirements**:
  - Auto-install jq, curl, wget during setup
  - Detect and install missing Docker dependencies
  - Provide manual installation instructions if auto-install fails
  - Add dependency validation after installation
- **Impact**: Reduces setup friction for new users

### 🔴 **28. Better Error Recovery and Rollback**
- **Status**: ❌ Not Started
- **Priority**: Medium
- **Description**: When operations fail, there's no automatic cleanup or rollback mechanism
- **Requirements**:
  - Implement transaction-like operations with rollback
  - Add cleanup mechanism for failed operations
  - Provide recovery instructions for common failure scenarios
  - Add validation steps after critical operations
- **Impact**: Failed operations can leave system in inconsistent state

### 🔴 **29. Improved Progress Feedback**
- **Status**: ❌ Not Started
- **Priority**: Low
- **Description**: Long-running operations provide minimal feedback to users
- **Requirements**:
  - Add progress bars or spinners for long operations
  - Provide estimated time remaining for backups/restores
  - Add verbose mode for detailed operation logging
  - Implement real-time status updates during critical operations
- **Impact**: Poor user experience during long operations

---

## Next Steps

**CRITICAL**: Address **Phase 6: Real-World User Issues** first, as these are blockers for actual usage:

**Immediate Priority (Critical)**:
1. **Item 20 (Missing jq Dependency)** - Blocks all functionality on fresh systems
2. **Item 21 (Interactive Command Timeouts)** - Prevents reliable automation
3. **Item 22 (DNS Verification Hang)** - Blocks setup completion
4. **Item 23 (Restore Permission Failures)** - Breaks core backup/restore functionality

**High Priority**:
5. **Item 24 (Missing SSH Key Setup)** - Breaks NAS backup functionality
6. **Item 25 (Non-Interactive Mode)** - Essential for automation
7. **Item 26 (Command-Specific Help)** - Critical for user experience

**Medium Priority**:
8. **Item 27 (Dependency Installation)** - Reduces setup friction
9. **Item 28 (Error Recovery)** - Prevents system inconsistency
10. **Item 29 (Progress Feedback)** - Improves user experience

**Implementation approach**: Focus on **Phase 6 Real-World Issues** before continuing with other phases, as these are fundamental blockers for production usage.

**Testing validation**: Each item should be validated with `./dev-test.sh fresh` and real-world manual testing before being marked as complete.