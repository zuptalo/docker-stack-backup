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

### 🔴 **3. Fix VM Startup Issue in Development Environment**
- **Status**: ❌ Not Started
- **Priority**: High
- **Description**: Fix issue where `./dev-test.sh up` doesn't start VMs properly
- **Requirements**:
  - Investigate why `smart_start_vms()` function isn't working correctly
  - Fix VM startup logic to ensure both VMs start properly
  - Test that `./dev-test.sh up` command works as expected
- **Current Issue**: User reported that `./dev-test.sh up` doesn't start VMs properly
- **Test Cases Needed**:
  - Test VM startup from stopped state
  - Test VM startup when some VMs are already running
  - Test VM status detection logic

### 🔴 **4. Path Migration in Config Command**
- **Status**: ❌ Not Started
- **Priority**: High
- **Description**: Implement path migration functionality in config command - inventory stacks, warn about complexity, pre-migration backup, move data, update configurations
- **Requirements**:
  - Inventory deployed stacks via Portainer API
  - Warn about complexity with additional stacks
  - Create pre-migration backup
  - Move data folders to new paths
  - Update stack configurations with new paths
  - Validate all services restart successfully
- **Test Cases Needed**:
  - Test config with only Portainer + NPM
  - Test config with additional stacks
  - Test path migration process
  - Test rollback on failure

### 🔴 **5. Dual Backup Approach for Reliability**
- **Status**: ❌ Not Started
- **Priority**: High
- **Description**: Add metadata file generation for ownership/permissions alongside tar archive to ensure 100% reliability
- **Requirements**:
  - Generate metadata file with detailed ownership/permissions
  - Include metadata file in backup archive
  - Use metadata file during restore process
  - Maintain tar.gz as primary method with metadata as backup
- **Test Cases Needed**:
  - Test metadata file generation
  - Test metadata file usage during restore
  - Test permission preservation across different scenarios

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

## Next Steps

**Recommended starting point**: Begin with **Item 1 (DNS Verification)** as it's foundational to the setup process and affects user experience significantly.

**Implementation approach**: One item at a time, with full implementation and testing before moving to the next item.

**Testing validation**: Each item should be validated with `./dev-test.sh fresh` before being marked as complete.