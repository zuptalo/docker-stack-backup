#!/bin/bash

set -euo pipefail

# Docker Backup Manager
# Comprehensive script for Docker-based deployment backup and management
# Compatible with Ubuntu 24.04

VERSION="2025.08.22.1546"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/docker-backup-manager.log"

# Default configuration
DEFAULT_PORTAINER_PATH="/opt/portainer"
DEFAULT_TOOLS_PATH="/opt/tools"
DEFAULT_BACKUP_PATH="/opt/backup"
DEFAULT_BACKUP_RETENTION=7
DEFAULT_REMOTE_RETENTION=30
DEFAULT_DOMAIN="zuptalo.com"
DEFAULT_PORTAINER_SUBDOMAIN="pt"
DEFAULT_NPM_SUBDOMAIN="npm"
DEFAULT_PORTAINER_USER="portainer"

# Non-interactive mode configuration
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
AUTO_YES="${AUTO_YES:-false}"
QUIET_MODE="${QUIET_MODE:-false}"
PROMPT_TIMEOUT="${PROMPT_TIMEOUT:-60}"  # Default 60 second timeout
CONFIG_FILE="${CONFIG_FILE:-}"  # Path to configuration file

# Test environment defaults
TEST_DOMAIN="zuptalo.local"
TEST_PORTAINER_SUBDOMAIN="pt"
TEST_NPM_SUBDOMAIN="npm"

# Configuration file (default location, can be overridden by --config-file flag)
DEFAULT_CONFIG_FILE="/etc/docker-backup-manager.conf"
CONFIG_FILE=""
USER_SPECIFIED_CONFIG_FILE=false

# Colors for output - enable if terminal supports colors
if [[ "${TERM:-}" == *"color"* ]] || [[ "${TERM:-}" == "xterm"* ]] || [[ "${TERM:-}" == "screen"* ]] || [[ "${TERM:-}" == "tmux"* ]]; then
    # Known color terminals - enable colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
elif [[ "${TERM:-}" != "dumb" ]] && command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1 && [[ "$(tput colors)" -ge 8 ]]; then
    # Fallback to tput detection (removed TTY check for SSH compatibility)
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    # No colors
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Display message to console
    printf "%s [%s] %b\n" "${timestamp}" "${level}" "${message}"
    
    # Try to write to log file with proper error handling (strip color codes)
    local clean_message=$(printf "%b" "${message}" | sed 's/\x1b\[[0-9;]*m//g')
    write_to_log "${timestamp} [${level}] ${clean_message}"
}

# Write to log file with proper permission handling
write_to_log() {
    local log_message="$1"
    
    # Ensure log file exists and has proper permissions
    if [[ ! -f "${LOG_FILE}" ]]; then
        # Create log file with sudo and set proper permissions
        sudo touch "${LOG_FILE}" 2>/dev/null || return 0
        sudo chmod 666 "${LOG_FILE}" 2>/dev/null || return 0
    fi
    
    # Try to write normally first
    if printf "%s\n" "${log_message}" >> "${LOG_FILE}" 2>/dev/null; then
        return 0
    fi
    
    # If normal write fails, try with sudo
    if printf "%s\n" "${log_message}" | sudo tee -a "${LOG_FILE}" >/dev/null 2>&1; then
        # After sudo write, fix permissions for future writes
        sudo chmod 666 "${LOG_FILE}" 2>/dev/null || true
        return 0
    fi
    
    # If both fail, just continue silently (don't break the script)
    return 0
}

info() { log "INFO" "$*"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
# Enhanced cleanup and error recovery
cleanup() {
    local exit_code=$?
    
    # Clean up temporary directories
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    
    # Clean up any operation lock files
    if [[ -n "${OPERATION_LOCK:-}" && -f "$OPERATION_LOCK" ]]; then
        rm -f "$OPERATION_LOCK" 2>/dev/null || true
    fi
    
    # If we're exiting due to an error and recovery info exists, show recovery instructions
    if [[ $exit_code -ne 0 && -n "${RECOVERY_INFO:-}" && -f "$RECOVERY_INFO" ]]; then
        echo
        warn "Operation failed - recovery information available:"
        warn "Recovery file: $RECOVERY_INFO"
        warn "To view recovery instructions: cat '$RECOVERY_INFO'"
    fi
}

trap cleanup EXIT

# Create recovery information for critical operations
create_recovery_info() {
    local operation="$1"
    local recovery_file="/tmp/backup_manager_recovery_$(date +%Y%m%d_%H%M%S).json"
    RECOVERY_INFO="$recovery_file"
    
    local current_state=""
    case "$operation" in
        "backup")
            current_state="backup_creation"
            ;;
        "restore")
            current_state="system_restore"
            ;;
        "setup")
            current_state="initial_setup"
            ;;
        "migration")
            current_state="path_migration"
            ;;
        *)
            current_state="unknown_operation"
            ;;
    esac
    
    jq -n \
        --arg op "$operation" \
        --arg state "$current_state" \
        --arg timestamp "$(date -Iseconds)" \
        --arg user "$(whoami)" \
        --arg working_dir "$(pwd)" \
        '{
            operation: $op,
            state: $state,
            timestamp: $timestamp,
            user: $user,
            working_directory: $working_dir,
            recovery_instructions: {
                backup_creation: "If backup creation failed, check disk space and try again. Previous backups are preserved.",
                system_restore: "If restore failed, system may be in inconsistent state. Check logs and restore from last known good backup.",
                initial_setup: "If setup failed, run uninstall command and restart setup. Check prerequisites and network connectivity.",
                path_migration: "If migration failed, restore from pre-migration backup using restore command with the backup file listed above.",
                unknown_operation: "Check logs for specific error messages and recovery steps."
            }
        }' > "$recovery_file" 2>/dev/null || true
    
    return 0
}

# Validate critical system state after operations
validate_system_state() {
    local operation="$1"
    local validation_errors=()
    
    case "$operation" in
        "setup")
            # Validate Docker is running
            if ! systemctl is-active docker >/dev/null 2>&1; then
                validation_errors+=("Docker daemon is not running")
            fi
            
            # Validate Portainer is accessible
            if ! curl -s -f "http://localhost:9000" >/dev/null 2>&1; then
                validation_errors+=("Portainer is not accessible on port 9000")
            fi
            
            # Validate required directories exist
            for dir in "$PORTAINER_PATH" "$TOOLS_PATH" "$BACKUP_PATH"; do
                if [[ -n "$dir" && ! -d "$dir" ]]; then
                    validation_errors+=("Required directory does not exist: $dir")
                fi
            done
            ;;
        "backup")
            # Validate backup file was created
            if [[ -n "${LATEST_BACKUP:-}" && ! -f "$LATEST_BACKUP" ]]; then
                validation_errors+=("Backup file was not created: $LATEST_BACKUP")
            fi
            
            # Validate services are running after backup
            if ! curl -s -f "http://localhost:9000" >/dev/null 2>&1; then
                validation_errors+=("Portainer is not accessible after backup")
            fi
            ;;
        "restore")
            # Validate services are running after restore
            if ! curl -s -f "http://localhost:9000" >/dev/null 2>&1; then
                validation_errors+=("Portainer is not accessible after restore")
            fi
            
            # Validate data directories exist
            for dir in "$PORTAINER_PATH" "$TOOLS_PATH"; do
                if [[ -n "$dir" && ! -d "$dir" ]]; then
                    validation_errors+=("Required directory missing after restore: $dir")
                fi
            done
            ;;
    esac
    
    # Report validation results
    if [[ ${#validation_errors[@]} -eq 0 ]]; then
        success "System validation passed for $operation"
        return 0
    else
        error "System validation failed for $operation:"
        for error in "${validation_errors[@]}"; do
            error "  - $error"
        done
        return 1
    fi
}

# Create operation lock to prevent concurrent operations
create_operation_lock() {
    local operation="$1"
    local lock_file="/tmp/backup_manager_${operation}.lock"
    
    if [[ -f "$lock_file" ]]; then
        local lock_pid=$(cat "$lock_file" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            error "Another $operation operation is already running (PID: $lock_pid)"
            error "If this is incorrect, remove the lock file: rm '$lock_file'"
            return 1
        else
            warn "Removing stale lock file: $lock_file"
            rm -f "$lock_file"
        fi
    fi
    
    echo "$$" > "$lock_file"
    OPERATION_LOCK="$lock_file"
    return 0
}

die() {
    error "$*"
    exit 1
}

# Cache for dependency check results to avoid repeated checks
DEPENDENCIES_CHECKED=false

# Install required dependencies with optimization and user confirmation
install_dependencies() {
    # Skip if already checked in this session
    if [[ "$DEPENDENCIES_CHECKED" == "true" ]]; then
        return 0
    fi
    
    info "Checking required dependencies..."
    
    # Define required tools with descriptions
    local required_tools_list="curl wget jq dnsutils"
    
    local missing_tools=()
    local available_tools=()
    
    # Check which tools are missing (note: dnsutils provides dig command)
    for tool in curl wget jq; do
        if command -v "$tool" >/dev/null 2>&1; then
            available_tools+=("$tool")
        else
            missing_tools+=("$tool")
        fi
    done
    
    # Check for dig (from dnsutils package)
    if ! command -v dig >/dev/null 2>&1; then
        missing_tools+=("dnsutils")
    else
        available_tools+=("dig")
    fi
    
    # Show status of all tools
    if [[ ${#available_tools[@]} -gt 0 ]]; then
        success "Available tools: ${available_tools[*]}"
    fi
    
    # Handle missing tools
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo
        warn "Missing required tools detected:"
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                curl) echo "  • $tool - Download files and make HTTP requests" ;;
                wget) echo "  • $tool - Download files from web servers" ;;
                jq) echo "  • $tool - Parse and manipulate JSON data" ;;
                dnsutils) echo "  • $tool - DNS utilities (dig, nslookup)" ;;
                cron) echo "  • $tool - Task scheduling daemon (provides crontab command)" ;;
                *) echo "  • $tool - Required system tool" ;;
            esac
        done
        echo
        
        # Ask for user confirmation (skip in test environment)
        if is_test_environment; then
            info "Test environment detected - auto-installing dependencies"
            install_confirmed=true
        else
            if prompt_yes_no "Install missing tools automatically?" "y"; then
                install_confirmed=true
            else
                install_confirmed=false
            fi
        fi
        
        if [[ "$install_confirmed" == "true" ]]; then
            install_system_packages "${missing_tools[@]}"
        else
            error "Required tools are missing. Please install them manually:"
            for tool in "${missing_tools[@]}"; do
                error "  sudo apt-get install -y $tool"
            done
            return 1
        fi
    else
        success "All required dependencies are available"
    fi
    
    # Mark as checked to avoid repeated checks
    DEPENDENCIES_CHECKED=true
    return 0
}

# Install system packages with proper error handling
install_system_packages() {
    local packages=("$@")
    
    info "Installing system packages: ${packages[*]}"
    
    # Update package list
    info "Updating package list..."
    if ! sudo apt-get update >/dev/null 2>&1; then
        error "Failed to update package list"
        error "Please check your internet connection and try again"
        return 1
    fi
    
    # Install each package
    for package in "${packages[@]}"; do
        info "Installing $package..."
        if sudo apt-get install -y "$package" >/dev/null 2>&1; then
            success "$package installed successfully"
        else
            error "Failed to install $package"
            error "You may need to install it manually: sudo apt-get install -y $package"
            return 1
        fi
    done
    
    # Verify installations
    info "Verifying installations..."
    for package in "${packages[@]}"; do
        # Special handling for dnsutils package (provides dig command)
        if [[ "$package" == "dnsutils" ]]; then
            if command -v dig >/dev/null 2>&1; then
                success "dig (from dnsutils) is now available"
            else
                error "dnsutils installation verification failed - dig not found"
                return 1
            fi
        else
            if command -v "$package" >/dev/null 2>&1; then
                success "$package is now available"
            else
                error "$package installation verification failed"
                return 1
            fi
        fi
    done
    
    success "All packages installed and verified successfully"
    return 0
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        die "This script should not be run as root for security reasons. Run as a regular user with sudo privileges."
    fi
}

# Check if system setup is complete before running operational commands
check_setup_required() {
    local missing_requirements=()
    
    # Check if configuration file exists
    if [[ ! -f "$DEFAULT_CONFIG_FILE" ]]; then
        missing_requirements+=("Configuration file missing")
    fi
    
    # Check if portainer user exists
    if ! id "$PORTAINER_USER" >/dev/null 2>&1; then
        missing_requirements+=("System user '$PORTAINER_USER' not found")
    fi
    
    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        missing_requirements+=("Docker not installed")
    fi
    
    # Check if basic directories exist
    if [[ ! -d "$PORTAINER_PATH" ]]; then
        missing_requirements+=("Portainer directory missing")
    fi
    
    # If any requirements are missing, show setup guidance
    if [[ ${#missing_requirements[@]} -gt 0 ]]; then
        echo
        error "System setup is incomplete. Cannot proceed with this command."
        echo
        warn "Missing requirements:"
        for requirement in "${missing_requirements[@]}"; do
            echo "  • $requirement"
        done
        echo
        info "Please run the setup command first:"
        printf "  %b\n" "${BLUE}./backup-manager.sh setup${NC}"
        echo
        info "The setup command will:"
        echo "  • Install Docker and required dependencies"
        echo "  • Create system user and directories"
        echo "  • Configure Portainer and nginx-proxy-manager"
        echo "  • Set up networking and SSL certificates"
        echo
        return 1
    fi
    
    return 0
}

# Check if running in test environment
is_test_environment() {
    [[ "${DOCKER_BACKUP_TEST:-}" == "true" ]] || [[ -f "/.dockerenv" ]]
}

# Enhanced prompt function with timeout and non-interactive support
prompt_user() {
    local prompt_text="$1"
    local default_value="${2:-}"
    local timeout_default="${3:-${default_value}}"
    local variable_name=""
    
    # Handle non-interactive modes
    if [[ "$NON_INTERACTIVE" == "true" ]] || is_test_environment; then
        if [[ -n "$default_value" ]]; then
            printf "%s" "$default_value"
        else
            printf "%s" "$timeout_default"
        fi
        return 0
    fi
    
    # Show prompt with timeout warning
    local full_prompt="$prompt_text"
    if [[ "$PROMPT_TIMEOUT" -gt 0 ]]; then
        full_prompt="$prompt_text (${PROMPT_TIMEOUT}s timeout, default: ${timeout_default})"
    fi
    
    local user_input=""
    if [[ "$PROMPT_TIMEOUT" -gt 0 ]]; then
        # Use timeout for interactive prompt
        if read -t "$PROMPT_TIMEOUT" -p "$full_prompt: " user_input; then
            if [[ -n "$user_input" ]]; then
                printf "%s" "$user_input"
            else
                printf "%s" "$default_value"
            fi
        else
            # Timeout occurred
            echo >&2  # New line after timeout
            warn "Prompt timeout after ${PROMPT_TIMEOUT} seconds, using default: ${timeout_default}"
            printf "%s" "$timeout_default"
        fi
    else
        # No timeout, regular prompt
        read -p "$full_prompt: " user_input
        if [[ -n "$user_input" ]]; then
            printf "%s" "$user_input"
        else
            printf "%s" "$default_value"
        fi
    fi
}

# Yes/No prompt with timeout and auto-yes support
prompt_yes_no() {
    local prompt_text="$1"
    local default_answer="${2:-n}"  # Default to 'n' for safety
    
    # Handle auto-yes mode
    if [[ "$AUTO_YES" == "true" ]]; then
        info "Auto-yes mode: $prompt_text -> y"
        return 0
    fi
    
    # Handle non-interactive modes
    if [[ "$NON_INTERACTIVE" == "true" ]] || is_test_environment; then
        if [[ "$default_answer" =~ ^[Yy]$ ]]; then
            return 0
        else
            return 1
        fi
    fi
    
    local user_input
    local full_prompt="$prompt_text [y/N]"
    if [[ "$default_answer" =~ ^[Yy]$ ]]; then
        full_prompt="$prompt_text [Y/n]"
    fi
    
    if [[ "$PROMPT_TIMEOUT" -gt 0 ]]; then
        full_prompt="$full_prompt (${PROMPT_TIMEOUT}s timeout, default: ${default_answer})"
        if read -t "$PROMPT_TIMEOUT" -p "$full_prompt: " user_input; then
            [[ -z "$user_input" ]] && user_input="$default_answer"
        else
            echo >&2  # New line after timeout
            warn "Prompt timeout after ${PROMPT_TIMEOUT} seconds, using default: ${default_answer}"
            user_input="$default_answer"
        fi
    else
        read -p "$full_prompt: " user_input
        [[ -z "$user_input" ]] && user_input="$default_answer"
    fi
    
    [[ "$user_input" =~ ^[Yy]$ ]]
}

# Setup log file with proper permissions

# Load configuration from file
load_config() {
    # Determine which config file to use
    local config_to_load=""
    
    if [[ "$USER_SPECIFIED_CONFIG_FILE" == "true" && -n "$CONFIG_FILE" ]]; then
        # User explicitly specified a config file
        config_to_load="$CONFIG_FILE"
    elif [[ -f "$DEFAULT_CONFIG_FILE" ]]; then
        # Use default config file if it exists
        config_to_load="$DEFAULT_CONFIG_FILE"
    fi
    
    if [[ -n "$config_to_load" ]]; then
        info "Loading configuration from: $config_to_load"

        # Validate and source the config file safely
        if ! bash -n "$config_to_load" 2>/dev/null; then
            error "Configuration file has syntax errors: $config_to_load"
            exit 1
        fi

        # shellcheck source=/dev/null
        source "$config_to_load"
        info "Configuration loaded successfully"
    fi
    
    # Set defaults based on environment
    if is_test_environment; then
        # Test environment - non-interactive defaults
        DOMAIN_NAME="${DOMAIN_NAME:-$TEST_DOMAIN}"
        PORTAINER_SUBDOMAIN="${PORTAINER_SUBDOMAIN:-$TEST_PORTAINER_SUBDOMAIN}"
        NPM_SUBDOMAIN="${NPM_SUBDOMAIN:-$TEST_NPM_SUBDOMAIN}"
    else
        # Production environment - use user configuration or defaults
        DOMAIN_NAME="${DOMAIN_NAME:-$DEFAULT_DOMAIN}"
        PORTAINER_SUBDOMAIN="${PORTAINER_SUBDOMAIN:-$DEFAULT_PORTAINER_SUBDOMAIN}"
        NPM_SUBDOMAIN="${NPM_SUBDOMAIN:-$DEFAULT_NPM_SUBDOMAIN}"
    fi
    
    # Set other defaults
    PORTAINER_PATH="${PORTAINER_PATH:-$DEFAULT_PORTAINER_PATH}"
    TOOLS_PATH="${TOOLS_PATH:-$DEFAULT_TOOLS_PATH}"
    BACKUP_PATH="${BACKUP_PATH:-$DEFAULT_BACKUP_PATH}"
    BACKUP_RETENTION="${BACKUP_RETENTION:-$DEFAULT_BACKUP_RETENTION}"
    REMOTE_RETENTION="${REMOTE_RETENTION:-$DEFAULT_REMOTE_RETENTION}"
    PORTAINER_USER="${PORTAINER_USER:-$DEFAULT_PORTAINER_USER}"
    
    # Set URLs
    PORTAINER_URL="${PORTAINER_SUBDOMAIN}.${DOMAIN_NAME}"
    NPM_URL="${NPM_SUBDOMAIN}.${DOMAIN_NAME}"
}

# Save configuration
save_config() {
    # Use default config file location for saving during setup
    local config_file_to_save="${CONFIG_FILE:-$DEFAULT_CONFIG_FILE}"
    sudo tee "$config_file_to_save" > /dev/null << EOF
# Docker Backup Manager Configuration
PORTAINER_PATH="$PORTAINER_PATH"
TOOLS_PATH="$TOOLS_PATH"
BACKUP_PATH="$BACKUP_PATH"
BACKUP_RETENTION="$BACKUP_RETENTION"
REMOTE_RETENTION="$REMOTE_RETENTION"
DOMAIN_NAME="$DOMAIN_NAME"
PORTAINER_SUBDOMAIN="$PORTAINER_SUBDOMAIN"
NPM_SUBDOMAIN="$NPM_SUBDOMAIN"
PORTAINER_USER="$PORTAINER_USER"
PORTAINER_URL="$PORTAINER_URL"
NPM_URL="$NPM_URL"
EOF
    success "Configuration saved to $config_file_to_save"
}

# Simple fixed configuration - no customization needed
setup_fixed_configuration() {
    info "Setting up Docker Backup Manager with default configuration..."

    # Use fixed default paths - no customization
    PORTAINER_USER="portainer"
    PORTAINER_PATH="/opt/portainer"
    TOOLS_PATH="/opt/tools"
    BACKUP_PATH="/opt/backup"

    # Initialize domain defaults
    DOMAIN_NAME="${DOMAIN_NAME:-$DEFAULT_DOMAIN}"
    PORTAINER_SUBDOMAIN="${PORTAINER_SUBDOMAIN:-$DEFAULT_PORTAINER_SUBDOMAIN}"
    NPM_SUBDOMAIN="${NPM_SUBDOMAIN:-$DEFAULT_NPM_SUBDOMAIN}"
    
    # Initialize other defaults
    BACKUP_RETENTION="${BACKUP_RETENTION:-$DEFAULT_BACKUP_RETENTION}"
    REMOTE_RETENTION="${REMOTE_RETENTION:-$DEFAULT_REMOTE_RETENTION}"

    # Only domain configuration is needed for SSL certificates
    if ! is_test_environment; then
        printf "%b\n" "${BLUE}=== Domain Configuration ===${NC}"
        echo "Configure your domain for SSL certificates and service access."
        echo

        DOMAIN_NAME=$(prompt_user "Domain name (e.g., example.com)" "$DOMAIN_NAME")
        PORTAINER_SUBDOMAIN=$(prompt_user "Portainer subdomain" "$PORTAINER_SUBDOMAIN")
        NPM_SUBDOMAIN=$(prompt_user "NPM admin subdomain" "$NPM_SUBDOMAIN")

        echo
        printf "%b\n" "${BLUE}Configuration summary:${NC}"
        echo "  • System user: $PORTAINER_USER (fixed)"
        echo "  • Portainer path: $PORTAINER_PATH (fixed)"
        echo "  • Tools path: $TOOLS_PATH (fixed)"
        echo "  • Backup path: $BACKUP_PATH (fixed)"
        echo "  • Domain: $DOMAIN_NAME"
        echo "  • Portainer URL: https://$PORTAINER_SUBDOMAIN.$DOMAIN_NAME"
        echo "  • NPM admin URL: https://$NPM_SUBDOMAIN.$DOMAIN_NAME"
        echo

        if ! prompt_yes_no "Continue with this configuration?" "y"; then
            info "Setup cancelled by user"
            exit 0
        fi
    fi

    # Set URLs for configuration file
    PORTAINER_URL="${PORTAINER_SUBDOMAIN}.${DOMAIN_NAME}"
    NPM_URL="${NPM_SUBDOMAIN}.${DOMAIN_NAME}"

    # Save configuration
    save_config
    info "Configuration saved successfully"
}

# Interactive setup configuration with user choice
interactive_setup_configuration() {
    printf "%b\n" "${BLUE}=== Docker Backup Manager Initial Setup ===${NC}"
    echo
    echo "Welcome to Docker Backup Manager setup!"
    echo
    printf "%b\n" "${BLUE}Current default configuration:${NC}"
    echo "  • System user: $PORTAINER_USER"
    echo "  • Portainer data path: $PORTAINER_PATH"
    echo "  • Tools data path: $TOOLS_PATH"
    echo "  • Backup storage path: $BACKUP_PATH"
    echo "  • Local backup retention: $BACKUP_RETENTION days"
    echo "  • Remote backup retention: $REMOTE_RETENTION days"
    echo "  • Domain name: $DOMAIN_NAME"
    echo "  • Portainer subdomain: $PORTAINER_SUBDOMAIN"
    echo "  • NPM admin subdomain: $NPM_SUBDOMAIN"
    echo
    printf "%b\n" "${BLUE}Setup options:${NC}"
    echo "1) Use default configuration (recommended for most users)"
    echo "2) Customize configuration interactively"
    echo "3) Show advanced configuration details"
    echo "4) Exit setup"
    echo
    
    # In test environment, automatically choose option 1 (default configuration)
    if is_test_environment; then
        setup_choice="1"
        info "Test environment: automatically choosing default configuration"
    else
        read -p "Choose setup option [1-4]: " setup_choice
    fi
    
    case "$setup_choice" in
        1)
            info "Using default configuration"
            confirm_configuration
            ;;
        2)
            info "Starting interactive configuration"
            interactive_configuration
            ;;
        3)
            show_advanced_configuration_details
            interactive_setup_configuration
            ;;
        4)
            info "Setup cancelled by user"
            exit 0
            ;;
        *)
            warn "Invalid option selected. Using default configuration."
            confirm_configuration
            ;;
    esac
}

# Show advanced configuration details
show_advanced_configuration_details() {
    echo
    printf "%b\n" "${BLUE}=== Advanced Configuration Details ===${NC}"
    echo
    printf "%b\n" "${BLUE}System User ($PORTAINER_USER):${NC}"
    echo "  • Used for running Docker containers and backup operations"
    echo "  • Must have Docker group access and sudo privileges"
    echo "  • Default 'portainer' is suitable for most installations"
    echo
    printf "%b\n" "${BLUE}Portainer Data Path ($PORTAINER_PATH):${NC}"
    echo "  • Stores Portainer configuration and container data"
    echo "  • Should be on a persistent volume with adequate space"
    echo "  • Default /opt/portainer is standard for system installations"
    echo
    printf "%b\n" "${BLUE}Tools Data Path ($TOOLS_PATH):${NC}"
    echo "  • Stores nginx-proxy-manager and other tool configurations"
    echo "  • Should be on the same volume as Portainer for consistency"
    echo "  • Default /opt/tools follows standard directory structure"
    echo
    printf "%b\n" "${BLUE}Backup Storage Path ($BACKUP_PATH):${NC}"
    echo "  • Where backup archives are stored locally"
    echo "  • Should have sufficient space for your backup retention policy"
    echo "  • Default /opt/backup is accessible system-wide"
    echo
    printf "%b\n" "${BLUE}Backup Retention:${NC}"
    echo "  • Local retention: How many backups to keep locally"
    echo "  • Remote retention: How many backups to keep on remote storage"
    echo "  • Higher retention uses more storage but provides more restore points"
    echo
    printf "%b\n" "${BLUE}Domain Configuration:${NC}"
    echo "  • Domain name: Your main domain for accessing services"
    echo "  • Subdomains: Used for accessing Portainer and nginx-proxy-manager"
    echo "  • SSL certificates will be automatically requested if DNS is configured"
    echo
    echo "Press Enter to continue..."
    read
}

# Interactive configuration
interactive_configuration() {
    printf "%b\n" "${BLUE}=== Interactive Configuration ===${NC}"
    echo
    echo "Configure each setting (press Enter to keep default):"
    echo
    
    PORTAINER_USER=$(prompt_user "System user" "$PORTAINER_USER")
    PORTAINER_PATH=$(prompt_user "Portainer data path" "$PORTAINER_PATH")
    TOOLS_PATH=$(prompt_user "Tools data path" "$TOOLS_PATH")
    BACKUP_PATH=$(prompt_user "Backup storage path" "$BACKUP_PATH")
    BACKUP_RETENTION=$(prompt_user "Local backup retention (days)" "$BACKUP_RETENTION")
    REMOTE_RETENTION=$(prompt_user "Remote backup retention (days)" "$REMOTE_RETENTION")
    DOMAIN_NAME=$(prompt_user "Domain name" "$DOMAIN_NAME")
    PORTAINER_SUBDOMAIN=$(prompt_user "Portainer subdomain" "$PORTAINER_SUBDOMAIN")
    NPM_SUBDOMAIN=$(prompt_user "NPM admin subdomain" "$NPM_SUBDOMAIN")
    
    confirm_configuration
}

# Confirm configuration before proceeding
confirm_configuration() {
    # Calculate URLs
    PORTAINER_URL="${PORTAINER_SUBDOMAIN}.${DOMAIN_NAME}"
    NPM_URL="${NPM_SUBDOMAIN}.${DOMAIN_NAME}"
    
    echo
    printf "%b\n" "${BLUE}=== Final Configuration Summary ===${NC}"
    echo "Domain: $DOMAIN_NAME"
    echo "Portainer URL: https://$PORTAINER_SUBDOMAIN.$DOMAIN_NAME"
    echo "NPM URL: https://$NPM_SUBDOMAIN.$DOMAIN_NAME"
    echo "Portainer Path: $PORTAINER_PATH"
    echo "Tools Path: $TOOLS_PATH"
    echo "Backup Path: $BACKUP_PATH"
    echo "Local Retention: $BACKUP_RETENTION days"
    echo "Remote Retention: $REMOTE_RETENTION days"
    echo "System User: $PORTAINER_USER"
    echo
    
    if ! prompt_yes_no "Save this configuration?" "y"; then
        echo "Configuration not saved. Exiting."
        exit 0
    fi
    
    save_config
}

# Path migration for existing installations
migrate_paths() {
    printf "%b\n" "${BLUE}=== Path Migration Mode ===${NC}"
    printf "%b\n" "${YELLOW}WARNING: This will migrate your existing installation to new paths${NC}"
    echo
    
    # Store current paths
    local old_portainer_path="$PORTAINER_PATH"
    local old_tools_path="$TOOLS_PATH"
    local old_backup_path="$BACKUP_PATH"
    
    # Show current configuration
    printf "%b\n" "${BLUE}Current Configuration:${NC}"
    echo "Portainer Path: $PORTAINER_PATH"
    echo "Tools Path: $TOOLS_PATH"
    echo "Backup Path: $BACKUP_PATH"
    echo "Domain: $DOMAIN_NAME"
    echo "Portainer URL: https://$PORTAINER_SUBDOMAIN.$DOMAIN_NAME"
    echo "NPM URL: https://$NPM_SUBDOMAIN.$DOMAIN_NAME"
    echo "Local Retention: $BACKUP_RETENTION days"
    echo "Remote Retention: $REMOTE_RETENTION days"
    echo "System User: $PORTAINER_USER"
    echo
    
    # Get new paths
    printf "%b\n" "${BLUE}Enter new paths (press Enter to keep current):${NC}"
    echo
    
    read -p "New Portainer data path [$PORTAINER_PATH]: " input
    local new_portainer_path="${input:-$PORTAINER_PATH}"
    
    read -p "New Tools data path [$TOOLS_PATH]: " input
    local new_tools_path="${input:-$TOOLS_PATH}"
    
    read -p "New Backup storage path [$BACKUP_PATH]: " input
    local new_backup_path="${input:-$BACKUP_PATH}"
    
    read -p "Domain name [$DOMAIN_NAME]: " input
    DOMAIN_NAME="${input:-$DOMAIN_NAME}"
    
    read -p "Portainer subdomain [$PORTAINER_SUBDOMAIN]: " input
    PORTAINER_SUBDOMAIN="${input:-$PORTAINER_SUBDOMAIN}"
    
    read -p "NPM admin subdomain [$NPM_SUBDOMAIN]: " input
    NPM_SUBDOMAIN="${input:-$NPM_SUBDOMAIN}"
    
    read -p "Local backup retention (days) [$BACKUP_RETENTION]: " input
    BACKUP_RETENTION="${input:-$BACKUP_RETENTION}"
    
    read -p "Remote backup retention (days) [$REMOTE_RETENTION]: " input
    REMOTE_RETENTION="${input:-$REMOTE_RETENTION}"
    
    read -p "Portainer system user [$PORTAINER_USER]: " input
    PORTAINER_USER="${input:-$PORTAINER_USER}"
    
    PORTAINER_URL="${PORTAINER_SUBDOMAIN}.${DOMAIN_NAME}"
    NPM_URL="${NPM_SUBDOMAIN}.${DOMAIN_NAME}"
    
    # Check if any paths need migration
    if [[ "$new_portainer_path" == "$old_portainer_path" && 
          "$new_tools_path" == "$old_tools_path" && 
          "$new_backup_path" == "$old_backup_path" ]]; then
        info "No path changes detected. Updating configuration only."
        
        # Update paths in memory
        PORTAINER_PATH="$new_portainer_path"
        TOOLS_PATH="$new_tools_path"
        BACKUP_PATH="$new_backup_path"
        
        save_config
        success "Configuration updated successfully"
        return 0
    fi
    
    echo
    printf "%b\n" "${BLUE}Migration Summary:${NC}"
    printf "%b\n" "${YELLOW}Paths to migrate:${NC}"
    [[ "$new_portainer_path" != "$old_portainer_path" ]] && echo "  Portainer: $old_portainer_path → $new_portainer_path"
    [[ "$new_tools_path" != "$old_tools_path" ]] && echo "  Tools: $old_tools_path → $new_tools_path"
    [[ "$new_backup_path" != "$old_backup_path" ]] && echo "  Backup: $old_backup_path → $new_backup_path"
    echo
    printf "%b\n" "${YELLOW}Migration Process:${NC}"
    echo "1. Inventory deployed stacks via Portainer API"
    echo "2. Create pre-migration backup"
    echo "3. Stop services gracefully"
    echo "4. Move data folders to new paths"
    echo "5. Update configurations"
    echo "6. Restart services and validate"
    echo
    
    if ! prompt_yes_no "Proceed with migration?" "n"; then
        echo "Migration cancelled"
        return 1
    fi
    
    # Perform the migration
    perform_path_migration "$old_portainer_path" "$new_portainer_path" "$old_tools_path" "$new_tools_path" "$old_backup_path" "$new_backup_path"
}

# Perform the actual path migration
perform_path_migration() {
    local old_portainer_path="$1"
    local new_portainer_path="$2"
    local old_tools_path="$3"
    local new_tools_path="$4"
    local old_backup_path="$5"
    local new_backup_path="$6"
    
    local migration_log="/tmp/migration_$(date +%Y%m%d_%H%M%S).log"
    local rollback_info="/tmp/rollback_$(date +%Y%m%d_%H%M%S).json"
    
    exec 3>&1 4>&2
    exec 1> >(tee -a "$migration_log")
    exec 2> >(tee -a "$migration_log" >&2)
    
    echo "=== MIGRATION STARTED: $(date) ===" 
    
    # Step 1: Inventory deployed stacks
    info "Step 1: Inventorying deployed stacks..."
    local stack_inventory="/tmp/stack_inventory_$(date +%Y%m%d_%H%M%S).json"
    get_stack_inventory "$stack_inventory"
    
    local stack_count=$(jq -r '.stacks | length' "$stack_inventory" 2>/dev/null || echo "0")
    info "Found $stack_count deployed stacks"
    
    # Warn about complexity if additional stacks exist
    if [[ "$stack_count" -gt 2 ]]; then
        warn "Found $stack_count stacks (more than basic Portainer + NPM setup)"
        warn "This migration will be more complex and may require manual intervention"
        echo
        jq -r '.stacks[] | "  - \(.name) (ID: \(.id))"' "$stack_inventory" 2>/dev/null || echo "  - Unable to list stacks"
        echo
        if ! prompt_yes_no "Continue with complex migration?" "n"; then
            error "Migration cancelled due to complexity"
            return 1
        fi
    fi
    
    # Step 2: Create pre-migration backup
    info "Step 2: Creating pre-migration backup..."
    local backup_timestamp=$(date '+%Y%m%d_%H%M%S')
    local pre_migration_backup="$old_backup_path/pre_migration_backup_${backup_timestamp}.tar.gz"
    
    create_migration_backup "$pre_migration_backup" "$stack_inventory"
    
    # Create rollback information
    jq -n \
        --arg old_portainer "$old_portainer_path" \
        --arg new_portainer "$new_portainer_path" \
        --arg old_tools "$old_tools_path" \
        --arg new_tools "$new_tools_path" \
        --arg old_backup "$old_backup_path" \
        --arg new_backup "$new_backup_path" \
        --arg backup_file "$pre_migration_backup" \
        --arg stack_file "$stack_inventory" \
        --arg log_file "$migration_log" \
        '{
            old_paths: {
                portainer: $old_portainer,
                tools: $old_tools,
                backup: $old_backup
            },
            new_paths: {
                portainer: $new_portainer,
                tools: $new_tools,
                backup: $new_backup
            },
            backup_file: $backup_file,
            stack_inventory: $stack_file,
            log_file: $log_file,
            migration_date: now
        }' > "$rollback_info"
    
    # Step 3: Stop services gracefully
    info "Step 3: Stopping services gracefully..."
    stop_containers_for_migration
    
    # Step 4: Move data folders
    info "Step 4: Moving data folders to new paths..."
    migrate_data_folders "$old_portainer_path" "$new_portainer_path" "$old_tools_path" "$new_tools_path" "$old_backup_path" "$new_backup_path"
    
    # Step 5: Update configurations
    info "Step 5: Updating configurations..."
    update_configurations_for_migration "$old_portainer_path" "$new_portainer_path" "$old_tools_path" "$new_tools_path" "$old_backup_path" "$new_backup_path"
    
    # Step 6: Restart services and validate
    info "Step 6: Restarting services and validating..."
    restart_and_validate_services "$stack_inventory"
    
    exec 1>&3 2>&4
    exec 3>&- 4>&-
    
    success "Migration completed successfully!"
    success "Rollback information saved to: $rollback_info"
    success "Migration log saved to: $migration_log"
    
    info "Services should be accessible at:"
    info "  Portainer: https://$PORTAINER_URL"
    info "  nginx-proxy-manager: https://$NPM_URL"
}

# Get detailed stack inventory for migration
get_stack_inventory() {
    local output_file="$1"
    
    if [[ ! -f "$PORTAINER_PATH/.credentials" ]]; then
        warn "Portainer credentials not found"
        echo '{"stacks": []}' > "$output_file"
        return 0
    fi
    
    source "$PORTAINER_PATH/.credentials"
    
    # Login to Portainer API
    local auth_response
    auth_response=$(curl -s -X POST "$PORTAINER_API_URL/auth" \
        -H "Content-Type: application/json" \
        -d "{\"Username\": \"$PORTAINER_ADMIN_USERNAME\", \"Password\": \"$PORTAINER_ADMIN_PASSWORD\"}")
    
    local jwt_token
    jwt_token=$(echo "$auth_response" | jq -r '.jwt // empty')
    
    if [[ -z "$jwt_token" ]]; then
        warn "Failed to authenticate with Portainer API for stack inventory"
        echo '{"stacks": []}' > "$output_file"
        return 0
    fi
    
    # Get detailed stack information
    local stacks_response
    stacks_response=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/stacks")
    
    # Create detailed inventory
    local stack_inventory='{"stacks": []}'
    if [[ "$stacks_response" != "null" && -n "$stacks_response" ]]; then
        stack_inventory=$(echo "$stacks_response" | jq '{
            stacks: [.[] | {
                id: .Id,
                name: .Name,
                status: .Status,
                type: .Type,
                endpoint_id: .EndpointId,
                compose_file: .ComposeFile,
                env_vars: .Env,
                creation_date: .CreationDate,
                update_date: .UpdateDate
            }]
        }')
    fi
    
    echo "$stack_inventory" > "$output_file"
    info "Stack inventory saved to: $output_file"
}

# Create a comprehensive backup before migration
create_migration_backup() {
    local backup_file="$1"
    local stack_inventory="$2"
    
    info "Creating comprehensive pre-migration backup..."
    
    local temp_backup_dir="/tmp/pre_migration_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$temp_backup_dir"
    
    # Copy stack inventory
    cp "$stack_inventory" "$temp_backup_dir/stack_inventory.json"
    
    # Copy current configuration
    cp "$CONFIG_FILE" "$temp_backup_dir/config.conf"
    
    # Create metadata
    jq -n \
        --arg version "$VERSION" \
        --arg backup_date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg backup_type "pre_migration" \
        --arg portainer_path "$PORTAINER_PATH" \
        --arg tools_path "$TOOLS_PATH" \
        --arg backup_path "$BACKUP_PATH" \
        '{
            version: $version,
            backup_date: $backup_date,
            backup_type: $backup_type,
            paths: {
                portainer: $portainer_path,
                tools: $tools_path,
                backup: $backup_path
            }
        }' > "$temp_backup_dir/backup_metadata.json"
    
    # Create the backup archive
    info "Creating backup archive at: $backup_file"
    
    # Ensure parent directory exists
    mkdir -p "$(dirname "$backup_file")"
    
    # Create tar archive with preserved permissions
    if sudo tar -czf "$backup_file" \
        --same-owner --same-permissions \
        -C "$PORTAINER_PATH" . \
        -C "$TOOLS_PATH" . \
        -C "$temp_backup_dir" . 2>/dev/null; then
        success "Pre-migration backup created successfully"
    else
        error "Failed to create pre-migration backup"
        rm -rf "$temp_backup_dir"
        return 1
    fi
    
    # Set proper ownership
    sudo chown "$PORTAINER_USER:$PORTAINER_USER" "$backup_file"
    
    # Clean up temporary directory
    rm -rf "$temp_backup_dir"
    
    info "Backup size: $(du -h "$backup_file" | cut -f1)"
}

# Stop containers for migration (different from regular backup)
stop_containers_for_migration() {
    info "Stopping containers for migration..."
    
    # Stop all containers except Portainer itself (we need it for API access)
    local containers_to_stop=($(sudo -u "$PORTAINER_USER" docker ps --format "table {{.Names}}" | grep -v "^NAMES$" | grep -v "portainer"))
    
    for container in "${containers_to_stop[@]}"; do
        if [[ -n "$container" ]]; then
            info "Stopping container: $container"
            sudo -u "$PORTAINER_USER" docker stop "$container" 2>/dev/null || warn "Failed to stop $container"
        fi
    done
    
    # Wait for containers to stop
    sleep 5
    
    success "Containers stopped for migration"
}

# Move data folders to new paths
migrate_data_folders() {
    local old_portainer_path="$1"
    local new_portainer_path="$2"
    local old_tools_path="$3"
    local new_tools_path="$4"
    local old_backup_path="$5"
    local new_backup_path="$6"
    
    # Migrate Portainer data
    if [[ "$old_portainer_path" != "$new_portainer_path" ]]; then
        info "Migrating Portainer data: $old_portainer_path → $new_portainer_path"
        
        # Create new directory
        sudo mkdir -p "$new_portainer_path"
        
        # Move data with preserved permissions
        if sudo mv "$old_portainer_path"/* "$new_portainer_path/" 2>/dev/null; then
            # Set ownership
            sudo chown -R "$PORTAINER_USER:$PORTAINER_USER" "$new_portainer_path"
            
            # Remove old directory if empty
            sudo rmdir "$old_portainer_path" 2>/dev/null || warn "Could not remove old Portainer directory"
            
            success "Portainer data migrated successfully"
        else
            error "Failed to migrate Portainer data"
            return 1
        fi
    fi
    
    # Migrate Tools data
    if [[ "$old_tools_path" != "$new_tools_path" ]]; then
        info "Migrating Tools data: $old_tools_path → $new_tools_path"
        
        # Create new directory
        sudo mkdir -p "$new_tools_path"
        
        # Move data with preserved permissions
        if sudo mv "$old_tools_path"/* "$new_tools_path/" 2>/dev/null; then
            # Set ownership
            sudo chown -R "$PORTAINER_USER:$PORTAINER_USER" "$new_tools_path"
            
            # Remove old directory if empty
            sudo rmdir "$old_tools_path" 2>/dev/null || warn "Could not remove old Tools directory"
            
            success "Tools data migrated successfully"
        else
            error "Failed to migrate Tools data"
            return 1
        fi
    fi
    
    # Migrate Backup data
    if [[ "$old_backup_path" != "$new_backup_path" ]]; then
        info "Migrating Backup data: $old_backup_path → $new_backup_path"
        
        # Create new directory
        sudo mkdir -p "$new_backup_path"
        
        # Move data with preserved permissions
        if sudo mv "$old_backup_path"/* "$new_backup_path/" 2>/dev/null; then
            # Set ownership
            sudo chown -R "$PORTAINER_USER:$PORTAINER_USER" "$new_backup_path"
            
            # Remove old directory if empty
            sudo rmdir "$old_backup_path" 2>/dev/null || warn "Could not remove old Backup directory"
            
            success "Backup data migrated successfully"
        else
            error "Failed to migrate Backup data"
            return 1
        fi
    fi
}

# Update configurations after migration
update_configurations_for_migration() {
    local old_portainer_path="$1"
    local new_portainer_path="$2"
    local old_tools_path="$3"
    local new_tools_path="$4"
    local old_backup_path="$5"
    local new_backup_path="$6"
    
    info "Updating configurations for new paths..."
    
    # Update global configuration
    PORTAINER_PATH="$new_portainer_path"
    TOOLS_PATH="$new_tools_path"
    BACKUP_PATH="$new_backup_path"
    
    # Save updated configuration
    save_config
    
    # Update docker-compose files if they exist
    local portainer_compose="$new_portainer_path/docker-compose.yml"
    if [[ -f "$portainer_compose" ]]; then
        info "Updating Portainer compose file paths..."
        # Only replace path references in volume definitions, not image names
        sudo sed -i "s|$old_portainer_path/data|$new_portainer_path/data|g" "$portainer_compose" 2>/dev/null || warn "Failed to update Portainer compose paths"
    fi
    
    local npm_compose="$new_tools_path/nginx-proxy-manager/docker-compose.yml"
    if [[ -f "$npm_compose" ]]; then
        info "Updating NPM compose file paths..."
        # Only replace path references in volume definitions, not image names
        sudo sed -i "s|$old_tools_path/nginx-proxy-manager/data|$new_tools_path/nginx-proxy-manager/data|g" "$npm_compose" 2>/dev/null || warn "Failed to update NPM compose paths"
        sudo sed -i "s|$old_tools_path/nginx-proxy-manager/letsencrypt|$new_tools_path/nginx-proxy-manager/letsencrypt|g" "$npm_compose" 2>/dev/null || warn "Failed to update NPM compose paths"
    fi
    
    success "Configurations updated successfully"
}

# Restart services and validate after migration
restart_and_validate_services() {
    local stack_inventory="$1"
    
    info "Restarting services after migration..."
    
    # First, restart Portainer with new paths
    info "Restarting Portainer..."
    if sudo -u "$PORTAINER_USER" docker compose -f "$PORTAINER_PATH/docker-compose.yml" up -d; then
        success "Portainer restarted successfully"
    else
        error "Failed to restart Portainer"
        return 1
    fi
    
    # Wait for Portainer to be ready
    local max_wait=120  # Increased timeout for containers with health checks
    local wait_count=0
    while [[ $wait_count -lt $max_wait ]]; do
        if curl -s -f "http://localhost:9000/api/system/status" >/dev/null 2>&1; then
            success "Portainer is ready"
            break
        fi
        sleep 2
        ((wait_count+=2))
    done
    
    if [[ $wait_count -ge $max_wait ]]; then
        error "Portainer failed to start within $max_wait seconds"
        return 1
    fi
    
    # Restart other services using Portainer API
    info "Restarting other services..."
    
    # Get stacks from inventory and restart them
    local stacks=$(jq -r '.stacks[] | select(.name != "portainer") | .name' "$stack_inventory" 2>/dev/null)
    
    if [[ -n "$stacks" ]]; then
        while IFS= read -r stack_name; do
            if [[ -n "$stack_name" ]]; then
                info "Restarting stack: $stack_name"
                restart_stack_via_api "$stack_name"
            fi
        done <<< "$stacks"
    fi
    
    # Validate services are accessible
    info "Validating services..."
    
    # Check Portainer
    if curl -s -f "http://localhost:9000/api/system/status" >/dev/null 2>&1; then
        success "Portainer is accessible"
    else
        error "Portainer is not accessible"
        return 1
    fi
    
    # Check nginx-proxy-manager
    if curl -s -f "http://localhost:81/api/system/status" >/dev/null 2>&1; then
        success "nginx-proxy-manager is accessible"
    else
        warn "nginx-proxy-manager may not be accessible (this is normal if it's not deployed yet)"
    fi
    
    success "Service validation completed"
}

# Restart a stack via Portainer API
restart_stack_via_api() {
    local stack_name="$1"
    
    if [[ ! -f "$PORTAINER_PATH/.credentials" ]]; then
        warn "Cannot restart stack $stack_name: Portainer credentials not found"
        return 1
    fi
    
    source "$PORTAINER_PATH/.credentials"
    
    # Login to Portainer API
    local auth_response
    auth_response=$(curl -s -X POST "$PORTAINER_API_URL/auth" \
        -H "Content-Type: application/json" \
        -d "{\"Username\": \"$PORTAINER_ADMIN_USERNAME\", \"Password\": \"$PORTAINER_ADMIN_PASSWORD\"}")
    
    local jwt_token
    jwt_token=$(echo "$auth_response" | jq -r '.jwt // empty')
    
    if [[ -z "$jwt_token" ]]; then
        warn "Failed to authenticate with Portainer API for stack restart"
        return 1
    fi
    
    # Find stack ID
    local stacks_response
    stacks_response=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/stacks")
    
    local stack_id
    stack_id=$(echo "$stacks_response" | jq -r ".[] | select(.Name == \"$stack_name\") | .Id")
    
    if [[ -z "$stack_id" || "$stack_id" == "null" ]]; then
        warn "Stack $stack_name not found for restart"
        return 1
    fi
    
    # Restart stack
    local restart_response
    restart_response=$(curl -s -X POST -H "Authorization: Bearer $jwt_token" \
        "$PORTAINER_API_URL/stacks/$stack_id/stop")
    
    sleep 5
    
    restart_response=$(curl -s -X POST -H "Authorization: Bearer $jwt_token" \
        "$PORTAINER_API_URL/stacks/$stack_id/start")
    
    success "Stack $stack_name restarted via API"
}

# Get public IP address
get_public_ip() {
    local ip=""
    
    # Try multiple methods to get public IP
    if command -v curl >/dev/null 2>&1; then
        ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        ip=$(wget -qO- --timeout=5 ifconfig.me 2>/dev/null || wget -qO- --timeout=5 ipinfo.io/ip 2>/dev/null)
    fi
    
    # Validate IP format
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "$ip"
    else
        echo ""
    fi
}

# Check DNS resolution using dig or nslookup with timeout
check_dns_resolution() {
    local domain="$1"
    local expected_ip="$2"
    local timeout_seconds="${3:-10}"  # Default 10 second timeout
    
    local resolved_ip=""
    local dns_chain=""
    
    # Try dig first (more reliable) with timeout
    if command -v dig >/dev/null 2>&1; then
        # Get the complete DNS resolution chain with timeout
        local dig_output
        dig_output=$(timeout "$timeout_seconds" dig +short "$domain" 2>/dev/null || echo "")
        
        if [[ -n "$dig_output" ]]; then
            # dig +short returns the complete chain in order
            # Last line should be the final IP, earlier lines are CNAMEs
            local lines=()
            while IFS= read -r line; do
                [[ -n "$line" ]] && lines+=("$line")
            done <<< "$dig_output"
            
            if [[ ${#lines[@]} -gt 0 ]]; then
                # Build the DNS chain representation
                for line in "${lines[@]}"; do
                    # Remove trailing dots from CNAMEs
                    local clean_line="${line%.}"
                    dns_chain="${dns_chain}${clean_line} -> "
                done
                dns_chain="${dns_chain%% -> }"  # Remove trailing arrow
                
                # The final resolved IP is the last line (compatible with older bash)
                resolved_ip="${lines[$(( ${#lines[@]} - 1 ))]}"
                # Remove trailing dot if present
                resolved_ip="${resolved_ip%.}"
            fi
        fi
    elif command -v nslookup >/dev/null 2>&1; then
        # Fallback to nslookup (less detailed) with timeout
        local nslookup_output
        nslookup_output=$(timeout "$timeout_seconds" nslookup "$domain" 2>/dev/null || echo "")
        resolved_ip=$(echo "$nslookup_output" | grep -A1 "^Name:" | grep "Address:" | awk '{print $2}' | head -1 | tr -d '\r\n ')
        dns_chain="$resolved_ip (via nslookup)"
    fi
    
    # Store DNS chain for debugging (global variable for error reporting)
    DNS_RESOLUTION_CHAIN="$dns_chain"
    
    # Validate final IP format
    if [[ -n "$resolved_ip" ]] && [[ ! "$resolved_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        resolved_ip=""
    fi
    
    # Check if resolved IP matches expected IP
    if [[ -n "$resolved_ip" ]] && [[ "$resolved_ip" == "$expected_ip" ]]; then
        return 0
    else
        # For debugging: check if we got any resolution at all
        if [[ -z "$resolved_ip" ]]; then
            DNS_RESOLUTION_CHAIN="No DNS resolution found for $domain"
        else
            DNS_RESOLUTION_CHAIN="$dns_chain (resolved to $resolved_ip, expected $expected_ip)"
        fi
        return 1
    fi
}

# DNS verification and SSL readiness check
verify_dns_and_ssl() {
    # Skip DNS verification in test environment
    if is_test_environment; then
        info "Skipping DNS verification in test environment"
        return 0
    fi
    
    info "Verifying DNS configuration and SSL readiness..."
    echo
    
    # Get public IP
    local public_ip=$(get_public_ip)
    
    if [[ -z "$public_ip" ]]; then
        warn "Could not determine public IP address"
        warn "DNS verification will be skipped"
        echo
        if ! prompt_yes_no "Continue without DNS verification?" "n"; then
            error "Setup cancelled"
            exit 1
        fi
        return 0
    fi
    
    success "Detected public IP: $public_ip"
    echo
    
    # Check DNS resolution for both domains
    local portainer_dns_ok=false
    local npm_dns_ok=false
    
    info "Checking DNS resolution for your domains..."
    
    # Construct domain names for DNS checking (without https:// prefix)
    local portainer_domain="$PORTAINER_SUBDOMAIN.$DOMAIN_NAME"
    local npm_domain="$NPM_SUBDOMAIN.$DOMAIN_NAME"
    
    # Check Portainer domain
    if check_dns_resolution "$portainer_domain" "$public_ip"; then
        success "✅ $portainer_domain resolves to $public_ip"
        if [[ -n "$DNS_RESOLUTION_CHAIN" ]]; then
            info "   DNS chain: $DNS_RESOLUTION_CHAIN"
        fi
        portainer_dns_ok=true
    else
        if [[ -n "$DNS_RESOLUTION_CHAIN" ]]; then
            error "❌ $portainer_domain DNS resolution failed"
            info "   Details: $DNS_RESOLUTION_CHAIN"
        else
            error "❌ $portainer_domain does not resolve to any IP address"
        fi
    fi
    
    # Check NPM domain
    if check_dns_resolution "$npm_domain" "$public_ip"; then
        success "✅ $npm_domain resolves to $public_ip"
        if [[ -n "$DNS_RESOLUTION_CHAIN" ]]; then
            info "   DNS chain: $DNS_RESOLUTION_CHAIN"
        fi
        npm_dns_ok=true
    else
        if [[ -n "$DNS_RESOLUTION_CHAIN" ]]; then
            error "❌ $npm_domain DNS resolution failed"
            info "   Details: $DNS_RESOLUTION_CHAIN"
        else
            error "❌ $npm_domain does not resolve to any IP address"
        fi
    fi
    
    echo
    
    # Provide DNS record instructions
    if [[ "$portainer_dns_ok" == false ]] || [[ "$npm_dns_ok" == false ]]; then
        warn "DNS records need to be configured for SSL certificates to work"
        echo
        info "Please add the following DNS records to your domain provider:"
        echo
        printf "%b\n" "${BLUE}DNS Records Required:${NC}"
        if [[ "$portainer_dns_ok" == false ]]; then
            echo "  A    $PORTAINER_SUBDOMAIN    $public_ip"
        fi
        if [[ "$npm_dns_ok" == false ]]; then
            echo "  A    $NPM_SUBDOMAIN    $public_ip"
        fi
        echo
        echo "These records typically take 5-15 minutes to propagate globally."
        echo
        
        # Offer options to user
        echo "Choose how to proceed:"
        echo "1) Wait and re-check DNS (recommended)"
        echo "2) Continue setup with HTTP-only (SSL can be configured later)"
        echo "3) Exit setup to configure DNS manually"
        echo
        
        local dns_choice
        dns_choice=$(prompt_user "Select option [1-3]" "2")
        
        case "$dns_choice" in
            1)
                echo
                info "Waiting for DNS propagation..."
                info "Waiting 30 seconds for DNS changes to propagate..."
                sleep 30
                
                # Re-check DNS with timeout - try 3 times max
                local retry_count=0
                local max_retries=3
                while [[ $retry_count -lt $max_retries ]]; do
                    info "DNS re-check attempt $((retry_count + 1))/$max_retries"
                    
                    # Check both domains again with timeout
                    local portainer_retry_ok=false
                    local npm_retry_ok=false
                    
                    if check_dns_resolution "$PORTAINER_URL" "$public_ip" 10; then
                        portainer_retry_ok=true
                    fi
                    
                    if check_dns_resolution "$NPM_URL" "$public_ip" 10; then
                        npm_retry_ok=true
                    fi
                    
                    if [[ "$portainer_retry_ok" == true ]] && [[ "$npm_retry_ok" == true ]]; then
                        success "DNS resolution successful after retry!"
                        return 0
                    fi
                    
                    retry_count=$((retry_count + 1))
                    if [[ $retry_count -lt $max_retries ]]; then
                        info "DNS still not ready, waiting 15 more seconds..."
                        sleep 15
                    fi
                done
                
                warn "DNS verification failed after $max_retries attempts"
                warn "Continuing with HTTP-only setup"
                export SKIP_SSL_CERTIFICATES=true
                return 0
                ;;
            2)
                warn "Continuing with HTTP-only setup"
                warn "SSL certificates will not be requested automatically"
                warn "You can configure SSL later through the nginx-proxy-manager UI"
                echo
                info "After DNS records are configured, you can:"
                info "1. Access nginx-proxy-manager at: http://$public_ip:81"
                info "2. Navigate to SSL Certificates and request certificates"
                info "3. Edit your proxy hosts to use HTTPS"
                echo
                
                # Set a flag to skip SSL certificate requests
                export SKIP_SSL_CERTIFICATES=true
                return 0
                ;;
            3)
                info "Setup cancelled. Please configure DNS records and run setup again."
                exit 0
                ;;
            *)
                warn "Invalid option. Continuing with HTTP-only setup..."
                export SKIP_SSL_CERTIFICATES=true
                return 0
                ;;
        esac
    else
        success "✅ DNS configuration is correct!"
        success "SSL certificates will be requested automatically"
        echo
        
        # DNS is configured correctly, SSL certificates will be requested
        export SKIP_SSL_CERTIFICATES=false
        return 0
    fi
}

# Check if Docker is installed and install if needed
install_docker() {
    info "Checking Docker installation..."
    
    if command -v docker >/dev/null 2>&1; then
        success "Docker is already installed"
        return 0
    fi
    
    info "Installing Docker..."
    
    # Update package index
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    sudo systemctl enable docker
    sudo systemctl start docker
    
    success "Docker installed successfully"
}

# Create system user for Portainer
create_portainer_user() {
    info "Creating system user: $PORTAINER_USER"
    
    if id "$PORTAINER_USER" >/dev/null 2>&1; then
        success "User $PORTAINER_USER already exists"

        # Ensure SSH keys are set up even for existing user
        setup_ssh_keys
        success "SSH key setup verified for existing user"
        return 0
    fi
    
    sudo useradd -r -s /bin/bash -d "/home/$PORTAINER_USER" -m "$PORTAINER_USER"
    
    # Add portainer user to docker group for container management
    sudo usermod -aG docker "$PORTAINER_USER"
    
    # Add portainer user to sudo group for backup operations
    sudo usermod -aG sudo "$PORTAINER_USER"
    
    # Configure passwordless sudo for portainer user (for automated backups)
    echo "$PORTAINER_USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$PORTAINER_USER" > /dev/null
    sudo chmod 440 "/etc/sudoers.d/$PORTAINER_USER"
    
    # Ensure docker service is running and portainer user can access it
    sudo systemctl restart docker
    sleep 2
    
    # Setup SSH keys for backup functionality
    setup_ssh_keys
    
    success "User $PORTAINER_USER created with SSH key pair"
}

# Setup or repair SSH keys for portainer user
setup_ssh_keys() {
    info "Setting up SSH keys for $PORTAINER_USER user..."
    
    local ssh_dir="/home/$PORTAINER_USER/.ssh"
    local ssh_key_path="$ssh_dir/id_ed25519"
    local ssh_pub_path="$ssh_dir/id_ed25519.pub"
    local auth_keys_path="$ssh_dir/authorized_keys"
    
    # Ensure SSH directory exists with proper permissions
    if [[ ! -d "$ssh_dir" ]]; then
        sudo -u "$PORTAINER_USER" mkdir -p "$ssh_dir"
        sudo chmod 700 "$ssh_dir"
        info "Created SSH directory: $ssh_dir"
    fi
    
    # Generate Ed25519 SSH key pair (modern, secure, and compact)
    info "Generating Ed25519 SSH key pair..."
    sudo -u "$PORTAINER_USER" ssh-keygen -t ed25519 -f "$ssh_key_path" -N ""
    success "Ed25519 SSH key pair generated"
    
    # Set up SSH access for backups
    if ! is_test_environment; then
        # Restricted SSH access for production
        local public_key_content=$(cat "$ssh_pub_path")
        sudo -u "$PORTAINER_USER" tee "$auth_keys_path" > /dev/null << EOF
# Restricted key for backup access only
command="rsync --server --daemon .",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty $public_key_content
EOF
        info "Set up restricted SSH access for production"
    else
        # Full SSH access for test environment
        sudo -u "$PORTAINER_USER" cp "$ssh_pub_path" "$auth_keys_path"
        info "Set up full SSH access for test environment"
    fi
    
    # Set proper permissions
    sudo chmod 600 "$ssh_key_path"
    sudo chmod 644 "$ssh_pub_path"
    sudo chmod 600 "$auth_keys_path"
    sudo chown "$PORTAINER_USER:$PORTAINER_USER" "$ssh_key_path" "$ssh_pub_path" "$auth_keys_path"
    
    success "SSH keys setup completed"
}

# Validate SSH key setup for backup functionality
validate_ssh_setup() {
    info "Validating SSH key setup..."
    
    local ssh_key_path="/home/$PORTAINER_USER/.ssh/id_ed25519"
    local ssh_pub_path="/home/$PORTAINER_USER/.ssh/id_ed25519.pub"
    local auth_keys_path="/home/$PORTAINER_USER/.ssh/authorized_keys"
    
    # Check if SSH private key exists and is readable (use sudo since files are owned by portainer)
    if ! sudo test -f "$ssh_key_path"; then
        error "SSH private key not found at: $ssh_key_path"
        error "NAS backup functionality will not work without SSH keys"
        return 1
    fi
    
    # Check if SSH public key exists
    if ! sudo test -f "$ssh_pub_path"; then
        error "SSH public key not found at: $ssh_pub_path"
        return 1
    fi
    
    # Check if authorized_keys exists
    if ! sudo test -f "$auth_keys_path"; then
        error "SSH authorized_keys not found at: $auth_keys_path"
        return 1
    fi
    
    # Check permissions
    local private_perms=$(sudo stat -c "%a" "$ssh_key_path" 2>/dev/null)
    local auth_perms=$(sudo stat -c "%a" "$auth_keys_path" 2>/dev/null)
    
    if [[ "$private_perms" != "600" ]]; then
        error "SSH private key has incorrect permissions: $private_perms (should be 600)"
        return 1
    fi
    
    if [[ "$auth_perms" != "600" ]]; then
        error "SSH authorized_keys has incorrect permissions: $auth_perms (should be 600)"
        return 1
    fi
    
    # Test if SSH key can be read by the script
    if ! sudo cat "$ssh_key_path" >/dev/null 2>&1; then
        error "Cannot read SSH private key (permission issue)"
        return 1
    fi
    
    # Test SSH connectivity (basic self-connection test in test environment)
    if is_test_environment; then
        info "Testing SSH connectivity..."
        if sudo -u "$PORTAINER_USER" ssh -i "$ssh_key_path" -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no \
           "$PORTAINER_USER@localhost" 'echo "SSH test successful"' >/dev/null 2>&1; then
            success "SSH connectivity test passed"
        else
            warn "SSH connectivity test failed (this may be normal if SSH server is not configured)"
            warn "NAS backup functionality will still work if remote SSH access is properly configured"
        fi
    fi
    
    success "SSH key setup validation passed"
    success "NAS backup functionality will be available"
    return 0
}

# Create required directories with proper permissions
create_directories() {
    info "Creating required directories..."
    
    # Create Portainer and tools directories (owned by portainer user)
    local portainer_dirs=("$PORTAINER_PATH" "$TOOLS_PATH")
    
    for dir in "${portainer_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            sudo mkdir -p "$dir"
            info "Created directory: $dir"
        fi
        
        sudo chown -R "$PORTAINER_USER:$PORTAINER_USER" "$dir"
        sudo chmod -R 755 "$dir"
    done
    
    # Create backup directory with system-wide access (owned by root)
    if [[ ! -d "$BACKUP_PATH" ]]; then
        sudo mkdir -p "$BACKUP_PATH"
        info "Created directory: $BACKUP_PATH"
    fi
    
    # Set backup directory permissions for system-wide access
    # - Root ownership for security
    # - 755 permissions so portainer user can read/write backup files
    sudo chown root:root "$BACKUP_PATH"
    sudo chmod 755 "$BACKUP_PATH"
    
    # Create nginx-proxy-manager subdirectory
    sudo mkdir -p "$TOOLS_PATH/nginx-proxy-manager"
    sudo chown -R "$PORTAINER_USER:$PORTAINER_USER" "$TOOLS_PATH/nginx-proxy-manager"
    
    success "Directories created with proper permissions"
    info "  - $PORTAINER_PATH and $TOOLS_PATH: owned by $PORTAINER_USER"
    info "  - $BACKUP_PATH: system-wide location with root ownership"
}

# Create Docker network
create_docker_network() {
    info "Creating prod-network..."
    
    if sudo -u "$PORTAINER_USER" docker network ls | grep -q "prod-network"; then
        success "prod-network already exists"
        return 0
    fi
    
    sudo -u "$PORTAINER_USER" docker network create prod-network
    success "prod-network created"
}

# Generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Prepare nginx-proxy-manager files for Portainer deployment
prepare_nginx_proxy_manager_files() {
    info "Preparing nginx-proxy-manager files..."
    
    local npm_path="$TOOLS_PATH/nginx-proxy-manager"
    
    # Create docker-compose.yml for nginx-proxy-manager with absolute paths
    sudo -u "$PORTAINER_USER" tee "$npm_path/docker-compose.yml" > /dev/null << EOF
services:
  nginx-proxy-manager:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: nginx-proxy-manager
    restart: always
    ports:
      - '80:80'
      - '443:443'
      - '81:81'
    volumes:
      - $npm_path/data:/data
      - $npm_path/letsencrypt:/etc/letsencrypt
    networks:
      - prod-network
    environment:
      DB_SQLITE_FILE: "/data/database.sqlite"
      DISABLE_IPV6: 'true'

networks:
  prod-network:
    external: true
EOF

    # Create credentials file with domain-based values
    local npm_admin_email="admin@${DOMAIN_NAME}"
    local npm_admin_password="AdminPassword123!"
    sudo -u "$PORTAINER_USER" tee "$npm_path/.credentials" > /dev/null << EOF
NPM_ADMIN_EMAIL=${npm_admin_email}
NPM_ADMIN_PASSWORD=${npm_admin_password}
NPM_API_URL=http://localhost:81/api
EOF

    # Create data directories with proper ownership
    sudo -u "$PORTAINER_USER" mkdir -p "$npm_path/data" "$npm_path/letsencrypt"
    sudo chmod 755 "$npm_path/data" "$npm_path/letsencrypt"
    
    success "nginx-proxy-manager files prepared"
    info "Compose file: $npm_path/docker-compose.yml"
    info "Credentials file: $npm_path/.credentials"
    info "Data directories: $npm_path/data, $npm_path/letsencrypt"
    info "Will be deployed as a Portainer stack"
}

# Configure nginx-proxy-manager via API
configure_nginx_proxy_manager() {
    info "Configuring nginx-proxy-manager..."
    
    local npm_path="$TOOLS_PATH/nginx-proxy-manager"
    
    # Load custom credentials from setup
    if [[ -f "$npm_path/.credentials" ]]; then
        source "$npm_path/.credentials" || true
    fi
    
    # nginx-proxy-manager always starts with default credentials
    local auth_email="admin@example.com"
    local auth_password="changeme"
    
    # Wait for nginx-proxy-manager to complete initialization
    info "Waiting for nginx-proxy-manager to complete initialization..."
    local max_attempts=30  # Increased to 5 minutes (30 * 10 seconds)
    local attempt=1
    local api_ready=false
    
    while [[ $attempt -le $max_attempts ]]; do
        # First check if the web interface is responsive
        if curl -s --connect-timeout 5 "http://localhost:81/" > /dev/null 2>&1; then
            # Check if API endpoint is available
            local api_status=$(curl -s -w "%{http_code}" -o /dev/null --connect-timeout 5 "http://localhost:81/api/schema" 2>/dev/null || echo "000")
            
            if [[ "$api_status" == "200" ]]; then
                # Try to authenticate with default credentials
                local test_token
                test_token=$(curl -s --connect-timeout 5 -X POST "http://localhost:81/api/tokens" \
                    -H "Content-Type: application/json" \
                    -d "{\"identity\": \"$auth_email\", \"secret\": \"$auth_password\"}" 2>/dev/null | \
                    jq -r '.token // empty' 2>/dev/null)
                
                if [[ -n "$test_token" && "$test_token" != "null" ]]; then
                    info "nginx-proxy-manager API is ready and authenticated"
                    api_ready=true
                    break
                fi
            fi
        fi
        
        # Progress indicator with more detailed status
        if [[ $((attempt % 6)) -eq 0 ]]; then
            info "Still waiting for nginx-proxy-manager initialization... (${attempt}0 seconds elapsed)"
            info "This can take up to 5 minutes on first startup while database and keys are generated"
        else
            echo -n "."
        fi
        
        sleep 10
        ((attempt++))
    done
    
    if [[ "$api_ready" != "true" ]]; then
        warn "nginx-proxy-manager API not available after $((max_attempts * 10)) seconds"
        warn ""
        warn "Possible solutions:"
        warn "1. nginx-proxy-manager may need more time to initialize on slower systems"
        warn "2. Complete the first-run setup manually at: http://localhost:81"
        warn "3. Check nginx-proxy-manager logs: docker logs nginx-proxy-manager"
        warn ""
        warn "Default credentials for manual setup: admin@example.com / changeme"
        warn ""
        
        # Offer to continue with manual setup option
        if ! is_test_environment; then
            echo
            if prompt_yes_no "Would you like to continue setup and configure nginx-proxy-manager manually later?" "y"; then
                info "Continuing setup - you can configure nginx-proxy-manager manually later"
                info "Access it at: http://localhost:81 with admin@example.com / changeme"
                return 0
            else
                error "Setup cannot continue without nginx-proxy-manager configuration"
                return 1
            fi
        else
            # In test environment, continue but don't fail
            warn "Test environment: continuing without nginx-proxy-manager configuration"
            return 0
        fi
    fi
    
    # Login and get token (using default credentials first)
    local token
    token=$(curl -s -X POST "http://localhost:81/api/tokens" \
        -H "Content-Type: application/json" \
        -d "{\"identity\": \"$auth_email\", \"secret\": \"$auth_password\"}" | \
        jq -r '.token // empty')
    
    if [[ -z "$token" ]]; then
        warn "Failed to authenticate with nginx-proxy-manager"
        warn "nginx-proxy-manager is running but API configuration failed"
        warn "You can configure it manually at: http://localhost:81"
        warn "Default credentials: admin@example.com / changeme"
        return 0
    fi
    
    info "Successfully authenticated with nginx-proxy-manager API"
    
    # Update admin user profile and password (skip in test environment to avoid conflicts)
    if ! is_test_environment; then
        local user_id
        user_id=$(curl -s -H "Authorization: Bearer $token" "http://localhost:81/api/users" | \
            jq -r '.[] | select(.email == "admin@example.com") | .id')
        
        if [[ -n "$user_id" ]]; then
            # Update user profile (name, nickname, email)
            info "Updating admin user profile..."
            curl -s -X PUT "http://localhost:81/api/users/$user_id" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" \
                -d "{
                    \"name\": \"Zuptalo\",
                    \"nickname\": \"Zupi\",
                    \"email\": \"$NPM_ADMIN_EMAIL\",
                    \"roles\": [\"admin\"],
                    \"is_disabled\": false
                }" >/dev/null
            
            # Update admin password
            info "Updating admin password..."
            curl -s -X PUT "http://localhost:81/api/users/$user_id/auth" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" \
                -d "{
                    \"type\": \"password\",
                    \"current\": \"changeme\",
                    \"secret\": \"$NPM_ADMIN_PASSWORD\"
                }" >/dev/null
            
            success "Updated admin user profile and password"
            
            # Get new authentication token with updated credentials
            info "Re-authenticating with updated credentials..."
            local new_token
            new_token=$(curl -s -X POST "http://localhost:81/api/tokens" \
                -H "Content-Type: application/json" \
                -d "{\"identity\": \"$NPM_ADMIN_EMAIL\", \"secret\": \"$NPM_ADMIN_PASSWORD\"}" | \
                jq -r '.token // empty')
            
            if [[ -n "$new_token" ]]; then
                success "Re-authenticated successfully with updated credentials"
                token="$new_token"
            else
                warn "Re-authentication failed, using original token"
            fi
        fi
    fi
    
    # Create proxy hosts for both services
    create_portainer_proxy_host "$token"
    create_npm_proxy_host "$token"
}

# Create proxy host for Portainer
create_portainer_proxy_host() {
    local token="$1"
    
    # Extract domain name from URL (remove https:// prefix)
    local portainer_domain
    portainer_domain=$(echo "$PORTAINER_URL" | sed 's|https\?://||')
    
    info "Creating proxy host for $portainer_domain..."
    
    # Determine SSL configuration based on DNS setup
    local certificate_config="0"
    local ssl_forced="false"
    local hsts_enabled="false"
    local hsts_subdomains="false"
    local http2_support="false"
    
    if ! is_test_environment && [[ "${SKIP_SSL_CERTIFICATES:-false}" != "true" ]]; then
        certificate_config="\"new\""
        ssl_forced="true"
        hsts_enabled="true"
        hsts_subdomains="true"
        http2_support="true"
    fi
    
    # Create proxy host with complete configuration including SSL
    local proxy_response
    proxy_response=$(curl -s -X POST "http://localhost:81/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_names\": [\"$portainer_domain\"],
            \"forward_scheme\": \"http\",
            \"forward_host\": \"portainer\",
            \"forward_port\": 9000,
            \"caching_enabled\": true,
            \"block_exploits\": true,
            \"allow_websocket_upgrade\": true,
            \"access_list_id\": \"0\",
            \"certificate_id\": $certificate_config,
            \"ssl_forced\": $ssl_forced,
            \"http2_support\": $http2_support,
            \"hsts_enabled\": $hsts_enabled,
            \"hsts_subdomains\": $hsts_subdomains,
            \"meta\": {
                \"letsencrypt_email\": \"$NPM_ADMIN_EMAIL\",
                \"letsencrypt_agree\": true,
                \"dns_challenge\": false
            },
            \"advanced_config\": \"\",
            \"locations\": []
        }")
    
    local proxy_id
    proxy_id=$(echo "$proxy_response" | jq -r '.id // empty')
    
    if [[ -n "$proxy_id" ]]; then
        if [[ "$certificate_config" == "\"new\"" ]]; then
            success "Proxy host created for $portainer_domain (ID: $proxy_id) with SSL certificate"
            info "HTTPS URL: https://$portainer_domain"
        else
            success "Proxy host created for $portainer_domain (ID: $proxy_id) - HTTP only"
            warn "HTTP URL: http://$portainer_domain"
            if is_test_environment; then
                info "SSL skipped in test environment"
            else
                info "SSL skipped - configure DNS records and rerun setup for HTTPS"
            fi
        fi
    else
        error "Failed to create proxy host for $portainer_domain"
        warn "API Response: $proxy_response"
    fi
}

# Create proxy host for nginx-proxy-manager admin interface
create_npm_proxy_host() {
    local token="$1"
    
    # Extract domain name from URL (remove https:// prefix)
    local npm_domain
    npm_domain=$(echo "$NPM_URL" | sed 's|https\?://||')
    
    info "Creating proxy host for $npm_domain..."
    
    # Determine SSL configuration based on DNS setup
    local certificate_config="0"
    local ssl_forced="false"
    local hsts_enabled="false"
    local hsts_subdomains="false"
    local http2_support="false"
    
    if ! is_test_environment && [[ "${SKIP_SSL_CERTIFICATES:-false}" != "true" ]]; then
        certificate_config="\"new\""
        ssl_forced="true"
        hsts_enabled="true"
        hsts_subdomains="true"
        http2_support="true"
    fi
    
    # Create proxy host for NPM admin interface with complete configuration
    # Forward to nginx-proxy-manager container instead of Docker gateway IP
    local proxy_response
    proxy_response=$(curl -s -X POST "http://localhost:81/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_names\": [\"$npm_domain\"],
            \"forward_scheme\": \"http\",
            \"forward_host\": \"nginx-proxy-manager\",
            \"forward_port\": 81,
            \"caching_enabled\": true,
            \"block_exploits\": true,
            \"allow_websocket_upgrade\": true,
            \"access_list_id\": \"0\",
            \"certificate_id\": $certificate_config,
            \"ssl_forced\": $ssl_forced,
            \"http2_support\": $http2_support,
            \"hsts_enabled\": $hsts_enabled,
            \"hsts_subdomains\": $hsts_subdomains,
            \"meta\": {
                \"letsencrypt_email\": \"$NPM_ADMIN_EMAIL\",
                \"letsencrypt_agree\": true,
                \"dns_challenge\": false
            },
            \"advanced_config\": \"\",
            \"locations\": []
        }")
    
    local proxy_id
    proxy_id=$(echo "$proxy_response" | jq -r '.id // empty')
    
    if [[ -n "$proxy_id" ]]; then
        if [[ "$certificate_config" == "\"new\"" ]]; then
            success "Proxy host created for $npm_domain (ID: $proxy_id) with SSL certificate"
            info "HTTPS URL: https://$npm_domain"
        else
            success "Proxy host created for $npm_domain (ID: $proxy_id) - HTTP only"
            warn "HTTP URL: http://$npm_domain"
            if is_test_environment; then
                info "SSL skipped in test environment"
            else
                info "SSL skipped - configure DNS records and rerun setup for HTTPS"
            fi
        fi
    else
        error "Failed to create proxy host for $npm_domain"
        warn "API Response: $proxy_response"
    fi
}

# Deploy Portainer
deploy_portainer() {
    info "Deploying Portainer..."
    
    # Use default Portainer setup - no pre-configured admin password
    # Portainer will prompt for admin setup on first access
    
    # Create docker-compose.yml for Portainer
    sudo -u "$PORTAINER_USER" tee "$PORTAINER_PATH/docker-compose.yml" > /dev/null << EOF
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    ports:
      - "9000:9000"
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./data:/data
    networks:
      - prod-network

networks:
  prod-network:
    external: true
EOF

    # Create credentials file with setup credentials (meeting Portainer requirements)
    local portainer_admin_password="AdminPassword123!"
    local portainer_admin_username="admin@${DOMAIN_NAME}"
    sudo -u "$PORTAINER_USER" tee "$PORTAINER_PATH/.credentials" > /dev/null << EOF
PORTAINER_ADMIN_USERNAME=${portainer_admin_username}
PORTAINER_ADMIN_PASSWORD=${portainer_admin_password}
PORTAINER_URL=https://${PORTAINER_URL}
PORTAINER_API_URL=http://localhost:9000/api
EOF

    # Deploy Portainer
    cd "$PORTAINER_PATH"
    sudo -u "$PORTAINER_USER" docker compose up -d
    
    # Wait for Portainer to be ready
    info "Waiting for Portainer to start..."
    
    local max_attempts=12
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if sudo -u "$PORTAINER_USER" docker ps | grep -q "portainer" && curl -s -f "http://localhost:9000/api/system/status" >/dev/null 2>&1; then
            success "Portainer deployed successfully"
            info "Portainer URL: https://$PORTAINER_URL"
            
            # Initialize Portainer admin user
            initialize_portainer_admin
            return 0
        fi
        info "Waiting for Portainer to be ready... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    # Even if the API check fails, if the container is running, consider it a success
    if sudo -u "$PORTAINER_USER" docker ps | grep -q "portainer"; then
        warn "Portainer container is running but API may not be ready yet"
        info "Portainer URL: https://$PORTAINER_URL"
        info "Credentials stored in: $PORTAINER_PATH/.credentials"
        return 0
    else
        error "Portainer failed to start"
        return 1
    fi
}

# Initialize Portainer admin user via API
initialize_portainer_admin() {
    info "Initializing Portainer admin user..."
    
    # Load credentials
    source "$PORTAINER_PATH/.credentials"
    
    # Initialize admin user
    local init_response
    init_response=$(curl -s -X POST "$PORTAINER_API_URL/users/admin/init" \
        -H "Content-Type: application/json" \
        -d "{\"Username\": \"$PORTAINER_ADMIN_USERNAME\", \"Password\": \"$PORTAINER_ADMIN_PASSWORD\"}")
    
    # Check if initialization was successful
    if echo "$init_response" | jq -e '.Id' >/dev/null 2>&1; then
        success "Portainer admin user initialized"
        
        # Create local Docker endpoint immediately
        if ! create_local_docker_endpoint; then
            warn "Could not create local Docker endpoint, but continuing..."
        fi
        
        # Create NPM stack in Portainer
        create_npm_stack_in_portainer || {
            error "Failed to create nginx-proxy-manager stack in Portainer"
            error "Setup cannot continue without Portainer-managed NPM stack"
            exit 1
        }
    else
        warn "Portainer admin initialization may have failed or was already done"
    fi
}

# Create local Docker endpoint in Portainer
create_local_docker_endpoint() {
    info "Creating local Docker endpoint in Portainer..."
    
    # Get authentication token
    local auth_response
    auth_response=$(curl -s -X POST "$PORTAINER_API_URL/auth" \
        -H "Content-Type: application/json" \
        -d "{\"Username\": \"$PORTAINER_ADMIN_USERNAME\", \"Password\": \"$PORTAINER_ADMIN_PASSWORD\"}")
    
    local jwt_token
    jwt_token=$(echo "$auth_response" | jq -r '.jwt // empty')
    
    if [[ -z "$jwt_token" ]]; then
        warn "Could not authenticate with Portainer to create endpoint"
        return 1
    fi
    
    # Create the local Docker endpoint using form-data (as UI does)
    local create_response
    create_response=$(curl -s -X POST "$PORTAINER_API_URL/endpoints" \
        -H "Authorization: Bearer $jwt_token" \
        -F "Name=local" \
        -F "EndpointCreationType=1" \
        -F "URL=" \
        -F "PublicURL=" \
        -F "TagIds=[]" \
        -F "ContainerEngine=docker" \
        2>/dev/null)
    
    local endpoint_id
    endpoint_id=$(echo "$create_response" | jq -r '.Id // empty' 2>/dev/null || echo "")
    
    if [[ -n "$endpoint_id" && "$endpoint_id" != "null" && "$endpoint_id" != "empty" ]]; then
        success "Created local Docker endpoint with ID: $endpoint_id"
        return 0
    else
        warn "Could not create local Docker endpoint"
        warn "Create response: $create_response"
        return 1
    fi
}

# Create nginx-proxy-manager stack in Portainer
create_npm_stack_in_portainer() {
    info "Creating nginx-proxy-manager stack in Portainer..."
    
    # Get authentication token
    local auth_response
    auth_response=$(curl -s -X POST "$PORTAINER_API_URL/auth" \
        -H "Content-Type: application/json" \
        -d "{\"Username\": \"$PORTAINER_ADMIN_USERNAME\", \"Password\": \"$PORTAINER_ADMIN_PASSWORD\"}")
    
    local jwt_token
    jwt_token=$(echo "$auth_response" | jq -r '.jwt // empty')
    
    if [[ -z "$jwt_token" ]]; then
        warn "Could not authenticate with Portainer to create NPM stack"
        return 0
    fi
    
    # Get endpoint ID for local Docker environment (should exist since we just created it)
    info "Getting endpoint ID from Portainer..."
    local endpoints_response
    endpoints_response=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/endpoints" 2>/dev/null || echo "")
    
    local endpoint_id
    if [[ -n "$endpoints_response" && "$endpoints_response" != "[]" && "$endpoints_response" != "null" ]]; then
        # Try to get the local endpoint (name="local") or first endpoint
        endpoint_id=$(echo "$endpoints_response" | jq -r '.[] | select(.Name == "local") | .Id // empty' 2>/dev/null || echo "")
        if [[ -z "$endpoint_id" || "$endpoint_id" == "empty" ]]; then
            # Fallback to first endpoint if no "local" endpoint found
            endpoint_id=$(echo "$endpoints_response" | jq -r '.[0].Id // empty' 2>/dev/null || echo "")
        fi
    fi
    
    # Check if we got a valid endpoint ID
    if [[ -z "$endpoint_id" || "$endpoint_id" == "null" || "$endpoint_id" == "empty" ]]; then
        error "Could not get endpoint ID from Portainer"
        error "Endpoints response: $endpoints_response"
        return 1
    fi
    
    info "Using endpoint ID: $endpoint_id"
    
    # Create NPM stack using proper API format
    local npm_compose_content=$(cat "$TOOLS_PATH/nginx-proxy-manager/docker-compose.yml")
    
    local stack_response
    stack_response=$(curl -s -X POST "$PORTAINER_API_URL/stacks/create/standalone/string?endpointId=$endpoint_id" \
        -H "Authorization: Bearer $jwt_token" \
        -H "Content-Type: application/json" \
        -d "{
            \"method\": \"string\",
            \"type\": \"standalone\",
            \"Name\": \"nginx-proxy-manager\",
            \"StackFileContent\": $(echo "$npm_compose_content" | jq -Rs .),
            \"Env\": []
        }")
    
    local stack_id
    stack_id=$(echo "$stack_response" | jq -r '.Id // empty')
    
    if [[ -n "$stack_id" && "$stack_id" != "null" ]]; then
        success "nginx-proxy-manager stack created in Portainer (ID: $stack_id)"
        info "Stack is now managed through Portainer UI"
        
        # Wait for stack to be deployed
        info "Waiting for nginx-proxy-manager stack to be ready..."
        local attempts=0
        local max_attempts=10
        
        while [[ $attempts -lt $max_attempts ]]; do
            if sudo -u "$PORTAINER_USER" docker ps | grep -q "nginx-proxy-manager"; then
                success "nginx-proxy-manager stack is running"
                return 0
            fi
            sleep 3
            ((attempts++))
        done
        
        warn "nginx-proxy-manager stack created but container not running yet"
        return 0
    else
        error "Could not create NPM stack in Portainer"
        error "API Response: $stack_response"
        error "Endpoint ID used: $endpoint_id"
        error "NPM must be deployed as a Portainer stack - no fallback allowed"
        return 1
    fi
}


# Get detailed stack states from Portainer with enhanced capture
get_stack_states() {
    local output_file="$1"
    
    if [[ ! -f "$PORTAINER_PATH/.credentials" ]]; then
        warn "Portainer credentials not found, skipping stack state capture"
        echo "{}" > "$output_file"
        return 0
    fi
    
    source "$PORTAINER_PATH/.credentials"
    
    # Login to Portainer API
    local auth_response
    auth_response=$(curl -s -X POST "$PORTAINER_API_URL/auth" \
        -H "Content-Type: application/json" \
        -d "{\"Username\": \"$PORTAINER_ADMIN_USERNAME\", \"Password\": \"$PORTAINER_ADMIN_PASSWORD\"}")
    
    local jwt_token
    jwt_token=$(echo "$auth_response" | jq -r '.jwt // empty')
    
    if [[ -z "$jwt_token" ]]; then
        # Check if it's an initialization timeout (expected for fresh Portainer)
        if echo "$auth_response" | grep -q "initialization timeout"; then
            info "Portainer requires initial admin setup via web UI"
        else
            warn "Failed to authenticate with Portainer API"
            warn "Response: $auth_response"
        fi
        echo "{}" > "$output_file"
        return 0
    fi
    
    # Get basic stack information
    local stacks_response
    stacks_response=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/stacks")
    
    # Create enhanced state information with detailed capture
    local enhanced_stacks="[]"
    if [[ "$stacks_response" != "null" && -n "$stacks_response" ]]; then
        info "Capturing enhanced stack details..."
        
        # Process each stack to get detailed information
        local stack_ids
        stack_ids=$(echo "$stacks_response" | jq -r '.[].Id')
        
        local stack_details_array="[]"
        while read -r stack_id; do
            if [[ -n "$stack_id" && "$stack_id" != "null" ]]; then
                info "Capturing detailed information for stack ID: $stack_id"
                
                # Get detailed stack information
                local stack_detail
                stack_detail=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/stacks/$stack_id")
                
                if [[ "$stack_detail" != "null" && -n "$stack_detail" ]]; then
                    # Get stack file (compose.yml content)
                    local stack_file
                    stack_file=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/stacks/$stack_id/file")
                    
                    # Enhance the stack detail with compose file content
                    local enhanced_stack
                    enhanced_stack=$(echo "$stack_detail" | jq --arg stack_file "$stack_file" '{
                        id: .Id,
                        name: .Name,
                        status: .Status,
                        type: .Type,
                        endpoint_id: .EndpointId,
                        namespace: .Namespace,
                        created_date: .CreationDate,
                        updated_date: .UpdateDate,
                        created_by: .CreatedBy,
                        updated_by: .UpdatedBy,
                        resource_control: .ResourceControl,
                        auto_update: .AutoUpdate,
                        git_config: .GitConfig,
                        env_variables: .Env,
                        entry_point: .EntryPoint,
                        additional_files: .AdditionalFiles,
                        compose_file_content: $stack_file,
                        project_path: .ProjectPath,
                        swarm_id: .SwarmId,
                        is_compose_format: .IsComposeFormat
                    }')
                    
                    # Add to details array
                    stack_details_array=$(echo "$stack_details_array" | jq --argjson stack "$enhanced_stack" '. + [$stack]')
                else
                    warn "Failed to get detailed information for stack $stack_id"
                fi
            fi
        done <<< "$stack_ids"
        
        enhanced_stacks="$stack_details_array"
    fi
    
    # Create final state structure with metadata
    local final_state
    final_state=$(jq -n --argjson stacks "$enhanced_stacks" '{
        capture_timestamp: (now | strftime("%Y-%m-%d %H:%M:%S")),
        capture_version: "enhanced-v2",
        total_stacks: ($stacks | length),
        stacks: $stacks
    }')
    
    echo "$final_state" > "$output_file"
    local stack_count
    stack_count=$(echo "$enhanced_stacks" | jq -r 'length')
    success "Enhanced stack states captured: $stack_count stacks with complete configuration details"
}

# Gracefully stop all stacks through Portainer API
gracefully_stop_all_stacks() {
    info "Gracefully stopping all stacks through Portainer API..."
    
    # Check if we can access Portainer API
    if ! curl -s "$PORTAINER_API_URL/status" >/dev/null 2>&1; then
        warn "Portainer API not accessible, skipping graceful stack shutdown"
        return 0
    fi
    
    # Load credentials and authenticate
    if [[ -f "$PORTAINER_PATH/.credentials" ]]; then
        source "$PORTAINER_PATH/.credentials"
        
        local auth_response
        auth_response=$(curl -s -X POST "$PORTAINER_API_URL/auth" \
            -H "Content-Type: application/json" \
            -d "{\"Username\": \"$PORTAINER_ADMIN_USERNAME\", \"Password\": \"$PORTAINER_ADMIN_PASSWORD\"}")
        
        local jwt_token
        jwt_token=$(echo "$auth_response" | jq -r '.jwt // empty' 2>/dev/null)
        
        if [[ -n "$jwt_token" && "$jwt_token" != "null" ]]; then
            # Get all stacks
            local stacks_response
            stacks_response=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/stacks")
            
            # Stop each stack
            echo "$stacks_response" | jq -r '.[].Id' 2>/dev/null | while read -r stack_id; do
                if [[ -n "$stack_id" && "$stack_id" != "null" ]]; then
                    local stack_name
                    stack_name=$(echo "$stacks_response" | jq -r ".[] | select(.Id == $stack_id) | .Name" 2>/dev/null)
                    info "Stopping stack: $stack_name (ID: $stack_id)"
                    
                    # Note: Portainer doesn't have a direct stop endpoint for stacks
                    # Stacks will be stopped via docker compose down in the container stop phase
                    info "Stack $stack_name will be stopped via docker compose down"
                fi
            done
            
            # Give stacks time to stop gracefully
            sleep 5
        else
            warn "Could not authenticate with Portainer API for graceful stack shutdown"
        fi
    else
        warn "Portainer credentials not found, skipping graceful stack shutdown"
    fi
}

# Stop containers gracefully for backup (keeping Portainer running for API access)
# Stop containers using Portainer Docker API (same endpoints as Portainer UI)
stop_containers() {
    info "Stopping containers gracefully via Portainer API..."
    info "Keeping Portainer running to manage backup process"
    
    # Authenticate with Portainer API (using localhost since NPM may be down)
    source "$PORTAINER_PATH/.credentials"
    local auth_response
    auth_response=$(curl -s -X POST "http://localhost:9000/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"Username\": \"$PORTAINER_ADMIN_USERNAME\", \"Password\": \"$PORTAINER_ADMIN_PASSWORD\"}")
    
    local jwt_token
    jwt_token=$(echo "$auth_response" | jq -r '.jwt // empty')
    
    if [[ -z "$jwt_token" ]]; then
        error "Failed to authenticate with Portainer API for container stopping"
        return 1
    fi
    
    # Get all containers using the same API endpoint as Portainer UI
    local all_containers
    all_containers=$(get_all_containers_via_api "$jwt_token")
    
    if [[ -z "$all_containers" ]]; then
        warn "Could not retrieve containers via Portainer API, skipping graceful stop"
        return 1
    fi
    
    # Stop all containers except Portainer using the same API as Portainer UI
    local containers_stopped=0
    
    # Get running containers excluding Portainer, output as separate lines
    local running_container_ids
    running_container_ids=$(echo "$all_containers" | jq -r '.[] | select(.State == "running" and .Names[0] != "/portainer") | .Id')
    
    if [[ -n "$running_container_ids" ]]; then
        while IFS= read -r container_id; do
            if [[ -n "$container_id" && "$container_id" != "null" ]]; then
                # Get container name for logging
                local container_name
                container_name=$(echo "$all_containers" | jq -r --arg id "$container_id" '.[] | select(.Id == $id) | .Names[0]' | sed 's|^/||')
                
                if stop_container_via_api "$jwt_token" "$container_id"; then
                    info "Stopped container: $container_name (ID: $container_id)"
                    containers_stopped=$((containers_stopped + 1))
                else
                    warn "Failed to stop container: $container_name (ID: $container_id)"
                fi
            fi
        done <<< "$running_container_ids"
    else
        info "No running containers found to stop (excluding Portainer)"
    fi
    
    # Wait for containers to stop gracefully
    sleep 5
    
    success "Containers stopped gracefully via Portainer API (Portainer kept running)"
}

# Start containers after backup
start_containers() {
    info "Starting containers after backup..."
    
    # Check if Portainer is running, start it if not
    if ! sudo -u "$PORTAINER_USER" docker ps --format "{{.Names}}" | grep -q "^portainer$"; then
        warn "Portainer was stopped during backup, restarting..."
        cd "$PORTAINER_PATH"
        sudo -u "$PORTAINER_USER" docker compose up -d
        sleep 15  # Give Portainer more time to start
        info "Portainer restarted"
    else
        info "Portainer remained running during backup"
    fi
    
    # Start nginx-proxy-manager (reverse proxy) first as it's critical for accessing everything
    info "Starting nginx-proxy-manager (reverse proxy)..."
    cd "$TOOLS_PATH/nginx-proxy-manager"
    sudo -u "$PORTAINER_USER" docker compose up -d
    
    # Wait a bit for NPM to be ready
    sleep 10
    
    success "Core containers started"
    
    # Restart any standalone containers that were running before backup
    local running_containers_file="$TEMP_DIR/running_containers.txt"
    if [[ -f "$running_containers_file" ]]; then
        info "Restoring standalone containers that were running before backup..."
        
        while read -r container_name; do
            if [[ -n "$container_name" ]]; then
                # Skip containers that are already managed by Portainer stacks
                if [[ "$container_name" != "nginx-proxy-manager" ]]; then
                    # Check if container exists and is not running
                    if sudo -u "$PORTAINER_USER" docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
                        if ! sudo -u "$PORTAINER_USER" docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
                            info "Restarting standalone container: $container_name"
                            sudo -u "$PORTAINER_USER" docker start "$container_name" || warn "Failed to restart container: $container_name"
                        else
                            info "Container already running: $container_name"
                        fi
                    else
                        warn "Container no longer exists: $container_name"
                    fi
                fi
            fi
        done < "$running_containers_file"
        
        success "Standalone container restoration completed"
    fi
}

# Restart Portainer stacks based on saved state with enhanced restoration
restart_stacks() {
    local state_file="$1"
    
    if [[ ! -f "$state_file" ]]; then
        warn "Stack state file not found: $state_file"
        return 0
    fi
    
    source "$PORTAINER_PATH/.credentials"
    
    # Check if this is enhanced format or legacy format
    local capture_version
    capture_version=$(jq -r '.capture_version // "legacy"' "$state_file")
    
    # Login to Portainer API
    local auth_response
    auth_response=$(curl -s -X POST "$PORTAINER_API_URL/auth" \
        -H "Content-Type: application/json" \
        -d "{\"Username\": \"$PORTAINER_ADMIN_USERNAME\", \"Password\": \"$PORTAINER_ADMIN_PASSWORD\"}")
    
    local jwt_token
    jwt_token=$(echo "$auth_response" | jq -r '.jwt // empty')
    
    if [[ -z "$jwt_token" ]]; then
        warn "Failed to authenticate with Portainer API for stack restart"
        return 0
    fi
    
    # Handle different state formats
    if [[ "$capture_version" == "enhanced-v2" ]]; then
        info "Processing enhanced stack state format v2"
        restore_enhanced_stacks "$state_file" "$jwt_token"
    else
        info "Processing legacy stack state format"
        restore_legacy_stacks "$state_file" "$jwt_token"
    fi
}

# Restore stacks using enhanced format with complete configuration
restore_enhanced_stacks() {
    local state_file="$1"
    local jwt_token="$2"
    
    # Read stack states and restart running stacks
    local stack_count
    stack_count=$(jq -r '.stacks | length' "$state_file")
    
    if [[ "$stack_count" -gt 0 ]]; then
        info "Restoring $stack_count stacks with enhanced configuration..."
        
        # Get current stacks
        local current_stacks
        current_stacks=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/stacks")
        
        # Process each stack for enhanced restoration
        jq -c '.stacks[]' "$state_file" | while read -r stack_json; do
            local stack_name stack_status stack_id compose_content env_vars
            stack_name=$(echo "$stack_json" | jq -r '.name')
            stack_status=$(echo "$stack_json" | jq -r '.status')
            compose_content=$(echo "$stack_json" | jq -r '.compose_file_content // empty')
            env_vars=$(echo "$stack_json" | jq -r '.env_variables // []')
            
            # Restore all stacks but handle running vs stopped state appropriately
            if [[ "$stack_status" == "1" ]]; then
                info "Restoring running stack: $stack_name"
            else
                info "Restoring stopped stack: $stack_name (will remain stopped)"
            fi
            
            # Find existing stack ID
            stack_id=$(echo "$current_stacks" | jq -r ".[] | select(.Name == \"$stack_name\") | .Id")
                
                if [[ -n "$stack_id" && "$stack_id" != "null" ]]; then
                    # Stack exists - update and restart it
                    info "Updating existing stack: $stack_name (ID: $stack_id)"
                    
                    # Update stack with enhanced configuration if we have compose content
                    if [[ -n "$compose_content" && "$compose_content" != "null" && "$compose_content" != "" ]]; then
                        # Prepare stack update payload
                        local update_payload
                        update_payload=$(jq -n \
                            --arg compose "$compose_content" \
                            --argjson env "$env_vars" \
                            '{
                                stackFileContent: $compose,
                                env: $env,
                                prune: false
                            }')
                        
                        # Update the stack
                        local update_response
                        update_response=$(curl -s -X PUT "$PORTAINER_API_URL/stacks/$stack_id" \
                            -H "Authorization: Bearer $jwt_token" \
                            -H "Content-Type: application/json" \
                            -d "$update_payload")
                        
                        if echo "$update_response" | jq -e . >/dev/null 2>&1; then
                            info "Successfully updated stack configuration: $stack_name"
                        else
                            warn "Failed to update stack configuration: $stack_name"
                        fi
                    fi
                    
                    # Start the stack only if it was running during backup
                    if [[ "$stack_status" == "1" ]]; then
                        # Use stack update/redeploy approach which is more reliable than start/stop
                        if [[ -n "$compose_content" && "$compose_content" != "null" && "$compose_content" != "" ]]; then
                            info "Redeploying stack via update API: $stack_name"
                            
                            # Create update payload with compose content for reliable deployment
                            local redeploy_payload
                            redeploy_payload=$(jq -n \
                                --arg compose "$compose_content" \
                                --argjson env "$env_vars" \
                                '{
                                    stackFileContent: $compose,
                                    env: $env,
                                    prune: false
                                }')
                            
                            # Update the stack (this effectively redeploys it)
                            local redeploy_response
                            redeploy_response=$(curl -s -X PUT "$PORTAINER_API_URL/stacks/$stack_id" \
                                -H "Authorization: Bearer $jwt_token" \
                                -H "Content-Type: application/json" \
                                -d "$redeploy_payload")
                            
                            if echo "$redeploy_response" | grep -q "error\|Error" 2>/dev/null; then
                                warn "Stack redeploy failed: $stack_name - trying start API"
                                # Fallback to start API if redeploy fails
                                local start_response
                                start_response=$(curl -s -X POST "$PORTAINER_API_URL/stacks/$stack_id/start" \
                                    -H "Authorization: Bearer $jwt_token")
                            else
                                info "Stack redeploy successful: $stack_name"
                            fi
                        else
                            # No compose content available, try basic start
                            local start_response
                            start_response=$(curl -s -X POST "$PORTAINER_API_URL/stacks/$stack_id/start" \
                                -H "Authorization: Bearer $jwt_token")
                        fi
                        
                        # Wait for stack to start up
                        sleep 15  # Extended wait time for stack startup with API-only approach
                        
                        # Verify the stack is actually running using Portainer Docker API (same as Portainer UI)
                        local containers_running=false
                        local retries=0
                        local max_retries=10  # Increased retries for API-only approach with longer waits
                        
                        while [[ $retries -lt $max_retries ]]; do
                            info "Attempt $((retries + 1))/$max_retries: Verifying stack $stack_name via Portainer Docker API"
                            
                            # Use the same Portainer Docker API that the UI uses
                            if verify_stack_running_via_api "$jwt_token" "$stack_name"; then
                                containers_running=true
                                success "Stack $stack_name verified running via Portainer Docker API"
                                break
                            else
                                info "Stack $stack_name not yet running, waiting..."
                            fi
                            
                            # API-only approach as requested - no fallbacks to direct docker commands
                            # Allow more time for containers with health checks to start properly
                            if [[ $retries -ge 2 ]]; then
                                info "Waiting longer for containers with health checks to start properly..."
                                sleep 15  # Extended wait for slow-starting containers
                            fi
                            
                            retries=$((retries + 1))
                            sleep 8  # Increased wait between retries for API-only approach
                        done
                        
                        if [[ "$containers_running" == "true" ]]; then
                            success "Restored running stack: $stack_name with enhanced configuration"
                        else
                            warn "Failed to start stack: $stack_name - containers not running after extensive retry attempts"
                            warn "Stack configuration has been updated but containers are not running"
                            warn "You may need to manually start this stack via Portainer UI"
                        fi
                    else
                        # Stack was stopped during backup, leave it stopped
                        success "Restored stopped stack: $stack_name (kept in stopped state)"
                    fi
                else
                    info "Stack not found in current Portainer installation: $stack_name (skipping - deleted stacks are not recreated during restore)"
                    
                    # Clean up any orphaned stack directory that may have been restored
                    if [[ -d "$TOOLS_PATH/$stack_name" ]]; then
                        warn "Removing orphaned stack directory: $TOOLS_PATH/$stack_name"
                        sudo rm -rf "$TOOLS_PATH/$stack_name"
                    fi
                fi
        done
        
        # Clean up any orphaned stack directories after restore
        cleanup_orphaned_stacks "$jwt_token"
        
        success "Enhanced stack restoration completed"
    fi
}

# Restore stacks using legacy format (backwards compatibility)
restore_legacy_stacks() {
    local state_file="$1"
    local jwt_token="$2"
    
    # Read stack states and restart running stacks
    local stack_count
    stack_count=$(jq -r '.stacks | length' "$state_file")
    
    if [[ "$stack_count" -gt 0 ]]; then
        info "Restarting $stack_count stacks (legacy format)..."
        
        # Get current stacks
        local current_stacks
        current_stacks=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/stacks")
        
        # Restart stacks that were running
        jq -r '.stacks[] | select(.status == 1) | .name' "$state_file" | while read -r stack_name; do
            local stack_id
            stack_id=$(echo "$current_stacks" | jq -r ".[] | select(.Name == \"$stack_name\") | .Id")
            
            if [[ -n "$stack_id" && "$stack_id" != "null" ]]; then
                local start_response
                start_response=$(curl -s -X POST "$PORTAINER_API_URL/stacks/$stack_id/start" \
                    -H "Authorization: Bearer $jwt_token")
                
                if echo "$start_response" | grep -q "error\|Error" 2>/dev/null; then
                    warn "Failed to start stack: $stack_name - API Error: $start_response"
                else
                    # Wait for stack to start up
                    sleep 3
                    info "Restarted stack: $stack_name"
                fi
            fi
        done
        
        # Clean up any orphaned stack directories after legacy restore
        cleanup_orphaned_stacks "$jwt_token"
    fi
}

# Generate metadata file for backup reliability
generate_backup_metadata() {
    local backup_dir="$1"
    local metadata_file="$backup_dir/backup_metadata.json"
    
    info "Generating backup metadata for enhanced reliability..."
    
    # Ensure backup directory is writable by the portainer user
    if [[ ! -w "$backup_dir" ]]; then
        sudo chown "$PORTAINER_USER:$PORTAINER_USER" "$backup_dir"
        sudo chmod 755 "$backup_dir"
    fi
    
    # Load configuration if not already loaded
    if [[ -z "${PORTAINER_PATH:-}" ]]; then
        if [[ -f "$CONFIG_FILE" ]]; then
            source "$CONFIG_FILE"
        else
            # Use defaults for test environment
            PORTAINER_PATH="${DEFAULT_PORTAINER_PATH}"
            TOOLS_PATH="${DEFAULT_TOOLS_PATH}"
            BACKUP_PATH="${DEFAULT_BACKUP_PATH}"
        fi
    fi
    
    # System information
    local system_info=$(cat << EOF
{
    "backup_version": "1.0",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "script_version": "$VERSION",
    "system": {
        "hostname": "$(hostname)",
        "kernel": "$(uname -r)",
        "architecture": "$(uname -m)",
        "os": "$(lsb_release -d 2>/dev/null | cut -d: -f2 | sed 's/^[[:space:]]*//' || echo 'Unknown')",
        "docker_version": "$(docker --version 2>/dev/null || echo 'Unknown')"
    },
    "paths": {
        "portainer": "$PORTAINER_PATH",
        "tools": "$TOOLS_PATH",
        "backup": "$BACKUP_PATH"
    },
    "permissions": [],
    "ownership": []
}
EOF
)
    
    # Write base metadata (ensure directory is writable)
    if ! echo "$system_info" > "$metadata_file" 2>/dev/null; then
        # If direct write fails, try with sudo
        echo "$system_info" | sudo tee "$metadata_file" > /dev/null
        sudo chown "$PORTAINER_USER:$PORTAINER_USER" "$metadata_file"
    fi
    
    # Generate detailed permissions and ownership data
    local temp_permissions="/tmp/backup_permissions_$$"
    local temp_ownership="/tmp/backup_ownership_$$"
    
    # Collect permissions and ownership for all files (only if paths exist)
    local paths_to_scan=""
    [[ -d "$PORTAINER_PATH" ]] && paths_to_scan="$paths_to_scan $PORTAINER_PATH"
    [[ -d "$TOOLS_PATH" ]] && paths_to_scan="$paths_to_scan $TOOLS_PATH"
    
    if [[ -n "$paths_to_scan" ]]; then
        # Use a simpler approach to avoid subshell issues
        while IFS= read -r -d '' file; do
            local perms=$(stat -c "%a" "$file" 2>/dev/null)
            local owner=$(stat -c "%U" "$file" 2>/dev/null)
            local group=$(stat -c "%G" "$file" 2>/dev/null)
            local relative_path=$(echo "$file" | sed 's|^/||')
            
            echo "{\"path\": \"$relative_path\", \"permissions\": \"$perms\", \"owner\": \"$owner\", \"group\": \"$group\"}" >> "$temp_permissions"
        done < <(find $paths_to_scan -type f -o -type d -print0 2>/dev/null)
    fi
    
    # Convert to JSON arrays
    if [[ -f "$temp_permissions" ]]; then
        # Create proper JSON array for permissions
        {
            echo "["
            sed '$!s/$/,/' "$temp_permissions"
            echo "]"
        } > "${temp_permissions}.json"
        
        # Update metadata file with permissions data
        if jq --slurpfile perms "${temp_permissions}.json" '.permissions = $perms[0]' "$metadata_file" > "${metadata_file}.tmp" 2>/dev/null; then
            mv "${metadata_file}.tmp" "$metadata_file"
        else
            # If jq fails, try with sudo
            sudo jq --slurpfile perms "${temp_permissions}.json" '.permissions = $perms[0]' "$metadata_file" > "${metadata_file}.tmp"
            sudo mv "${metadata_file}.tmp" "$metadata_file"
            sudo chown "$PORTAINER_USER:$PORTAINER_USER" "$metadata_file"
        fi
        
        # Cleanup
        rm -f "$temp_permissions" "${temp_permissions}.json"
    fi
    
    # Validate metadata file
    if jq . "$metadata_file" >/dev/null 2>&1; then
        success "Backup metadata generated successfully"
    else
        warn "Backup metadata may be malformed, continuing with backup"
    fi
}

# Clean up orphaned stack directories that don't exist in Portainer
cleanup_orphaned_stacks() {
    local jwt_token="$1"
    
    if [[ -z "$jwt_token" ]]; then
        warn "No JWT token provided, skipping orphaned stack cleanup"
        return 0
    fi
    
    info "Cleaning up orphaned stack directories..."
    
    # Get current active stacks from Portainer
    local current_stacks
    current_stacks=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/stacks")
    
    if [[ -z "$current_stacks" ]] || ! echo "$current_stacks" | jq -e . >/dev/null 2>&1; then
        warn "Could not retrieve current stacks from Portainer API, skipping cleanup"
        return 0
    fi
    
    # Get list of active stack names
    local active_stack_names
    active_stack_names=$(echo "$current_stacks" | jq -r '.[].Name' 2>/dev/null || echo "")
    
    # Check each directory in TOOLS_PATH
    if [[ -d "$TOOLS_PATH" ]]; then
        for stack_dir in "$TOOLS_PATH"/*/; do
            if [[ -d "$stack_dir" ]]; then
                local dir_name
                dir_name=$(basename "$stack_dir")
                
                # Check if this directory corresponds to an active stack
                local is_active=false
                if [[ -n "$active_stack_names" ]]; then
                    while read -r active_name; do
                        if [[ "$dir_name" == "$active_name" ]]; then
                            is_active=true
                            break
                        fi
                    done <<< "$active_stack_names"
                fi
                
                if [[ "$is_active" == "false" ]]; then
                    warn "Found orphaned stack directory: $stack_dir"
                    info "Removing orphaned directory: $stack_dir"
                    sudo rm -rf "$stack_dir"
                else
                    info "Keeping active stack directory: $stack_dir"
                fi
            fi
        done
    fi
    
    success "Orphaned stack cleanup completed"
}

# Implement snapshot restore philosophy - remove stacks not present in backup
implement_snapshot_restore() {
    local stack_state_file="$1"
    
    if [[ ! -f "$stack_state_file" ]]; then
        warn "Stack state file not found for snapshot restore: $stack_state_file"
        return 0
    fi
    
    info "Implementing snapshot restore philosophy - ensuring exact state match..."
    
    # Load Portainer credentials
    source "$PORTAINER_PATH/.credentials"
    
    # Login to Portainer API
    local auth_response
    auth_response=$(curl -s -X POST "$PORTAINER_API_URL/auth" \
        -H "Content-Type: application/json" \
        -d "{\"Username\": \"$PORTAINER_ADMIN_USERNAME\", \"Password\": \"$PORTAINER_ADMIN_PASSWORD\"}")
    
    local jwt_token
    jwt_token=$(echo "$auth_response" | jq -r '.jwt // empty')
    
    if [[ -z "$jwt_token" ]]; then
        warn "Failed to authenticate with Portainer API for snapshot restore"
        return 0
    fi
    
    # Get stacks that were in the backup
    local backup_stack_names
    backup_stack_names=$(jq -r '.stacks[].name' "$stack_state_file" 2>/dev/null)
    
    if [[ -z "$backup_stack_names" ]]; then
        info "No stacks found in backup - this will result in removing all current stacks"
    else
        info "Backup contains the following stacks: $(echo "$backup_stack_names" | tr '\n' ' ')"
    fi
    
    # Get current stacks from Portainer
    local current_stacks
    current_stacks=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/stacks")
    
    if [[ -z "$current_stacks" ]] || ! echo "$current_stacks" | jq -e . >/dev/null 2>&1; then
        warn "Could not retrieve current stacks from Portainer API, skipping snapshot restore"
        return 0
    fi
    
    # Get current stack names
    local current_stack_names
    current_stack_names=$(echo "$current_stacks" | jq -r '.[].Name' 2>/dev/null)
    
    if [[ -z "$current_stack_names" ]]; then
        info "No current stacks found - nothing to remove for snapshot restore"
        return 0
    fi
    
    info "Current stacks in Portainer: $(echo "$current_stack_names" | tr '\n' ' ')"
    
    # Find stacks that exist in current system but not in backup
    local stacks_to_remove=""
    while read -r current_stack; do
        if [[ -n "$current_stack" ]]; then
            local found_in_backup=false
            if [[ -n "$backup_stack_names" ]]; then
                while read -r backup_stack; do
                    if [[ "$current_stack" == "$backup_stack" ]]; then
                        found_in_backup=true
                        break
                    fi
                done <<< "$backup_stack_names"
            fi
            
            if [[ "$found_in_backup" == "false" ]]; then
                stacks_to_remove="$stacks_to_remove$current_stack\n"
            fi
        fi
    done <<< "$current_stack_names"
    
    # Remove stacks that weren't in the backup
    if [[ -n "$stacks_to_remove" ]]; then
        stacks_to_remove=$(echo -e "$stacks_to_remove" | sed '/^$/d')  # Remove empty lines
        info "Removing stacks that were not present in backup for true snapshot restore:"
        echo "$stacks_to_remove" | while read -r stack_to_remove; do
            if [[ -n "$stack_to_remove" ]]; then
                local stack_id
                stack_id=$(echo "$current_stacks" | jq -r ".[] | select(.Name == \"$stack_to_remove\") | .Id")
                
                if [[ -n "$stack_id" && "$stack_id" != "null" ]]; then
                    info "Removing stack not in backup: $stack_to_remove (ID: $stack_id)"
                    
                    # Delete the stack via API
                    local delete_response
                    delete_response=$(curl -s -X DELETE "$PORTAINER_API_URL/stacks/$stack_id" \
                        -H "Authorization: Bearer $jwt_token")
                    
                    if echo "$delete_response" | grep -q "error\|Error" 2>/dev/null; then
                        warn "Failed to delete stack: $stack_to_remove - API Error: $delete_response"
                    else
                        info "Successfully removed stack: $stack_to_remove"
                        
                        # Also remove any associated data directory
                        local stack_data_dir="$TOOLS_PATH/$stack_to_remove"
                        if [[ -d "$stack_data_dir" ]]; then
                            info "Removing data directory for deleted stack: $stack_data_dir"
                            sudo rm -rf "$stack_data_dir"
                        fi
                    fi
                else
                    warn "Could not find stack ID for: $stack_to_remove"
                fi
            fi
        done
        
        success "Snapshot restore completed - system now matches backup state exactly"
    else
        info "No extra stacks found - current state already matches backup"
    fi
}

# Implement true snapshot restore: clean system and restore only backup contents
implement_true_snapshot_restore() {
    local selected_backup="$1"
    
    info "Implementing true snapshot restore - cleaning system and restoring only backup contents..."
    
    # Step 1: Stop and remove ALL containers (except Portainer which we need for API calls)
    info "Stopping and removing all containers (except Portainer)..."
    stop_and_remove_all_containers
    
    # Step 2: Start only Portainer to have API access
    info "Starting Portainer for API management..."
    start_portainer_only
    
    # Step 3: Wait for Portainer to be ready
    info "Waiting for Portainer to be ready..."
    wait_for_portainer_ready
    
    # Step 4: Extract and process stack states from backup
    local stack_state_file="/tmp/stack_states.json"
    if tar -tf "$selected_backup" | grep -q "stack_states.json"; then
        sudo tar -xzf "$selected_backup" -C /tmp stack_states.json 2>/dev/null || true
        if [[ -f "$stack_state_file" ]]; then
            info "Restoring stacks from backup using Portainer API..."
            restore_stacks_from_backup "$stack_state_file"
            sudo rm -f "$stack_state_file"
        else
            warn "No stack state file found in backup - using fallback detection"
            restore_critical_stacks_fallback
        fi
    else
        warn "Backup does not contain stack states - using fallback detection"
        restore_critical_stacks_fallback
    fi
    
    # Step 5: Final Portainer restart to ensure clean state
    info "Performing final Portainer restart for clean state..."
    restart_portainer_after_restore
}

# Stop and remove all containers except Portainer
stop_and_remove_all_containers() {
    info "Getting list of all running containers..."
    local all_containers
    all_containers=$(sudo -u "$PORTAINER_USER" docker ps --format "{{.Names}}" | grep -v "^portainer$" || true)
    
    if [[ -n "$all_containers" ]]; then
        info "Stopping containers: $(echo "$all_containers" | tr '\n' ' ')"
        echo "$all_containers" | while read -r container_name; do
            if [[ -n "$container_name" ]]; then
                info "Stopping container: $container_name"
                sudo -u "$PORTAINER_USER" docker stop "$container_name" || warn "Failed to stop $container_name"
            fi
        done
        
        info "Removing stopped containers..."
        echo "$all_containers" | while read -r container_name; do
            if [[ -n "$container_name" ]]; then
                info "Removing container: $container_name"
                sudo -u "$PORTAINER_USER" docker rm "$container_name" || warn "Failed to remove $container_name"
            fi
        done
    else
        info "No containers found to stop/remove (other than Portainer)"
    fi
    
    # Also remove any orphaned containers
    info "Cleaning up any orphaned containers..."
    sudo -u "$PORTAINER_USER" docker container prune -f || true
}

# Start only Portainer container
start_portainer_only() {
    info "Starting Portainer container..."
    cd "$PORTAINER_PATH" || {
        error "Could not navigate to Portainer directory: $PORTAINER_PATH"
        return 1
    }
    
    # Start Portainer using docker compose
    if ! sudo -u "$PORTAINER_USER" docker compose up -d; then
        error "Failed to start Portainer"
        return 1
    fi
    
    success "Portainer started successfully"
}

# Get all containers using Portainer Docker API (same endpoint as Portainer UI)
get_all_containers_via_api() {
    local jwt_token="$1"
    local endpoint_id="${2:-1}"
    
    # Use localhost since NPM may be down during backup/restore operations
    local containers_response
    containers_response=$(curl -s -H "Authorization: Bearer $jwt_token" \
        "http://localhost:9000/api/endpoints/$endpoint_id/docker/v1.41/containers/json?all=true")
    
    if [[ -n "$containers_response" ]] && echo "$containers_response" | jq -e . >/dev/null 2>&1; then
        echo "$containers_response"
        return 0
    else
        warn "Failed to get containers via Portainer Docker API"
        if [[ -n "$containers_response" ]]; then
            warn "API Response: $containers_response"
        else
            warn "Empty response from API"
        fi
        return 1
    fi
}

# Start container using Portainer Docker API (same endpoint as Portainer UI)
start_container_via_api() {
    local jwt_token="$1"
    local container_id="$2"
    local endpoint_id="${3:-1}"
    
    info "Starting container via Portainer API: $container_id"
    
    # Use localhost since NPM may be down during backup/restore operations
    local start_response
    start_response=$(curl -s -X POST -H "Authorization: Bearer $jwt_token" \
        "http://localhost:9000/api/endpoints/$endpoint_id/docker/v1.41/containers/$container_id/start")
    
    # Docker API returns 204 No Content on success, so empty response is success
    if [[ -z "$start_response" ]] || [[ "$start_response" == "{}" ]]; then
        info "Successfully started container: $container_id"
        return 0
    else
        warn "Failed to start container $container_id via API: $start_response"
        return 1
    fi
}

# Stop container using Portainer Docker API (same endpoint as Portainer UI)
stop_container_via_api() {
    local jwt_token="$1"
    local container_id="$2"
    local endpoint_id="${3:-1}"
    
    info "Stopping container via Portainer API: $container_id"
    
    # Use localhost since NPM may be down during backup/restore operations
    local stop_response
    stop_response=$(curl -s -X POST -H "Authorization: Bearer $jwt_token" \
        "http://localhost:9000/api/endpoints/$endpoint_id/docker/v1.41/containers/$container_id/stop")
    
    # Docker API returns 204 No Content on success, so empty response is success
    if [[ -z "$stop_response" ]] || [[ "$stop_response" == "{}" ]]; then
        info "Successfully stopped container: $container_id"
        return 0
    else
        warn "Failed to stop container $container_id via API: $stop_response"
        return 1
    fi
}

# Get containers for a specific stack using Portainer Docker API
get_stack_containers_via_api() {
    local jwt_token="$1"
    local stack_name="$2"
    local endpoint_id="${3:-1}"
    
    local all_containers
    all_containers=$(get_all_containers_via_api "$jwt_token" "$endpoint_id")
    
    if [[ -z "$all_containers" ]]; then
        return 1
    fi
    
    # Filter containers by compose project label (same as Portainer does)
    local stack_containers
    stack_containers=$(echo "$all_containers" | jq -r ".[] | select(.Labels[\"com.docker.compose.project\"] == \"$stack_name\") | {Id: .Id, Names: .Names[0], State: .State, Labels: .Labels}")
    
    if [[ -n "$stack_containers" ]]; then
        echo "$stack_containers"
        return 0
    else
        return 1
    fi
}

# Verify containers are running using Portainer Docker API
verify_stack_running_via_api() {
    local jwt_token="$1"
    local stack_name="$2"
    local endpoint_id="${3:-1}"
    
    local stack_containers
    stack_containers=$(get_stack_containers_via_api "$jwt_token" "$stack_name" "$endpoint_id")
    
    if [[ -z "$stack_containers" ]]; then
        return 1
    fi
    
    # Check if any containers are running
    local running_containers
    running_containers=$(echo "$stack_containers" | jq -r 'select(.State == "running") | .Names')
    
    if [[ -n "$running_containers" ]]; then
        info "Stack $stack_name containers running: $running_containers"
        return 0
    else
        return 1
    fi
}

# Wait for Portainer to be ready and accessible
wait_for_portainer_ready() {
    local max_wait=120  # Increased timeout for containers with health checks
    local wait_count=0
    
    while [[ $wait_count -lt $max_wait ]]; do
        if curl -s "http://localhost:9000" >/dev/null 2>&1; then
            success "Portainer is ready and accessible"
            sleep 5  # Give it a bit more time for full initialization
            return 0
        fi
        
        sleep 2
        wait_count=$((wait_count + 2))
        
        if [[ $((wait_count % 10)) -eq 0 ]]; then
            info "Still waiting for Portainer... ($wait_count/${max_wait}s)"
        fi
    done
    
    error "Portainer failed to become ready within ${max_wait} seconds"
    return 1
}

# Restore stacks from backup using Portainer API (only what's in backup)
# Setup permissions after restore
setup_permissions_after_restore() {
    info "Setting up proper permissions after restore..."
    
    # Ensure portainer user owns the directories
    sudo chown -R "$PORTAINER_USER:$PORTAINER_USER" "$PORTAINER_PATH" || true
    sudo chown -R "$PORTAINER_USER:$PORTAINER_USER" "$TOOLS_PATH" || true
    
    # Set proper directory permissions
    sudo chmod 755 "$PORTAINER_PATH" || true
    sudo chmod 755 "$TOOLS_PATH" || true
    
    success "Permissions set up after restore"
}

# Restore stacks with proper startup sequence
restore_stacks_with_startup_sequence() {
    local stack_state_file="$1"
    
    if [[ ! -f "$stack_state_file" ]]; then
        warn "Stack state file not found: $stack_state_file"
        return 0
    fi
    
    source "$PORTAINER_PATH/.credentials"
    
    # Login to Portainer API
    local auth_response
    auth_response=$(curl -s -X POST "$PORTAINER_API_URL/auth" \
        -H "Content-Type: application/json" \
        -d "{\"Username\": \"$PORTAINER_ADMIN_USERNAME\", \"Password\": \"$PORTAINER_ADMIN_PASSWORD\"}")
    
    local jwt_token
    jwt_token=$(echo "$auth_response" | jq -r '.jwt // empty')
    
    if [[ -z "$jwt_token" ]]; then
        error "Failed to authenticate with Portainer API"
        return 1
    fi
    
    # Get stacks from backup
    local backup_stack_names
    backup_stack_names=$(jq -r '.stacks[].name' "$stack_state_file" 2>/dev/null)
    
    if [[ -z "$backup_stack_names" ]]; then
        info "No stacks found in backup to restore"
        return 0
    fi
    
    info "Restoring stacks with proper startup sequence: $(echo "$backup_stack_names" | tr '\n' ' ')"
    
    # Start nginx-proxy-manager first (reverse proxy)
    if echo "$backup_stack_names" | grep -q "nginx-proxy-manager"; then
        info "Starting nginx-proxy-manager first (reverse proxy)..."
        restart_specific_stack "nginx-proxy-manager" "$stack_state_file" "$jwt_token"
        
        # Wait for NPM to be ready
        sleep 15
        info "nginx-proxy-manager startup completed"
    fi
    
    # Start remaining stacks
    echo "$backup_stack_names" | while read -r stack_name; do
        if [[ -n "$stack_name" && "$stack_name" != "nginx-proxy-manager" ]]; then
            info "Starting stack: $stack_name"
            restart_specific_stack "$stack_name" "$stack_state_file" "$jwt_token"
            sleep 5  # Brief pause between stack starts
        fi
    done
    
    success "Stack restoration with startup sequence completed"
}

# Restart a specific stack
restart_specific_stack() {
    local stack_name="$1"
    local stack_state_file="$2"
    local jwt_token="$3"
    
    # Get stack information from the state file
    local stack_json
    stack_json=$(jq -c ".stacks[] | select(.name == \"$stack_name\")" "$stack_state_file" 2>/dev/null)
    
    if [[ -z "$stack_json" || "$stack_json" == "null" ]]; then
        warn "Stack $stack_name not found in backup state file"
        return 1
    fi
    
    local stack_status compose_content env_vars
    stack_status=$(echo "$stack_json" | jq -r '.status')
    compose_content=$(echo "$stack_json" | jq -r '.compose_file_content // empty')
    env_vars=$(echo "$stack_json" | jq -r '.env_variables // []')
    
    # Only start stacks that were running
    if [[ "$stack_status" == "1" ]]; then
        info "Starting stack: $stack_name (was running in backup)"
        
        # Get current stacks to see if it exists
        local current_stacks
        current_stacks=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/stacks")
        
        local stack_id
        stack_id=$(echo "$current_stacks" | jq -r ".[] | select(.Name == \"$stack_name\") | .Id")
        
        if [[ -n "$stack_id" && "$stack_id" != "null" ]]; then
            # Stack exists, start it
            curl -s -X POST -H "Authorization: Bearer $jwt_token" \
                "$PORTAINER_API_URL/stacks/$stack_id/start" >/dev/null 2>&1
        else
            # Stack doesn't exist, create it if we have compose content
            if [[ -n "$compose_content" && "$compose_content" != "null" ]]; then
                info "Creating stack $stack_name from backup compose content"
                create_stack_from_compose_content "$stack_name" "$compose_content" "$env_vars" "$jwt_token"
            else
                warn "No compose content found for stack $stack_name, skipping creation"
            fi
        fi
    else
        info "Stack $stack_name was stopped in backup, not starting"
    fi
}

# Create stack from compose content
create_stack_from_compose_content() {
    local stack_name="$1"
    local compose_content="$2"
    local env_vars="$3"
    local jwt_token="$4"
    
    # Prepare the payload
    local payload
    payload=$(jq -n \
        --arg name "$stack_name" \
        --arg content "$compose_content" \
        --argjson env "$env_vars" \
        '{
            "Name": $name,
            "StackFileContent": $content,
            "Env": $env
        }')
    
    # Create the stack
    curl -s -X POST "$PORTAINER_API_URL/stacks?type=2&method=string&endpointId=1" \
        -H "Authorization: Bearer $jwt_token" \
        -H "Content-Type: application/json" \
        -d "$payload" >/dev/null 2>&1
}

# Verify external accessibility
verify_external_accessibility() {
    info "Verifying external accessibility of services..."
    
    local portainer_accessible=false
    local npm_accessible=false
    
    # Check if we have domain configuration
    if [[ -n "$DOMAIN_NAME" ]]; then
        # Try to access Portainer via domain
        if curl -s -k "https://$PORTAINER_SUBDOMAIN.$DOMAIN_NAME" >/dev/null 2>&1; then
            success "✅ Portainer is accessible via https://$PORTAINER_SUBDOMAIN.$DOMAIN_NAME"
            portainer_accessible=true
        elif curl -s "http://$PORTAINER_SUBDOMAIN.$DOMAIN_NAME" >/dev/null 2>&1; then
            success "✅ Portainer is accessible via http://$PORTAINER_SUBDOMAIN.$DOMAIN_NAME"
            portainer_accessible=true
        else
            warn "❌ Portainer not accessible via domain"
        fi
        
        # Try to access NPM via domain
        if curl -s -k "https://$NPM_SUBDOMAIN.$DOMAIN_NAME" >/dev/null 2>&1; then
            success "✅ nginx-proxy-manager is accessible via https://$NPM_SUBDOMAIN.$DOMAIN_NAME"
            npm_accessible=true
        elif curl -s "http://$NPM_SUBDOMAIN.$DOMAIN_NAME" >/dev/null 2>&1; then
            success "✅ nginx-proxy-manager is accessible via http://$NPM_SUBDOMAIN.$DOMAIN_NAME"
            npm_accessible=true
        else
            warn "❌ nginx-proxy-manager not accessible via domain"
        fi
    else
        info "No domain configuration found, checking localhost access"
    fi
    
    # Fallback to localhost checks
    if [[ "$portainer_accessible" == "false" ]]; then
        if curl -s "http://localhost:9000" >/dev/null 2>&1; then
            info "✅ Portainer is accessible via localhost:9000"
        else
            warn "❌ Portainer not accessible via localhost"
        fi
    fi
    
    if [[ "$npm_accessible" == "false" ]]; then
        if curl -s "http://localhost:81" >/dev/null 2>&1; then
            info "✅ nginx-proxy-manager admin is accessible via localhost:81"
        else
            warn "❌ nginx-proxy-manager not accessible via localhost"
        fi
    fi
}

# Provide restore summary
provide_restore_summary() {
    local stack_state_file="$1"
    
    info "\n" "=== RESTORE SUMMARY ==="
    
    if [[ -f "$stack_state_file" ]]; then
        local backup_timestamp backup_stack_count backup_stacks
        backup_timestamp=$(jq -r '.timestamp // "Unknown"' "$stack_state_file" 2>/dev/null)
        backup_stack_count=$(jq -r '.stacks | length' "$stack_state_file" 2>/dev/null)
        backup_stacks=$(jq -r '.stacks[].name' "$stack_state_file" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
        
        info "📅 Backup created: $backup_timestamp"
        info "📦 Stacks restored: $backup_stack_count"
        info "🏗️  Stack names: $backup_stacks"
    else
        info "📦 Backup restored without stack state information"
    fi
    
    info "\n" "=== SERVICE ACCESS ==="
    if [[ -n "$DOMAIN_NAME" ]]; then
        info "🌐 Portainer: https://$PORTAINER_SUBDOMAIN.$DOMAIN_NAME"
        info "🌐 nginx-proxy-manager: https://$NPM_SUBDOMAIN.$DOMAIN_NAME"
    else
        info "🌐 Portainer: http://localhost:9000"
        info "🌐 nginx-proxy-manager: http://localhost:81"
    fi
    
    info "\n" "=== NOTES ==="
    info "⏱️  Services may take a few minutes to fully initialize"
    info "🔍 Check service logs if any issues occur: docker logs <container_name>"
    info "📋 Use 'docker ps' to verify all containers are running"
    
    success "Restore completed successfully!"
}

restore_stacks_from_backup() {
    local stack_state_file="$1"
    
    if [[ ! -f "$stack_state_file" ]]; then
        warn "Stack state file not found: $stack_state_file"
        return 0
    fi
    
    source "$PORTAINER_PATH/.credentials"
    
    # Login to Portainer API
    local auth_response
    auth_response=$(curl -s -X POST "$PORTAINER_API_URL/auth" \
        -H "Content-Type: application/json" \
        -d "{\"Username\": \"$PORTAINER_ADMIN_USERNAME\", \"Password\": \"$PORTAINER_ADMIN_PASSWORD\"}")
    
    local jwt_token
    jwt_token=$(echo "$auth_response" | jq -r '.jwt // empty')
    
    if [[ -z "$jwt_token" ]]; then
        error "Failed to authenticate with Portainer API"
        return 1
    fi
    
    # Get stacks from backup and restore them
    local backup_stack_names
    backup_stack_names=$(jq -r '.stacks[].name' "$stack_state_file" 2>/dev/null)
    
    if [[ -z "$backup_stack_names" ]]; then
        info "No stacks found in backup to restore"
        return 0
    fi
    
    info "Restoring stacks from backup: $(echo "$backup_stack_names" | tr '\n' ' ')"
    
    # Use the existing restart_stacks function but ensure we start fresh
    restart_stacks "$stack_state_file"
    
    success "Stack restoration from backup completed"
}

# Fallback function to restore critical stacks when stack states are missing
restore_critical_stacks_fallback() {
    info "Attempting to restore critical stacks using fallback detection..."
    
    # Give Portainer a moment to fully initialize after restart
    info "Waiting for Portainer API to be fully ready..."
    sleep 5
    
    # Load Portainer credentials
    source "$PORTAINER_PATH/.credentials"
    
    # Login to Portainer API with retry logic
    local jwt_token=""
    local auth_attempts=0
    local max_auth_attempts=3
    
    while [[ $auth_attempts -lt $max_auth_attempts && -z "$jwt_token" ]]; do
        info "Authentication attempt $((auth_attempts + 1))/$max_auth_attempts..."
        local auth_response
        auth_response=$(curl -s -X POST "$PORTAINER_API_URL/auth" \
            -H "Content-Type: application/json" \
            -d "{\"Username\": \"$PORTAINER_ADMIN_USERNAME\", \"Password\": \"$PORTAINER_ADMIN_PASSWORD\"}")
        
        info "Auth response length: ${#auth_response}"
        
        if [[ -n "$auth_response" ]]; then
            jwt_token=$(echo "$auth_response" | jq -r '.jwt // empty')
            if [[ -n "$jwt_token" && "$jwt_token" != "null" && "$jwt_token" != "empty" ]]; then
                info "Successfully authenticated with Portainer API"
                break
            else
                warn "Authentication response: $auth_response"
            fi
        fi
        
        auth_attempts=$((auth_attempts + 1))
        if [[ $auth_attempts -lt $max_auth_attempts ]]; then
            info "Waiting before retry..."
            sleep 10
        fi
    done
    
    if [[ -z "$jwt_token" || "$jwt_token" == "null" || "$jwt_token" == "empty" ]]; then
        error "Failed to authenticate with Portainer API after $max_auth_attempts attempts"
        return 1
    fi
    
    # Get endpoint ID (usually 1 for local Docker)
    local endpoint_id=1
    
    # Check for nginx-proxy-manager stack
    if [[ -d "$TOOLS_PATH/nginx-proxy-manager" && -f "$TOOLS_PATH/nginx-proxy-manager/docker-compose.yml" ]]; then
        info "Detected nginx-proxy-manager data - creating stack..."
        create_stack_from_compose "nginx-proxy-manager" "$TOOLS_PATH/nginx-proxy-manager/docker-compose.yml" "$jwt_token" "$endpoint_id"
    fi
    
    # Check for other common stacks
    info "Scanning $TOOLS_PATH for additional stacks..."
    for stack_dir in "$TOOLS_PATH"/*; do
        local stack_name=$(basename "$stack_dir")
        info "Examining directory: $stack_dir (stack name: $stack_name)"
        
        if [[ -d "$stack_dir" ]]; then
            info "  Directory exists: $stack_dir"
            if [[ -f "$stack_dir/docker-compose.yml" ]]; then
                info "  Found docker-compose.yml: $stack_dir/docker-compose.yml"
                if [[ "$stack_name" != "nginx-proxy-manager" ]]; then
                    info "Detected $stack_name data - creating stack..."
                    create_stack_from_compose "$stack_name" "$stack_dir/docker-compose.yml" "$jwt_token" "$endpoint_id"
                else
                    info "  Skipping nginx-proxy-manager (already processed)"
                fi
            else
                info "  No docker-compose.yml found in: $stack_dir"
            fi
        else
            info "  Not a directory: $stack_dir"
        fi
    done
    
    success "Fallback stack restoration completed"
}

# Create a stack from docker-compose file via Portainer API
create_stack_from_compose() {
    local stack_name="$1"
    local compose_file="$2"
    local jwt_token="$3"
    local endpoint_id="$4"
    
    if [[ ! -f "$compose_file" ]]; then
        warn "Compose file not found for $stack_name: $compose_file"
        return 1
    fi
    
    # Read compose file content
    local compose_content
    compose_content=$(cat "$compose_file")
    
    # Get the correct endpoint ID dynamically
    local endpoints_response
    endpoints_response=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/endpoints")
    
    if [[ -n "$endpoints_response" ]] && echo "$endpoints_response" | jq -e '.[0].Id' >/dev/null 2>&1; then
        endpoint_id=$(echo "$endpoints_response" | jq -r '.[0].Id')
        info "Using endpoint ID: $endpoint_id"
    else
        warn "Could not get endpoint ID, using default: 1"
        endpoint_id=1
    fi
    
    # Create stack payload with proper JSON formatting
    local payload
    payload=$(jq -n \
        --arg name "$stack_name" \
        --arg compose "$compose_content" \
        '{
            Name: $name,
            ComposeContent: $compose,
            Env: []
        }')
    
    info "Creating stack via API: $stack_name"
    info "API URL: $PORTAINER_API_URL/stacks?type=2&method=string&endpointId=$endpoint_id"
    
    # Create stack via Portainer API
    local stack_response
    stack_response=$(curl -s -X POST "$PORTAINER_API_URL/stacks?type=2&method=string&endpointId=$endpoint_id" \
        -H "Authorization: Bearer $jwt_token" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    info "API Response length: ${#stack_response}"
    
    if [[ -n "$stack_response" ]] && echo "$stack_response" | jq -e '.Id' >/dev/null 2>&1; then
        local stack_id
        stack_id=$(echo "$stack_response" | jq -r '.Id')
        success "Created stack: $stack_name (ID: $stack_id)"
    else
        warn "Failed to create stack: $stack_name"
        if [[ -n "$stack_response" ]]; then
            warn "API Response: $stack_response"
            # Try to parse error message if available
            local error_msg
            error_msg=$(echo "$stack_response" | jq -r '.message // .err // .error // "Unknown error"' 2>/dev/null || echo "Invalid JSON response")
            warn "Error details: $error_msg"
        else
            warn "Empty API response - possible authentication or connectivity issue"
        fi
        
        # API-only approach as requested - no fallbacks to direct docker compose
        error "Failed to create stack via Portainer API: $stack_name"
        error "Check Portainer logs and network connectivity, then try again"
        return 1
    fi
}

# Create stack using Docker Compose with Portainer-compatible labels
create_stack_via_compose() {
    local stack_name="$1"
    local compose_file="$2"
    
    info "Creating stack via Docker Compose: $stack_name"
    
    # Navigate to the stack directory
    local stack_dir
    stack_dir=$(dirname "$compose_file")
    
    cd "$stack_dir" || {
        error "Could not navigate to stack directory: $stack_dir"
        return 1
    }
    
    # Create the stack using docker compose with project name
    if sudo -u "$PORTAINER_USER" docker compose -p "$stack_name" up -d; then
        success "Created stack via Docker Compose: $stack_name"
        
        # Note: Docker Compose already adds proper labels for Portainer management
        # The com.docker.compose.project label allows Portainer to detect and manage the stack
        info "Stack created with Docker Compose - Portainer should detect it automatically"
        
        return 0
    else
        error "Failed to create stack via Docker Compose: $stack_name"
        return 1
    fi
}

# Restart Portainer after restore operations to ensure clean state consistency
restart_portainer_after_restore() {
    info "Restarting Portainer to ensure clean state consistency after restore..."
    
    # Check if Portainer is running
    local portainer_running=false
    if sudo -u "$PORTAINER_USER" docker ps --format "{{.Names}}" | grep -q "^portainer$"; then
        portainer_running=true
        info "Portainer is currently running - performing restart"
    else
        info "Portainer is not running - starting it"
    fi
    
    # Navigate to Portainer directory
    cd "$PORTAINER_PATH" || {
        error "Could not navigate to Portainer directory: $PORTAINER_PATH"
        return 1
    }
    
    # Restart Portainer using docker compose
    if [[ "$portainer_running" == "true" ]]; then
        info "Restarting Portainer container..."
        if ! sudo -u "$PORTAINER_USER" docker compose restart; then
            warn "Docker compose restart failed, trying stop/start sequence"
            sudo -u "$PORTAINER_USER" docker compose stop
            sleep 5
            sudo -u "$PORTAINER_USER" docker compose up -d
        fi
    else
        info "Starting Portainer container..."
        sudo -u "$PORTAINER_USER" docker compose up -d
    fi
    
    # Wait for Portainer to be ready
    local max_wait=120  # Increased timeout for containers with health checks
    local wait_count=0
    info "Waiting for Portainer to be ready after restart..."
    
    while [[ $wait_count -lt $max_wait ]]; do
        if curl -s "http://localhost:9000" >/dev/null 2>&1; then
            success "Portainer is ready and accessible"
            break
        fi
        
        sleep 2
        wait_count=$((wait_count + 2))
        
        if [[ $((wait_count % 10)) -eq 0 ]]; then
            info "Still waiting for Portainer... ($wait_count/${max_wait}s)"
        fi
    done
    
    if [[ $wait_count -ge $max_wait ]]; then
        warn "Portainer restart completed but may not be fully ready yet"
        warn "Services may take additional time to initialize"
    else
        success "Portainer restart completed successfully"
    fi
    
    # Give a bit more time for internal initialization
    sleep 10
}

# Create backup
create_backup() {
    info "Starting backup process..."
    
    # Create operation lock and recovery info
    create_operation_lock "backup" || return 1
    create_recovery_info "backup"
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_name="docker_backup_${timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_backup_file="$BACKUP_PATH/${backup_name}.tar.gz"
    
    # Set TEMP_DIR for use by other functions
    TEMP_DIR="$temp_backup_dir"
    
    # Create temporary backup directory
    mkdir -p "$temp_backup_dir"
    
    # Capture stack states before stopping containers
    get_stack_states "$temp_backup_dir/stack_states.json"
    
    # Generate metadata file for enhanced reliability
    generate_backup_metadata "$temp_backup_dir"
    
    # Stop containers gracefully
    stop_containers
    
    info "Creating backup archive..."
    
    # Ensure backup directory has correct permissions
    sudo chown -R "$PORTAINER_USER:$PORTAINER_USER" "$BACKUP_PATH"
    sudo chmod 755 "$BACKUP_PATH"
    
    # Get active stack directories from stack states
    local active_stack_dirs=""
    if [[ -f "$temp_backup_dir/stack_states.json" ]]; then
        # Extract stack names from the stack states JSON
        local stack_names
        stack_names=$(jq -r '.stacks[].name' "$temp_backup_dir/stack_states.json" 2>/dev/null || echo "")
        
        if [[ -n "$stack_names" ]]; then
            info "Identified active stacks for backup: $(echo "$stack_names" | tr '\n' ' ')"
            while read -r stack_name; do
                if [[ -n "$stack_name" ]] && [[ -d "$TOOLS_PATH/$stack_name" ]]; then
                    active_stack_dirs="$active_stack_dirs $(echo "$TOOLS_PATH/$stack_name" | sed 's|^/||')"
                fi
            done <<< "$stack_names"
        fi
    fi
    
    # If no active stacks found or stack states unavailable, backup all of tools directory
    if [[ -z "$active_stack_dirs" ]]; then
        warn "No active stack directories identified, backing up entire tools directory"
        active_stack_dirs="$(echo $TOOLS_PATH | sed 's|^/||')"
    else
        info "Backing up only active stack directories to ensure clean restore"
    fi
    
    # Create backup with preserved permissions  
    cd /
    if [[ -f "$temp_backup_dir/stack_states.json" ]] || [[ -f "$temp_backup_dir/backup_metadata.json" ]]; then
        # Create uncompressed tar first, add additional files, then compress
        sudo tar --same-owner --same-permissions -cf "${final_backup_file%.gz}" \
            "$(echo $PORTAINER_PATH | sed 's|^/||')" \
            $active_stack_dirs
        
        # Add stack states if available
        if [[ -f "$temp_backup_dir/stack_states.json" ]]; then
            sudo tar --same-owner --same-permissions -rf "${final_backup_file%.gz}" \
                -C "$temp_backup_dir" stack_states.json
        fi
        
        # Add metadata file if available
        if [[ -f "$temp_backup_dir/backup_metadata.json" ]]; then
            sudo tar --same-owner --same-permissions -rf "${final_backup_file%.gz}" \
                -C "$temp_backup_dir" backup_metadata.json
        fi
        
        sudo gzip "${final_backup_file%.gz}"
    else
        # Create compressed tar directly if no additional files
        sudo tar --same-owner --same-permissions -czf "$final_backup_file" \
            "$(echo $PORTAINER_PATH | sed 's|^/||')" \
            $active_stack_dirs
    fi
    
    # Ensure backup file has correct ownership
    sudo chown "$PORTAINER_USER:$PORTAINER_USER" "$final_backup_file"
    
    # Start containers again
    start_containers
    
    # Restart stacks that were running before backup
    restart_stacks "$temp_backup_dir/stack_states.json"
    
    # Clean up temporary directory
    rm -rf "$temp_backup_dir"
    
    # Manage backup retention
    manage_backup_retention
    
    if [[ -f "$final_backup_file" ]]; then
        success "Backup created: $final_backup_file"
        info "Backup size: $(du -h "$final_backup_file" | cut -f1)"
        
        # Store backup file path for validation
        LATEST_BACKUP="$final_backup_file"
        
        # Validate system state after backup
        if validate_system_state "backup"; then
            success "Backup completed successfully with validation"
        else
            warn "Backup completed but system validation failed"
            warn "Check system status and recovery information if needed"
        fi
    else
        error "Backup creation failed"
        return 1
    fi
}

# Manage backup retention
manage_backup_retention() {
    info "Managing backup retention (keeping last $BACKUP_RETENTION backups)..."
    
    local backup_count
    backup_count=$(ls -1 "$BACKUP_PATH"/docker_backup_*.tar.gz 2>/dev/null | wc -l)
    
    if [[ $backup_count -gt $BACKUP_RETENTION ]]; then
        local excess_count=$((backup_count - BACKUP_RETENTION))
        info "Removing $excess_count old backup(s)..."
        
        ls -1t "$BACKUP_PATH"/docker_backup_*.tar.gz | tail -n "$excess_count" | while read -r old_backup; do
            rm -f "$old_backup"
            info "Removed old backup: $(basename "$old_backup")"
        done
    fi
}

# Restore using metadata file for enhanced reliability
restore_using_metadata() {
    local metadata_file="$1"
    
    if [[ ! -f "$metadata_file" ]]; then
        warn "Metadata file not found, skipping metadata-based restore"
        return 0
    fi
    
    info "Using metadata file for enhanced restoration..."
    
    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        warn "jq not available, skipping metadata-based restore"
        return 0
    fi
    
    # Validate metadata file
    if ! jq . "$metadata_file" >/dev/null 2>&1; then
        warn "Invalid metadata file format, skipping metadata-based restore"
        return 0
    fi
    
    # Check architecture compatibility
    local backup_arch=$(jq -r '.system.architecture // empty' "$metadata_file")
    local current_arch=$(uname -m)
    
    if [[ -n "$backup_arch" && "$backup_arch" != "$current_arch" ]]; then
        warn "Architecture mismatch detected:"
        warn "  Backup created on: $backup_arch"
        warn "  Current system: $current_arch"
        warn "  Docker images may not be compatible"
        echo
        if ! is_test_environment; then
            if ! prompt_yes_no "Continue with restore anyway?" "n"; then
                error "Restore cancelled due to architecture mismatch"
                return 1
            fi
        fi
    fi
    
    # Restore permissions using metadata
    info "Restoring permissions using metadata..."
    
    # Get permissions array from metadata
    local permissions_count=$(jq '.permissions | length' "$metadata_file" 2>/dev/null || echo "0")
    
    if [[ "$permissions_count" -gt 0 ]] && [[ "$permissions_count" != "null" ]]; then
        local restored_count=0
        
        # Process each permission entry (with a reasonable limit)
        local max_permissions=500  # Reduced limit for better performance
        local actual_count=$((permissions_count > max_permissions ? max_permissions : permissions_count))
        
        info "Restoring permissions for $actual_count files/directories..."
        
        for ((i=0; i<actual_count; i++)); do
            # Progress indicator every 10 items
            if [[ $((i % 10)) -eq 0 ]] && [[ $i -gt 0 ]]; then
                info "Processed $i/$actual_count permission entries"
            fi
            
            local path=$(jq -r ".permissions[$i].path // empty" "$metadata_file" 2>/dev/null || echo "")
            local perms=$(jq -r ".permissions[$i].permissions // empty" "$metadata_file" 2>/dev/null || echo "")
            local owner=$(jq -r ".permissions[$i].owner // empty" "$metadata_file" 2>/dev/null || echo "")
            local group=$(jq -r ".permissions[$i].group // empty" "$metadata_file" 2>/dev/null || echo "")
            
            # Skip if path is empty
            [[ -z "$path" ]] && continue
            
            # Only restore if file exists
            if [[ -e "/$path" ]]; then
                # Restore ownership
                if [[ -n "$owner" && -n "$group" && "$owner" != "null" && "$group" != "null" ]]; then
                    if id "$owner" >/dev/null 2>&1 && getent group "$group" >/dev/null 2>&1; then
                        sudo chown "$owner:$group" "/$path" 2>/dev/null || true
                    fi
                fi
                
                # Restore permissions
                if [[ -n "$perms" && "$perms" != "null" && "$perms" =~ ^[0-9]+$ ]]; then
                    sudo chmod "$perms" "/$path" 2>/dev/null || true
                fi
                
                restored_count=$((restored_count + 1))
            fi
        done
        
        success "Restored permissions for $restored_count files/directories"
        
        # If we hit the limit, warn the user
        if [[ $actual_count -lt $permissions_count ]]; then
            warn "Only processed $actual_count of $permissions_count permission entries due to safety limits"
            warn "Some file permissions may not have been fully restored"
        fi
    else
        warn "No permission information found in metadata"
    fi
    
    # Display backup information
    local backup_timestamp=$(jq -r '.timestamp // empty' "$metadata_file")
    local backup_version=$(jq -r '.script_version // empty' "$metadata_file")
    local backup_hostname=$(jq -r '.system.hostname // empty' "$metadata_file")
    
    info "Backup Information:"
    [[ -n "$backup_timestamp" ]] && info "  Created: $backup_timestamp"
    [[ -n "$backup_version" ]] && info "  Script Version: $backup_version"
    [[ -n "$backup_hostname" ]] && info "  Source Hostname: $backup_hostname"
    
    success "Metadata-based restore completed"
}

# List available backups
list_backups() {
    printf "%b\n" "${BLUE}Available backups:${NC}"
    echo
    
    local backups
    backups=($(ls -1t "$BACKUP_PATH"/docker_backup_*.tar.gz 2>/dev/null || true))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "No backups found in $BACKUP_PATH"
        return 1
    fi
    
    local i=1
    for backup in "${backups[@]}"; do
        local backup_name=$(basename "$backup")
        local backup_date=$(echo "$backup_name" | sed 's/docker_backup_\([0-9]*_[0-9]*\).tar.gz/\1/' | sed 's/_/ /')
        local backup_size=$(du -h "$backup" | cut -f1)
        printf "%2d) %s (%s) - %s\n" "$i" "$backup_name" "$backup_size" "$backup_date"
        ((i++))
    done
    
    return 0
}

# Restore from backup
restore_backup() {
    # Create operation lock and recovery info
    create_operation_lock "restore" || return 1
    create_recovery_info "restore"
    
    # Set up temporary directory for restore operations
    local temp_restore_dir="/tmp/restore_$$"
    TEMP_DIR="$temp_restore_dir"
    mkdir -p "$TEMP_DIR"
    
    if ! list_backups; then
        return 1
    fi
    
    echo
    local choice
    choice=$(prompt_user "Select backup number to restore (or 'q' to quit)" "q")
    
    if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
        info "Restore cancelled"
        return 0
    fi
    
    local backups
    backups=($(ls -1t "$BACKUP_PATH"/docker_backup_*.tar.gz 2>/dev/null))
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt ${#backups[@]} ]]; then
        error "Invalid selection"
        return 1
    fi
    
    local selected_backup="${backups[$((choice-1))]}"
    local backup_name=$(basename "$selected_backup")
    
    echo
    printf "%b\n" "${YELLOW}WARNING: This will stop all containers and restore data from backup!${NC}"
    echo "Selected backup: $backup_name"
    echo
    if ! prompt_yes_no "Are you sure you want to continue?" "n"; then
        info "Restore cancelled"
        return 0
    fi
    
    info "Restoring from backup: $backup_name"
    
    # Stop containers
    stop_containers
    
    # Create backup of current state
    local current_backup_name="pre_restore_$(date '+%Y%m%d_%H%M%S')"
    info "Creating backup of current state: $current_backup_name"
    cd /
    if ! sudo tar --same-owner --same-permissions -czf "$BACKUP_PATH/${current_backup_name}.tar.gz" \
        "$(echo $PORTAINER_PATH | sed 's|^/||')" \
        "$(echo $TOOLS_PATH | sed 's|^/||')" 2>/dev/null; then
        warn "Failed to create pre-restore backup, continuing with restore anyway"
    else
        # Fix ownership of pre-restore backup to portainer user
        sudo chown "$PORTAINER_USER:$PORTAINER_USER" "$BACKUP_PATH/${current_backup_name}.tar.gz"
    fi
    
    # Extract backup
    info "Extracting backup..."
    cd /
    if ! sudo tar --same-owner --same-permissions -xzf "$selected_backup"; then
        error "Failed to extract backup archive"
        error "The backup file may be corrupted or you may not have sufficient permissions"
        return 1
    fi
    
    # Check for metadata file and use it for enhanced restoration
    local metadata_file="/tmp/backup_metadata.json"
    if tar -tf "$selected_backup" | grep -q "backup_metadata.json"; then
        sudo tar -xzf "$selected_backup" -C /tmp backup_metadata.json 2>/dev/null || true
        if [[ -f "$metadata_file" ]]; then
            restore_using_metadata "$metadata_file"
            sudo rm -f "$metadata_file"
        fi
    fi
    
    # Implement true snapshot restore: clean system and restore only what's in backup
    implement_true_snapshot_restore "$selected_backup"
    
    # Validate restore success
    info "Validating restore completion..."
    local validation_failed=false
    
    # Check if key directories exist
    if [[ ! -d "$PORTAINER_PATH/data" ]]; then
        error "Portainer data directory not found after restore"
        validation_failed=true
    fi
    
    if [[ ! -d "$TOOLS_PATH" ]]; then
        error "Tools directory not found after restore"
        validation_failed=true
    fi
    
    # Check if Portainer is accessible
    sleep 10  # Give a bit more time for startup
    if ! curl -s "http://localhost:9000" >/dev/null 2>&1; then
        warn "Portainer may not be fully accessible yet (this is normal immediately after restore)"
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        error "Restore validation failed - some components may not have restored correctly"
        error "Check the logs and consider restoring from a different backup"
        return 1
    fi
    
    # Clean up temporary directory
    rm -rf "$TEMP_DIR"
    
    # Restart Portainer after restore to ensure clean state consistency
    restart_portainer_after_restore
    
    # Validate system state after restore
    if validate_system_state "restore"; then
        success "Restore completed and validated successfully"
        success "Portainer available at: $PORTAINER_URL"
        info "Note: Services may take a few minutes to fully initialize"
    else
        error "Restore completed but system validation failed"
        error "System may be in an inconsistent state"
        error "Check recovery information and logs for troubleshooting"
        return 1
    fi
}

# Validate cron expression format
validate_cron_expression() {
    local cron_expr="$1"
    
    # Remove extra whitespace and split into fields
    cron_expr=$(echo "$cron_expr" | tr -s ' ')
    local fields=($cron_expr)
    
    # Check if we have exactly 5 fields
    if [[ ${#fields[@]} -ne 5 ]]; then
        error "Cron expression must have exactly 5 fields (minute hour day month weekday)"
        return 1
    fi
    
    local minute="${fields[0]}"
    local hour="${fields[1]}"
    local day="${fields[2]}"
    local month="${fields[3]}"
    local weekday="${fields[4]}"
    
    # Validate each field using cron field validation
    if ! validate_cron_field "$minute" 0 59 "minute"; then
        return 1
    fi
    
    if ! validate_cron_field "$hour" 0 23 "hour"; then
        return 1
    fi
    
    if ! validate_cron_field "$day" 1 31 "day"; then
        return 1
    fi
    
    if ! validate_cron_field "$month" 1 12 "month"; then
        return 1
    fi
    
    if ! validate_cron_field "$weekday" 0 7 "weekday"; then
        return 1
    fi
    
    return 0
}

# Validate individual cron field
validate_cron_field() {
    local field="$1"
    local min_val="$2"
    local max_val="$3"
    local field_name="$4"
    
    # Handle wildcard
    if [[ "$field" == "*" ]]; then
        return 0
    fi
    
    # Handle step values (e.g., */6, 2-10/2)
    if [[ "$field" =~ ^(.+)/([0-9]+)$ ]]; then
        local base_field="${BASH_REMATCH[1]}"
        local step="${BASH_REMATCH[2]}"
        
        # Validate step value
        if [[ $step -lt 1 ]]; then
            error "Step value must be at least 1 for $field_name"
            return 1
        fi
        
        # Recursively validate the base field
        if ! validate_cron_field "$base_field" "$min_val" "$max_val" "$field_name"; then
            return 1
        fi
        
        return 0
    fi
    
    # Handle ranges (e.g., 1-5, 10-20)
    if [[ "$field" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        
        if [[ $start -lt $min_val || $start -gt $max_val ]]; then
            error "Range start $start is out of bounds for $field_name ($min_val-$max_val)"
            return 1
        fi
        
        if [[ $end -lt $min_val || $end -gt $max_val ]]; then
            error "Range end $end is out of bounds for $field_name ($min_val-$max_val)"
            return 1
        fi
        
        if [[ $start -gt $end ]]; then
            error "Range start $start cannot be greater than end $end for $field_name"
            return 1
        fi
        
        return 0
    fi
    
    # Handle comma-separated lists (e.g., 1,3,5)
    if [[ "$field" =~ , ]]; then
        local IFS=','
        local values=($field)
        for value in "${values[@]}"; do
            if ! validate_cron_field "$value" "$min_val" "$max_val" "$field_name"; then
                return 1
            fi
        done
        return 0
    fi
    
    # Handle single number
    if [[ "$field" =~ ^[0-9]+$ ]]; then
        if [[ $field -lt $min_val || $field -gt $max_val ]]; then
            error "Value $field is out of bounds for $field_name ($min_val-$max_val)"
            return 1
        fi
        return 0
    fi
    
    error "Invalid format '$field' for $field_name"
    return 1
}

# Setup backup scheduling
setup_schedule() {
    printf "%b\n" "${BLUE}=== Backup Scheduling Setup ===${NC}"
    echo
    
    echo "Current cron jobs for user $PORTAINER_USER:"
    if [[ "$(whoami)" == "$PORTAINER_USER" ]]; then
        crontab -l 2>/dev/null || echo "No cron jobs found"
    else
        sudo -u "$PORTAINER_USER" crontab -l 2>/dev/null || echo "No cron jobs found"
    fi
    echo
    
    echo "Schedule options:"
    echo "1) Daily at 3:00 AM (recommended)"
    echo "2) Daily at 2:00 AM"
    echo "3) Every 12 hours"
    echo "4) Every 6 hours"
    echo "5) Custom schedule"
    echo "6) Test mode (every 30 seconds - for testing only)"
    echo "7) Remove scheduled backups"
    echo
    
    if is_test_environment && [[ ! -t 0 ]]; then
        # Non-interactive mode - read from stdin
        read schedule_choice
    else
        read -p "Select option [1-7]: " schedule_choice
    fi
    
    local cron_schedule=""
    local backup_script_path
    local current_user="$(whoami)"
    
    # Always use the script in /opt/backup for cron jobs - system-wide location
    # This ensures any user can set up cron jobs and the portainer user can always access it
    local system_script_path="/opt/backup/docker-backup-manager.sh"
    
    info "Setting up system-wide script location for cron execution..."
    
    # Ensure /opt/backup directory exists and has proper permissions
    sudo mkdir -p "/opt/backup"
    sudo chown root:root "/opt/backup"
    sudo chmod 755 "/opt/backup"
    
    # Copy current script to system location
    if sudo cp "$0" "$system_script_path"; then
        sudo chown root:root "$system_script_path"
        sudo chmod 755 "$system_script_path"
        success "Script installed to system location: $system_script_path"
    else
        error "Failed to copy script to system location"
        # Fallback to current script path
        if command -v realpath >/dev/null 2>&1; then
            backup_script_path="$(realpath "$0")"
        else
            backup_script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
        fi
        warn "Using current script location for cron: $backup_script_path"
        warn "Note: This may cause permission issues with cron execution"
        return
    fi
    
    # Use the system script path for cron jobs
    backup_script_path="$system_script_path"
    
    case "$schedule_choice" in
        1)
            cron_schedule="0 3 * * *"
            ;;
        2)
            cron_schedule="0 2 * * *"
            ;;
        3)
            cron_schedule="0 */12 * * *"
            ;;
        4)
            cron_schedule="0 */6 * * *"
            ;;
        5)
            echo
            echo "Custom cron schedule examples:"
            echo "  '0 3 * * *'     - Daily at 3:00 AM"
            echo "  '0 */6 * * *'   - Every 6 hours"
            echo "  '30 2 * * 0'    - Weekly on Sunday at 2:30 AM"
            echo "  '0 1 1 * *'     - Monthly on the 1st at 1:00 AM"
            echo "  '15 14 * * 1-5' - Weekdays at 2:15 PM"
            echo
            echo "Format: minute hour day month weekday"
            echo "  minute: 0-59, hour: 0-23, day: 1-31, month: 1-12, weekday: 0-7 (0=Sunday)"
            echo
            
            local valid_cron=false
            local attempts=0
            local max_attempts=3
            
            while [[ "$valid_cron" == false && $attempts -lt $max_attempts ]]; do
                if is_test_environment && [[ ! -t 0 ]]; then
                    # Non-interactive mode - read from stdin
                    read cron_schedule
                    valid_cron=true  # Skip validation in test mode
                else
                    read -p "Enter cron schedule: " cron_schedule
                    
                    if validate_cron_expression "$cron_schedule"; then
                        valid_cron=true
                    else
                        ((attempts++))
                        if [[ $attempts -lt $max_attempts ]]; then
                            warn "Invalid cron expression. Please try again ($attempts/$max_attempts attempts used)."
                            echo
                        fi
                    fi
                fi
            done
            
            if [[ "$valid_cron" == false ]]; then
                error "Failed to enter valid cron expression after $max_attempts attempts"
                return 1
            fi
            ;;
        6)
            cron_schedule="* * * * *"
            warn "TEST MODE: Backup will run every minute!"
            warn "This is for testing only - remember to remove this schedule"
            
            # Set test retention in config for quick testing
            if [[ -f "$CONFIG_FILE" ]]; then
                # Update existing config
                sudo sed -i 's/^BACKUP_RETENTION=.*/BACKUP_RETENTION="2"/' "$CONFIG_FILE" || \
                echo 'BACKUP_RETENTION="2"' | sudo tee -a "$CONFIG_FILE" >/dev/null
            else
                # Create config with test retention
                echo 'BACKUP_RETENTION="2"' | sudo tee "$CONFIG_FILE" >/dev/null
            fi
            info "Set backup retention to 2 for testing (will keep only 2 most recent backups)"
            ;;
        7)
            # Remove ALL docker-backup-manager.sh cron jobs (any path)
            if [[ "$(whoami)" == "$PORTAINER_USER" ]]; then
                # Already running as portainer user - don't use sudo
                crontab -l 2>/dev/null | grep -v "docker-backup-manager.sh backup" | crontab -
            else
                # Running as different user - use sudo
                sudo -u "$PORTAINER_USER" crontab -l 2>/dev/null | grep -v "docker-backup-manager.sh backup" | sudo -u "$PORTAINER_USER" crontab -
            fi
            success "Removed all scheduled backups"
            return 0
            ;;
        *)
            error "Invalid option"
            return 1
            ;;
    esac
    
    if [[ -n "$cron_schedule" ]]; then
        # Debug: show what we're trying to add
        if is_test_environment; then
            info "DEBUG: Adding cron job: $cron_schedule $backup_script_path backup >> $LOG_FILE 2>&1"
        fi
        
        # Add backup job to crontab (remove any existing docker-backup-manager.sh entries first)
        local cron_result=0
        if [[ "$(whoami)" == "$PORTAINER_USER" ]]; then
            # Already running as portainer user - don't use sudo
            (crontab -l 2>/dev/null | grep -v "docker-backup-manager.sh backup"; echo "$cron_schedule $backup_script_path backup >> $LOG_FILE 2>&1") | crontab - || cron_result=$?
        else
            # Running as different user - use sudo
            (sudo -u "$PORTAINER_USER" crontab -l 2>/dev/null | grep -v "docker-backup-manager.sh backup"; echo "$cron_schedule $backup_script_path backup >> $LOG_FILE 2>&1") | sudo -u "$PORTAINER_USER" crontab - || cron_result=$?
        fi
        
        if [[ $cron_result -eq 0 ]]; then
            success "Backup scheduled: $cron_schedule"
        else
            error "Failed to create cron job (exit code: $cron_result)"
            return 1
        fi
        info "Logs will be written to: $LOG_FILE"
        
        # Show current crontab
        echo
        echo "Current cron jobs:"
        if [[ "$(whoami)" == "$PORTAINER_USER" ]]; then
            crontab -l
        else
            sudo -u "$PORTAINER_USER" crontab -l
        fi
    fi
}

# Generate self-contained NAS backup script
generate_nas_script() {
    info "Generating Self-Contained NAS Backup Script"
    info "=============================================="
    echo
    
    # Get primary server details
    PRIMARY_SERVER_IP=$(hostname -I | awk '{print $2}' | head -1)  # Get host-only IP
    if [[ -z "$PRIMARY_SERVER_IP" || "$PRIMARY_SERVER_IP" == "127.0.0.1" ]]; then
        PRIMARY_SERVER_IP=$(ip route get 8.8.8.8 | grep -oP 'src \K[^ ]+' 2>/dev/null || echo "192.168.56.10")
    fi
    
    info "Primary server IP: $PRIMARY_SERVER_IP"
    
    # Check if SSH key exists
    SSH_KEY_PATH="/home/$PORTAINER_USER/.ssh/id_ed25519"
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        error "SSH private key not found at: $SSH_KEY_PATH"
        error "Please ensure Docker backup manager setup has been completed"
        return 1
    fi
    
    # Get the SSH private key
    SSH_PRIVATE_KEY=$(sudo cat "$SSH_KEY_PATH" | base64 -w 0)
    info "SSH private key extracted and encoded"
    
    # Generate the self-contained script in a writable location
    OUTPUT_SCRIPT="/tmp/nas-backup-client.sh"
    info "Generating self-contained script: $OUTPUT_SCRIPT"
    
    cat > "$OUTPUT_SCRIPT" << 'EOF'
#!/bin/bash

# Self-Contained NAS Backup Client
# Generated automatically from Docker Backup Manager
# This script contains embedded SSH key and requires no additional setup

set -euo pipefail

# =================================================================
# CONFIGURATION - EDIT THESE VALUES FOR YOUR ENVIRONMENT
# =================================================================

# Primary server connection details
PRIMARY_SERVER_IP="__PRIMARY_SERVER_IP__"
PRIMARY_SERVER_USER="portainer"
PRIMARY_BACKUP_PATH="/opt/backup"

# Local backup storage (change this for your NAS)
# In test mode, use local backup directory that's gitignored
if [[ "${DOCKER_BACKUP_TEST:-false}" == "true" ]]; then
    LOCAL_BACKUP_PATH="./backup"  # Test mode: use local backup directory
else
    LOCAL_BACKUP_PATH="/volume1/backup/zuptalo"  # Production: NAS path
fi
RETENTION_DAYS=30

# Temporary directory for SSH key
TEMP_DIR="/tmp/docker-backup-$$"
SSH_KEY_FILE="$TEMP_DIR/primary_key"

# =================================================================
# EMBEDDED SSH PRIVATE KEY (DO NOT EDIT BELOW THIS LINE)
# =================================================================

SSH_PRIVATE_KEY_B64="__SSH_PRIVATE_KEY_B64__"

# Colors for output - enable if terminal supports colors
if [[ "${TERM:-}" == *"color"* ]] || [[ "${TERM:-}" == "xterm"* ]] || [[ "${TERM:-}" == "screen"* ]] || [[ "${TERM:-}" == "tmux"* ]]; then
    # Known color terminals - enable colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
elif [[ "${TERM:-}" != "dumb" ]] && command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1 && [[ "$(tput colors)" -ge 8 ]]; then
    # Fallback to tput detection (removed TTY check for SSH compatibility)
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    # No colors
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "%b\n" "${timestamp} [${level}] ${message}"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Cleanup function
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# Setup SSH key from embedded data
setup_ssh_key() {
    info "Setting up SSH authentication..."
    
    mkdir -p "$TEMP_DIR"
    chmod 700 "$TEMP_DIR"
    
    # Decode and save SSH private key
    echo "$SSH_PRIVATE_KEY_B64" | base64 -d > "$SSH_KEY_FILE"
    chmod 600 "$SSH_KEY_FILE"
    
    success "SSH key prepared"
}

# Test SSH connectivity
test_ssh_connection() {
    info "Testing SSH connection to $PRIMARY_SERVER_IP..."
    
    if ssh -i "$SSH_KEY_FILE" -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no \
           "$PRIMARY_SERVER_USER@$PRIMARY_SERVER_IP" 'echo "SSH connection successful"' >/dev/null 2>&1; then
        success "SSH connection established"
        return 0
    else
        error "SSH connection failed"
        error "Please verify:"
        error "1. Primary server IP: $PRIMARY_SERVER_IP"
        error "2. Primary server is running and accessible"
        error "3. Docker backup manager is properly configured"
        return 1
    fi
}

# Create local backup directory
setup_local_directory() {
    info "Setting up local backup directory: $LOCAL_BACKUP_PATH"
    
    # Create directory if it doesn't exist
    if [[ ! -d "$LOCAL_BACKUP_PATH" ]]; then
        mkdir -p "$LOCAL_BACKUP_PATH" || {
            error "Failed to create backup directory: $LOCAL_BACKUP_PATH"
            error "Please ensure you have write permissions to the parent directory"
            return 1
        }
        success "Created local backup directory"
    else
        success "Local backup directory already exists"
    fi
    
    # Verify we can write to the directory
    if [[ ! -w "$LOCAL_BACKUP_PATH" ]]; then
        error "Cannot write to backup directory: $LOCAL_BACKUP_PATH"
        error "Please ensure the directory has proper permissions for your user"
        return 1
    fi
}

# Get list of backup files from primary server
list_remote_backups() {
    info "Getting backup file list from primary server..."
    
    ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no \
        "$PRIMARY_SERVER_USER@$PRIMARY_SERVER_IP" \
        "find $PRIMARY_BACKUP_PATH -name 'docker_backup_*.tar.gz' -type f | sort" 2>/dev/null || {
        warn "Could not retrieve backup list from primary server"
        return 1
    }
}

# Sync backup files from primary server
sync_backups() {
    info "Syncing backup files from primary server..."
    
    # First, list what backup files are available
    info "Available backup files on primary server:"
    ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no \
        "$PRIMARY_SERVER_USER@$PRIMARY_SERVER_IP" \
        "ls -la $PRIMARY_BACKUP_PATH/docker_backup_*.tar.gz 2>/dev/null || echo 'No backup files found'"
    
    # Use rsync for efficient copying - try direct file copy approach
    local rsync_result=0
    info "Running: rsync from $PRIMARY_SERVER_USER@$PRIMARY_SERVER_IP:$PRIMARY_BACKUP_PATH/ to $LOCAL_BACKUP_PATH/"
    
    # Get list of backup files and sync them individually
    local backup_files
    backup_files=$(ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no \
        "$PRIMARY_SERVER_USER@$PRIMARY_SERVER_IP" \
        "ls $PRIMARY_BACKUP_PATH/docker_backup_*.tar.gz 2>/dev/null || true")
    
    if [[ -n "$backup_files" ]]; then
        echo "$backup_files" | while read -r backup_file; do
            if [[ -n "$backup_file" ]]; then
                info "Syncing: $(basename "$backup_file")"
                rsync -avz --progress \
                      -e "ssh -i $SSH_KEY_FILE -o StrictHostKeyChecking=no" \
                      "$PRIMARY_SERVER_USER@$PRIMARY_SERVER_IP:$backup_file" \
                      "$LOCAL_BACKUP_PATH/" || rsync_result=$?
            fi
        done
    else
        warn "No backup files found on primary server"
        return 1
    fi
    
    if [[ $rsync_result -eq 0 ]]; then
        success "Backup sync completed successfully"
        
        # Count synced files
        local backup_count=$(ls -1 "$LOCAL_BACKUP_PATH"/docker_backup_*.tar.gz 2>/dev/null | wc -l)
        info "Total backups in local storage: $backup_count"
        
        # Show latest backups
        if [[ $backup_count -gt 0 ]]; then
            info "Latest backups:"
            ls -lt "$LOCAL_BACKUP_PATH"/docker_backup_*.tar.gz 2>/dev/null | head -5 | while read -r line; do
                info "  $line"
            done
        fi
        
    elif [[ $rsync_result -eq 23 ]]; then
        warn "Some files could not be transferred (possibly no new backups)"
    else
        error "Backup sync failed with exit code: $rsync_result"
        return 1
    fi
}

# Clean up old backups
cleanup_old_backups() {
    info "Managing backup retention (keeping last $RETENTION_DAYS days)..."
    
    local deleted_count=0
    find "$LOCAL_BACKUP_PATH" -name "docker_backup_*.tar.gz" -type f -mtime +$RETENTION_DAYS -print | \
    while read -r old_backup; do
        info "Removing old backup: $(basename "$old_backup")"
        rm -f "$old_backup"
        ((deleted_count++))
    done
    
    if [[ $deleted_count -gt 0 ]]; then
        info "Removed $deleted_count old backup(s)"
    else
        info "No old backups to remove"
    fi
}

# Get backup statistics
show_backup_stats() {
    info "Backup Statistics:"
    
    local total_backups=$(ls -1 "$LOCAL_BACKUP_PATH"/docker_backup_*.tar.gz 2>/dev/null | wc -l)
    local total_size=$(du -sh "$LOCAL_BACKUP_PATH" 2>/dev/null | cut -f1)
    local newest_backup=$(ls -t "$LOCAL_BACKUP_PATH"/docker_backup_*.tar.gz 2>/dev/null | head -1)
    local oldest_backup=$(ls -t "$LOCAL_BACKUP_PATH"/docker_backup_*.tar.gz 2>/dev/null | tail -1)
    
    info "  Total backups: $total_backups"
    info "  Total size: $total_size"
    info "  Local path: $LOCAL_BACKUP_PATH"
    
    if [[ -n "$newest_backup" ]]; then
        info "  Newest backup: $(basename "$newest_backup")"
        info "  Newest backup date: $(stat -c %y "$newest_backup" 2>/dev/null | cut -d' ' -f1)"
    fi
    
    if [[ -n "$oldest_backup" && "$oldest_backup" != "$newest_backup" ]]; then
        info "  Oldest backup: $(basename "$oldest_backup")"
        info "  Oldest backup date: $(stat -c %y "$oldest_backup" 2>/dev/null | cut -d' ' -f1)"
    fi
}

# Main execution
main() {
    info "Starting Self-Contained NAS Backup Client"
    info "=========================================="
    
    setup_ssh_key
    test_ssh_connection || exit 1
    setup_local_directory
    
    info "Configuration:"
    info "  Primary server: $PRIMARY_SERVER_USER@$PRIMARY_SERVER_IP"
    info "  Remote path: $PRIMARY_BACKUP_PATH"
    info "  Local path: $LOCAL_BACKUP_PATH"
    info "  Retention: $RETENTION_DAYS days"
    
    # Perform the backup sync
    sync_backups || exit 1
    cleanup_old_backups
    show_backup_stats
    
    success "Backup sync operation completed successfully"
}

# Handle command line arguments
case "${1:-sync}" in
    "sync"|"pull")
        main
        ;;
    "test")
        info "Testing SSH connection only..."
        setup_ssh_key
        test_ssh_connection
        ;;
    "list")
        info "Listing remote backups..."
        setup_ssh_key
        list_remote_backups
        ;;
    "stats")
        info "Showing local backup statistics..."
        setup_local_directory
        show_backup_stats
        ;;
    *)
        echo "Self-Contained NAS Backup Client"
        echo ""
        echo "Usage: $0 {sync|test|list|stats}"
        echo ""
        echo "Commands:"
        echo "  sync  - Sync backups from primary server (default)"
        echo "  test  - Test SSH connection to primary server"
        echo "  list  - List backups available on primary server"
        echo "  stats - Show local backup statistics"
        echo ""
        echo "Configuration:"
        echo "  Primary server: $PRIMARY_SERVER_IP"
        echo "  Local backup path: $LOCAL_BACKUP_PATH"
        echo "  Retention: $RETENTION_DAYS days"
        exit 1
        ;;
esac
EOF

    # Replace placeholders with actual values
    sed -i "s/__PRIMARY_SERVER_IP__/$PRIMARY_SERVER_IP/g" "$OUTPUT_SCRIPT"
    sed -i "s/__SSH_PRIVATE_KEY_B64__/$SSH_PRIVATE_KEY/g" "$OUTPUT_SCRIPT"
    
    # Make executable
    chmod +x "$OUTPUT_SCRIPT"
    
    # Copy to current directory if possible (for convenience)
    local final_script="./nas-backup-client.sh"
    if cp "$OUTPUT_SCRIPT" "$final_script" 2>/dev/null; then
        chmod +x "$final_script"
        success "Self-contained NAS backup script generated: $final_script"
        OUTPUT_SCRIPT="$final_script"  # Update for usage instructions
    else
        warn "Could not copy to current directory, script available at: $OUTPUT_SCRIPT"
    fi
    
    echo
    echo "============================================================"
    echo "📋 Usage Instructions"
    echo "============================================================"
    echo
    
    info "The generated script is completely self-contained:"
    echo "  ✅ Contains embedded SSH private key"
    echo "  ✅ No additional setup required on remote machine"
    echo "  ✅ No portainer user needed on NAS"
    echo "  ✅ Configurable backup path in script header"
    echo
    
    info "Copy $OUTPUT_SCRIPT to your NAS and run:"
    echo "  # Test connection:"
    echo "  ./$OUTPUT_SCRIPT test"
    echo
    echo "  # List available backups:"
    echo "  ./$OUTPUT_SCRIPT list"
    echo
    echo "  # Sync backups:"
    echo "  ./$OUTPUT_SCRIPT sync"
    echo
    echo "  # Show statistics:"
    echo "  ./$OUTPUT_SCRIPT stats"
    echo
    
    info "To customize for your NAS:"
    echo "  1. Edit LOCAL_BACKUP_PATH in the script (currently: /volume1/backup/zuptalo)"
    echo "  2. Adjust RETENTION_DAYS if needed (currently: 30)"
    echo "  3. Schedule with cron or DSM Task Scheduler"
    echo
    
    success "Setup complete! Your NAS backup client is ready."
}

# Check internet connectivity to GitHub
check_internet_connectivity() {
    info "Checking internet connectivity to GitHub..."
    
    # Try multiple methods to check connectivity
    if command -v curl >/dev/null 2>&1; then
        if curl -s --max-time 10 -o /dev/null https://github.com 2>/dev/null; then
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --timeout=10 -O /dev/null https://github.com 2>/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

# Get latest version from GitHub
get_latest_version() {
    local latest_version=""
    
    # Try to get latest release from GitHub API
    if command -v curl >/dev/null 2>&1; then
        latest_version=$(curl -s --max-time 10 https://api.github.com/repos/zuptalo/docker-stack-backup/releases/latest 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
    elif command -v wget >/dev/null 2>&1; then
        latest_version=$(wget -q --timeout=10 -O - https://api.github.com/repos/zuptalo/docker-stack-backup/releases/latest 2>/dev/null | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
    fi
    
    # If API fails, try to get from raw GitHub file
    if [[ -z "$latest_version" ]]; then
        if command -v curl >/dev/null 2>&1; then
            latest_version=$(curl -s --max-time 10 https://raw.githubusercontent.com/zuptalo/docker-stack-backup/main/backup-manager.sh 2>/dev/null | grep '^VERSION=' | head -1 | cut -d'"' -f2)
        elif command -v wget >/dev/null 2>&1; then
            latest_version=$(wget -q --timeout=10 -O - https://raw.githubusercontent.com/zuptalo/docker-stack-backup/main/backup-manager.sh 2>/dev/null | grep '^VERSION=' | head -1 | cut -d'"' -f2)
        fi
    fi
    
    # Clean up version string
    latest_version=$(echo "$latest_version" | tr -d 'v ')
    
    echo "$latest_version"
}

# Compare date-based version strings (YYYY.MM.DD format)
compare_versions() {
    local version1="$1"
    local version2="$2"
    
    # Simple string comparison for now to isolate the issue
    if [[ "$version1" == "$version2" ]]; then
        return 0  # versions are equal
    elif [[ "$version1" < "$version2" ]]; then
        return 2  # version1 < version2 (update available)
    else
        return 1  # version1 > version2 (newer than latest)
    fi
}

# Backup current version
backup_current_version() {
    local script_path="$1"
    local backup_dir="/tmp/docker-backup-manager-backup"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="$backup_dir/backup-manager-${VERSION}-${timestamp}.sh"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Copy current script
    if cp "$script_path" "$backup_file"; then
        success "Current version backed up to: $backup_file"
        return 0
    else
        error "Failed to backup current version"
        return 1
    fi
}

# Download latest version
download_latest_version() {
    local temp_file="/tmp/backup-manager-latest.sh"
    
    info "Downloading latest version..." >&2
    
    # Try to download from GitHub
    if command -v curl >/dev/null 2>&1; then
        if curl -s --max-time 30 -o "$temp_file" https://raw.githubusercontent.com/zuptalo/docker-stack-backup/main/backup-manager.sh 2>/dev/null; then
            echo "$temp_file"
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --timeout=30 -O "$temp_file" https://raw.githubusercontent.com/zuptalo/docker-stack-backup/main/backup-manager.sh 2>/dev/null; then
            echo "$temp_file"
            return 0
        fi
    fi
    
    error "Failed to download latest version"
    return 1
}

# Update script file
update_script_file() {
    local source_file="$1"
    local target_file="$2"
    local script_type="$3"
    
    # Check if source file exists and is readable
    if [[ ! -f "$source_file" ]]; then
        error "Source file $source_file not found"
        return 1
    fi
    
    if [[ ! -r "$source_file" ]]; then
        error "Cannot read source file $source_file"
        return 1
    fi
    
    # Check file size (should not be empty or too small)
    local file_size
    file_size=$(stat -c%s "$source_file" 2>/dev/null || stat -f%z "$source_file" 2>/dev/null || echo "0")
    if [[ "$file_size" -lt 1000 ]]; then
        error "Downloaded file is too small ($file_size bytes) - likely incomplete"
        if [[ "$file_size" -gt 0 ]]; then
            warn "File content preview:"
            head -10 "$source_file" || true
        fi
        return 1
    fi
    
    # Verify downloaded file is valid bash syntax
    local syntax_check_output
    syntax_check_output=$(bash -n "$source_file" 2>&1)
    if [[ $? -ne 0 ]]; then
        error "Downloaded $script_type script has syntax errors:"
        error "$syntax_check_output"
        if [[ -f "$source_file" ]]; then
            warn "File preview (first 20 lines):"
            head -20 "$source_file" || true
            warn "File preview (last 10 lines):"
            tail -10 "$source_file" || true
        fi
        return 1
    fi
    
    # Backup current version
    if ! backup_current_version "$target_file"; then
        return 1
    fi
    
    # Update the script
    if cp "$source_file" "$target_file"; then
        chmod +x "$target_file"
        success "Updated $script_type script: $target_file"
        return 0
    else
        error "Failed to update $script_type script"
        return 1
    fi
}

# Main update function
update_script() {
    info "Docker Stack Backup - Update Manager"
    info "===================================="
    echo
    
    # Check internet connectivity
    if ! check_internet_connectivity; then
        error "No internet connectivity to GitHub"
        error "Please check your internet connection and try again"
        return 1
    fi
    
    success "Internet connectivity verified"
    
    # Get latest version
    info "Checking for latest version..."
    local latest_version=$(get_latest_version)
    
    if [[ -z "$latest_version" ]]; then
        error "Could not determine latest version"
        error "Please check GitHub repository or try again later"
        return 1
    fi
    
    info "Current version: $VERSION"
    info "Latest version: $latest_version"
    
    # Simple version comparison
    if [[ "$VERSION" == "$latest_version" ]]; then
        success "You are already running the latest version ($VERSION)"
        return 0
    elif [[ "$VERSION" > "$latest_version" ]]; then
        warn "You are running a newer version ($VERSION) than the latest release ($latest_version)"
        if [[ "${AUTO_YES:-false}" != "true" ]]; then
            read -p "Continue with update anyway? [y/N]: " continue_update
            if [[ ! "$continue_update" =~ ^[Yy]$ ]]; then
                info "Update cancelled"
                return 0
            fi
        fi
    else
        info "Update available: $VERSION → $latest_version"
    fi
    
    
    # Download latest version
    local temp_file
    if ! temp_file=$(download_latest_version); then
        return 1
    fi
    
    success "Latest version downloaded"
    
    # Check if system script exists to determine available options
    local system_script_exists=false
    if [[ -f "/opt/backup/backup-manager.sh" ]]; then
        system_script_exists=true
    fi
    
    # Ask user what to update (or auto-select if --yes flag is set)
    local update_choice
    if [[ "${AUTO_YES:-false}" == "true" ]]; then
        if [[ "$system_script_exists" == "true" ]]; then
            update_choice="3"
            info "Auto-selecting option 3: Both scripts (recommended)"
        else
            update_choice="1"
            info "Auto-selecting option 1: Current script only (system script not installed yet)"
        fi
    else
        echo
        if [[ "$system_script_exists" == "true" ]]; then
            echo "Select what to update:"
            echo "1) Current script only ($(realpath "$0"))"
            echo "2) System script only (/opt/backup/backup-manager.sh)"
            echo "3) Both scripts (recommended)"
            echo "4) Cancel update"
            echo
            read -p "Select option [1-4]: " update_choice
        else
            echo "System script not found. Only current script can be updated."
            echo "Run 'setup' first to install the system script for full functionality."
            echo
            echo "Available options:"
            echo "1) Update current script only ($(realpath "$0"))"
            echo "2) Cancel update"
            echo
            read -p "Select option [1-2]: " temp_choice
            case "$temp_choice" in
                1) update_choice="1" ;;
                2) update_choice="4" ;;
                *) update_choice="4" ;;
            esac
        fi
    fi
    
    case "$update_choice" in
        1)
            if update_script_file "$temp_file" "$0" "current"; then
                success "Current script updated successfully"
            else
                error "Failed to update current script"
                rm -f "$temp_file"
                return 1
            fi
            ;;
        2)
            if [[ -f "/opt/backup/backup-manager.sh" ]]; then
                if update_script_file "$temp_file" "/opt/backup/backup-manager.sh" "system"; then
                    success "System script updated successfully"
                else
                    error "Failed to update system script"
                    rm -f "$temp_file"
                    return 1
                fi
            else
                warn "System script not found at /opt/backup/backup-manager.sh"
                warn "Run setup first to install system script"
                rm -f "$temp_file"
                return 1
            fi
            ;;
        3)
            local current_success=true
            local system_success=true
            
            # Update current script
            if ! update_script_file "$temp_file" "$0" "current"; then
                current_success=false
            fi
            
            # Update system script
            if [[ -f "/opt/backup/backup-manager.sh" ]]; then
                if ! update_script_file "$temp_file" "/opt/backup/backup-manager.sh" "system"; then
                    system_success=false
                fi
            else
                warn "System script not found at /opt/backup/backup-manager.sh"
                warn "Only current script was updated"
            fi
            
            if $current_success && $system_success; then
                success "Both scripts updated successfully"
            elif $current_success; then
                warn "Current script updated, but system script update failed"
            elif $system_success; then
                warn "System script updated, but current script update failed"
            else
                error "Failed to update both scripts"
                rm -f "$temp_file"
                return 1
            fi
            ;;
        4)
            info "Update cancelled"
            rm -f "$temp_file"
            return 0
            ;;
        *)
            error "Invalid option"
            rm -f "$temp_file"
            return 1
            ;;
    esac
    
    # Clean up
    rm -f "$temp_file"
    
    echo
    success "Update completed successfully!"
    info "Restart any running processes to use the updated version"
    
    return 0
}

# Uninstall system - complete cleanup with double confirmation
uninstall_system() {
    printf "%b\n" "${RED}⚠️  DESTRUCTIVE OPERATION WARNING${NC}"
    echo "════════════════════════════════════════════════════════════════"
    echo
    printf "%b\n" "${YELLOW}This command will completely remove:${NC}"
    echo "  • All Docker containers (Portainer, nginx-proxy-manager, user stacks)"
    echo "  • All Docker images, volumes, and networks"
    echo "  • All configuration files in /opt/portainer and /opt/tools"
    echo "  • All backup data in /opt/backup (unless you choose to keep it)"
    echo "  • Docker system will be completely cleaned"
    echo
    printf "%b\n" "${RED}⚠️  This action CANNOT be undone!${NC}"
    echo
    
    # First confirmation
    if ! prompt_yes_no "Are you absolutely sure you want to completely uninstall the system?" "n"; then
        info "Uninstall cancelled by user"
        return 0
    fi
    
    echo
    printf "%b\n" "${RED}⚠️  FINAL WARNING: This will destroy ALL data!${NC}"
    printf "%b\n" "${YELLOW}Type 'YES I UNDERSTAND' to proceed (case sensitive):${NC}"
    
    local confirmation
    if [[ "${NON_INTERACTIVE:-false}" == "true" ]] || [[ "${AUTO_YES:-false}" == "true" ]]; then
        confirmation="YES I UNDERSTAND"
        info "Non-interactive mode: proceeding with uninstall"
    else
        read -r confirmation
    fi
    
    if [[ "$confirmation" != "YES I UNDERSTAND" ]]; then
        info "Uninstall cancelled - confirmation phrase not matched"
        return 0
    fi
    
    echo
    warn "Starting complete system uninstall in 5 seconds..."
    if ! is_test_environment; then
        sleep 5
    fi
    
    info "Beginning system uninstall..."
    echo
    
    # Step 1: Stop and remove all containers
    info "Step 1/6: Stopping all Docker containers..."
    if docker ps -q | xargs -r docker stop; then
        success "All containers stopped"
    else
        warn "Some containers may have already been stopped"
    fi
    
    info "Removing all Docker containers..."
    if docker ps -aq | xargs -r docker rm -f; then
        success "All containers removed"
    else
        warn "No containers to remove or some removal failed"
    fi
    
    # Step 2: Remove Docker networks (except defaults)
    info "Step 2/6: Cleaning up Docker networks..."
    # Remove prod-network specifically
    if docker network inspect prod-network >/dev/null 2>&1; then
        docker network rm prod-network && success "Removed prod-network"
    fi
    # Remove other custom networks
    docker network ls --filter type=custom -q | xargs -r docker network rm && success "Custom networks cleaned"
    
    # Step 3: Remove Docker images, volumes, and system cleanup
    info "Step 3/6: Performing complete Docker system cleanup..."
    docker system prune -af --volumes && success "Docker system completely cleaned"
    
    # Step 4: Remove configuration directories
    info "Step 4/6: Removing configuration directories..."
    
    if [[ -d "/opt/portainer" ]]; then
        sudo rm -rf /opt/portainer && success "Removed /opt/portainer"
    else
        info "/opt/portainer directory not found"
    fi
    
    if [[ -d "/opt/tools" ]]; then
        sudo rm -rf /opt/tools && success "Removed /opt/tools"
    else
        info "/opt/tools directory not found"
    fi
    
    # Step 5: Handle backup directory (optional)
    info "Step 5/6: Handling backup data..."
    if [[ -d "/opt/backup" ]]; then
        if prompt_yes_no "Do you want to keep backup data in /opt/backup?" "y"; then
            info "Backup data preserved in /opt/backup"
        else
            sudo rm -rf /opt/backup && success "Removed /opt/backup"
        fi
    else
        info "/opt/backup directory not found"
    fi
    
    # Step 6: Remove configuration files
    info "Step 6/6: Removing configuration files..."
    if [[ -f "/etc/docker-backup-manager.conf" ]]; then
        sudo rm -f /etc/docker-backup-manager.conf && success "Removed /etc/docker-backup-manager.conf"
    else
        info "Configuration file not found"
    fi
    
    # Remove cron jobs
    if command -v crontab >/dev/null 2>&1; then
        if sudo -u portainer crontab -l 2>/dev/null | grep -q "docker-backup-manager"; then
            sudo -u portainer crontab -r 2>/dev/null && success "Removed portainer user cron jobs"
        fi
        if crontab -l 2>/dev/null | grep -q "docker-backup-manager"; then
            warn "Found backup-manager cron jobs for current user - you may want to remove them manually"
        fi
    fi
    
    echo
    printf "%b\n" "${GREEN}✅ System uninstall completed successfully!${NC}"
    echo "════════════════════════════════════════════════════════════════"
    echo
    printf "%b\n" "${BLUE}💡 Next steps:${NC}"
    echo "  • Docker is still installed and ready for fresh setup"
    echo "  • Run './backup-manager.sh setup' to reinstall the system"
    echo "  • The 'portainer' system user is still available for reuse"
    echo
    if [[ -d "/opt/backup" ]]; then
        info "Backup data was preserved and will be available after reinstall"
    fi
    
    success "System is ready for fresh installation"
}

# Show usage information
usage() {
    printf "%b" "$(cat << EOF
Docker Backup Manager v${VERSION}

Usage: $0 [FLAGS] {setup|config|backup|restore|schedule|generate-nas-script|update|uninstall}

${BLUE}═══ FLAGS ═══${NC}
    ${BLUE}--yes, -y${NC}               # Auto-answer 'yes' to all prompts
    ${BLUE}--non-interactive, -n${NC}   # Run in non-interactive mode (use defaults)
    ${BLUE}--quiet, -q${NC}             # Minimize output
    ${BLUE}--config-file=PATH${NC}      # Load configuration from file
    ${BLUE}--timeout=SECONDS${NC}       # Set prompt timeout (default: 60)
    ${BLUE}--help, -h${NC}              # Show this help message

${BLUE}═══ WORKFLOW COMMANDS (in recommended order) ═══${NC}
    ${BLUE}setup${NC}               - 🚀 Initial setup (install Docker, create user, deploy services)
    ${BLUE}config${NC}              - ⚙️  Interactive configuration (modify settings)
    
    ${BLUE}backup${NC}              - 💾 Create backup of all data
    ${BLUE}restore${NC}             - 🔄 Restore from backup (interactive selection)
    ${BLUE}schedule${NC}            - ⏰ Setup automated backups
    ${BLUE}generate-nas-script${NC} - 📡 Generate self-contained NAS backup script
    
    ${BLUE}update${NC}              - 🔄 Update script to latest version from GitHub
    ${BLUE}uninstall${NC}           - 🗑️  Complete system cleanup (destructive operation)

${BLUE}═══ GETTING STARTED ═══${NC}
    ${BLUE}$0 setup${NC}               # 🚀 First-time setup (run this first!)
    ${BLUE}$0 config${NC}              # ⚙️  Configure or reconfigure settings
    
${BLUE}═══ DAILY OPERATIONS ═══${NC}
    ${BLUE}$0 backup${NC}              # 💾 Create backup now
    ${BLUE}$0 restore${NC}             # 🔄 Choose and restore backup
    ${BLUE}$0 schedule${NC}            # ⏰ Setup cron job for backups
    
${BLUE}═══ ADVANCED FEATURES ═══${NC}
    ${BLUE}$0 generate-nas-script${NC} # 📡 Create NAS backup client script
    ${BLUE}$0 update${NC}              # 🔄 Update to latest version

${BLUE}═══ NON-INTERACTIVE USAGE ═══${NC}
    ${BLUE}$0 --non-interactive --yes setup${NC}
    ${BLUE}$0 --config-file=/path/to/config.conf setup${NC}

    ${YELLOW}Example config file (/etc/docker-backup-manager.conf):${NC}
    ${GREEN}DOMAIN_NAME="example.com"${NC}
    ${GREEN}PORTAINER_SUBDOMAIN="pt"${NC}
    ${GREEN}NPM_SUBDOMAIN="npm"${NC}
    ${GREEN}PORTAINER_PATH="/opt/portainer"${NC}
    ${GREEN}TOOLS_PATH="/opt/tools"${NC}
    ${GREEN}BACKUP_PATH="/opt/backup"${NC}
    ${GREEN}BACKUP_RETENTION=7${NC}

${YELLOW}💡 Note: Run 'setup' first if this is a new installation${NC}

EOF
)"
}


# Command-specific help function
show_command_help() {
    local command="$1"
    
    case "$command" in
        setup)
            printf "%b" "$(cat << EOF
Docker Backup Manager v${VERSION} - Setup Command Help

${BLUE}COMMAND:${NC} setup
${BLUE}PURPOSE:${NC} Complete initial setup of Docker Stack Backup Manager

${BLUE}DESCRIPTION:${NC}
This command performs a complete setup of your Docker environment with:
- Docker and Docker Compose installation
- Portainer container management platform deployment
- nginx-proxy-manager reverse proxy with SSL automation
- System user creation with SSH key management
- Network and directory structure setup

${BLUE}USAGE:${NC}
    $0 [FLAGS] setup
    
${BLUE}EXAMPLES:${NC}
    $0 setup                           # Interactive setup
    $0 --yes setup                     # Auto-confirm all prompts
    $0 --config-file=/path/config setup   # Use configuration file
    $0 --non-interactive --yes setup  # Fully automated setup

${BLUE}REQUIREMENTS:${NC}
    • Ubuntu 24.04 LTS (recommended) or compatible Linux distribution
    • User with sudo privileges
    • Internet connection for package downloads
    • Domain name pointing to server IP (for SSL certificates)
    
${BLUE}TROUBLESHOOTING:${NC}
    ${YELLOW}❌ "Docker installation failed"${NC}
        → Check internet connection
        → Verify Ubuntu version compatibility: lsb_release -a
        → Try: sudo apt update && sudo apt upgrade
        
    ${YELLOW}❌ "SSL certificate creation failed"${NC}
        → Verify domain DNS points to server IP: dig yourdomain.com
        → Check ports 80, 443 are accessible
        → Use --skip-ssl for HTTP-only setup during testing
        
    ${YELLOW}❌ "Portainer deployment failed"${NC}
        → Check Docker daemon: sudo systemctl status docker
        → Verify available disk space: df -h
        → Check for port conflicts: sudo netstat -tulpn | grep :9000

${YELLOW}💡 TIP: Setup creates configuration file at /etc/docker-backup-manager.conf${NC}

EOF
)"
            ;;
        backup)
            printf "%b" "$(cat << EOF
Docker Backup Manager v${VERSION} - Backup Command Help

${BLUE}COMMAND:${NC} backup
${BLUE}PURPOSE:${NC} Create comprehensive backup of Docker environment

${BLUE}DESCRIPTION:${NC}
Creates a complete backup including:
- All container data and volumes
- Portainer stack configurations with environment variables
- nginx-proxy-manager settings and SSL certificates
- File permissions and ownership preservation
- System metadata for reliable restoration

${BLUE}USAGE:${NC}
    $0 [FLAGS] backup
    
${BLUE}EXAMPLES:${NC}
    $0 backup                     # Interactive backup with prompts
    $0 --quiet backup             # Minimal output
    $0 --yes backup               # Auto-confirm backup creation

${BLUE}BACKUP PROCESS:${NC}
    1. Capture running stack states via Portainer API
    2. Gracefully stop containers (except Portainer)
    3. Create compressed archive with preserved permissions
    4. Restart services in proper order
    5. Clean up old backups per retention policy
    
${BLUE}BACKUP LOCATION:${NC}
    • Default: /opt/backup/
    • Format: docker_backup_YYYYMMDD_HHMMSS.tar.gz
    • Retention: 7 days (configurable)
    
${BLUE}TROUBLESHOOTING:${NC}
    ${YELLOW}❌ "Insufficient disk space"${NC}
        → Check available space: df -h /opt/backup
        → Clean old backups manually or adjust retention
        → Consider external backup location
        
    ${YELLOW}❌ "Portainer API authentication failed"${NC}
        → Verify Portainer is running: docker ps | grep portainer
        → Check credentials file: /opt/portainer/.credentials
        → Try: $0 config (to reconfigure)
        
    ${YELLOW}❌ "Container stop timeout"${NC}
        → Some containers may be unresponsive
        → Check docker logs for specific containers
        → Backup will continue but may have inconsistent data

${YELLOW}💡 TIP: Backups are created with enhanced metadata for reliable restoration${NC}

EOF
)"
            ;;
        restore)
            printf "%b" "$(cat << EOF
Docker Backup Manager v${VERSION} - Restore Command Help

${BLUE}COMMAND:${NC} restore
${BLUE}PURPOSE:${NC} Restore Docker environment from backup

${BLUE}DESCRIPTION:${NC}
Interactively restore your Docker environment from available backups:
- Select from available backup archives
- Restore all container data and configurations
- Recreate Portainer stacks with original settings
- Preserve file permissions and ownership
- Restart services in proper dependency order

${BLUE}USAGE:${NC}
    $0 [FLAGS] restore
    
${BLUE}EXAMPLES:${NC}
    $0 restore                    # Interactive restore with backup selection
    $0 --yes restore              # Auto-confirm restore prompts

${BLUE}RESTORE PROCESS:${NC}
    1. Display available backups for selection
    2. Create safety backup of current state
    3. Gracefully stop all containers
    4. Extract backup data with preserved permissions
    5. Restart services and restore stack states
    6. Validate service accessibility
    
${BLUE}BACKUP SELECTION:${NC}
    • Lists all available backup files with timestamps
    • Shows backup size and creation date
    • Allows selection by number or filename
    • Displays architecture compatibility warnings
    
${BLUE}TROUBLESHOOTING:${NC}
    ${YELLOW}❌ "No backups found"${NC}
        → Check backup directory: ls -la /opt/backup/
        → Verify backup path in config: $0 config
        → Create backup first: $0 backup
        
    ${YELLOW}❌ "Permission denied during restore"${NC}
        → Ensure running with proper user privileges
        → Check backup directory permissions
        → Try: sudo $0 restore (if needed)
        
    ${YELLOW}❌ "Services failed to start after restore"${NC}
        → Check Docker daemon: sudo systemctl status docker
        → Verify container logs: docker logs <container-name>
        → Try manual restart: $0 config
        
    ${YELLOW}❌ "Architecture mismatch warning"${NC}
        → Backup was created on different CPU architecture
        → Docker images may need to be rebuilt
        → Some containers may fail to start

${YELLOW}💡 TIP: Restore automatically creates safety backup before proceeding${NC}

EOF
)"
            ;;
        schedule)
            printf "%b" "$(cat << EOF
Docker Backup Manager v${VERSION} - Schedule Command Help

${BLUE}COMMAND:${NC} schedule
${BLUE}PURPOSE:${NC} Setup automated backup scheduling using cron

${BLUE}DESCRIPTION:${NC}
Configures automated backups to run at specified intervals:
- Multiple predefined schedules (daily, weekly, etc.)
- Custom cron expression support
- Automatic cleanup of old backups
- Email notifications (if configured)
- Logging of all backup operations

${BLUE}USAGE:${NC}
    $0 [FLAGS] schedule
    
${BLUE}EXAMPLES:${NC}
    $0 schedule                   # Interactive schedule setup
    $0 --yes schedule             # Use default daily backup schedule

${BLUE}SCHEDULE OPTIONS:${NC}
    1. Daily at 2:00 AM
    2. Weekly on Sundays at 3:00 AM  
    3. Twice daily (6:00 AM, 6:00 PM)
    4. Every 6 hours
    5. Custom cron expression
    
${BLUE}CUSTOM CRON EXAMPLES:${NC}
    • 0 2 * * *        → Daily at 2:00 AM
    • 0 3 * * 0        → Weekly on Sunday at 3:00 AM
    • 0 */6 * * *      → Every 6 hours
    • 30 1 */3 * *     → Every 3 days at 1:30 AM
    • 0 9-17 * * 1-5   → Hourly during business hours (9-5, Mon-Fri)
    
${BLUE}BACKUP RETENTION:${NC}
    • Local backups: 7 days (default, configurable)
    • Automatic cleanup of expired backups
    • Size-based retention options
    
${BLUE}TROUBLESHOOTING:${NC}
    ${YELLOW}❌ "crontab: command not found"${NC}
        → Install cron package: sudo apt install cron
        → Start cron service: sudo systemctl enable --now cron
        → Verify: sudo systemctl status cron
        
    ${YELLOW}❌ "Permission denied for cron"${NC}
        → Check user permissions: ls -la /etc/cron.allow
        → Verify cron access: crontab -l
        → May need to run as portainer user
        
    ${YELLOW}❌ "Scheduled backups not running"${NC}
        → Check cron logs: sudo tail -f /var/log/cron
        → Verify cron entry: sudo -u portainer crontab -l
        → Test backup manually: $0 backup
        
    ${YELLOW}❌ "Invalid cron expression"${NC}
        → Use standard cron format: minute hour day month weekday
        → Test expression: https://crontab.guru/
        → Each field: * = any, number = specific, */n = every n

${YELLOW}💡 TIP: Scheduled backups run as portainer user and log to /var/log/docker-backup-manager.log${NC}

EOF
)"
            ;;
        config)
            printf "%b" "$(cat << EOF
Docker Backup Manager v${VERSION} - Config Command Help

${BLUE}COMMAND:${NC} config
${BLUE}PURPOSE:${NC} Interactive configuration management

${BLUE}DESCRIPTION:${NC}
Manage Docker Backup Manager configuration:
- Modify domain and subdomain settings
- Change backup paths and retention policies
- Update service configurations
- Repair SSH keys for NAS backup functionality
- Migrate data to new paths

${BLUE}USAGE:${NC}
    $0 [FLAGS] config
    
${BLUE}EXAMPLES:${NC}
    $0 config                     # Interactive configuration
    $0 --config-file=/path config # Load from specific config file

${BLUE}CONFIGURATION OPTIONS:${NC}
    • Domain and subdomain settings
    • Directory paths (Portainer, tools, backups)
    • Backup retention policies
    • SSL certificate preferences
    • NAS backup settings
    
${BLUE}PATH MIGRATION:${NC}
    If changing paths with existing stacks:
    1. Automatically detects existing stacks
    2. Creates pre-migration backup
    3. Stops services gracefully
    4. Moves data to new locations
    5. Updates configurations
    6. Validates service restart
    
${BLUE}SSH KEY MANAGEMENT:${NC}
    • Automatically validates SSH setup
    • Repairs keys if validation fails
    • Required for NAS backup functionality
    • Uses Ed25519 keys for security
    
${BLUE}TROUBLESHOOTING:${NC}
    ${YELLOW}❌ "Configuration file not found"${NC}
        → Run setup first: $0 setup
        → Check file exists: ls -la /etc/docker-backup-manager.conf
        → Create manually or re-run setup
        
    ${YELLOW}❌ "Path migration failed"${NC}
        → Ensure sufficient disk space on destination
        → Check directory permissions
        → Review backup created before migration
        → Rollback if necessary: $0 restore
        
    ${YELLOW}❌ "SSH key validation failed"${NC}
        → Allow repair when prompted
        → Check SSH directory permissions: ls -la ~/.ssh/
        → Verify key files: ls -la /home/portainer/.ssh/
        
    ${YELLOW}❌ "Service restart failed after config"${NC}
        → Check Docker daemon: sudo systemctl status docker
        → Verify new paths are accessible
        → Review container logs: docker logs <container>
        → Consider rollback: $0 restore

${YELLOW}💡 TIP: Config changes are backed up automatically before applying${NC}

EOF
)"
            ;;
        generate-nas-script)
            printf "%b" "$(cat << EOF
Docker Backup Manager v${VERSION} - Generate NAS Script Help

${BLUE}COMMAND:${NC} generate-nas-script
${BLUE}PURPOSE:${NC} Generate self-contained NAS backup client script

${BLUE}DESCRIPTION:${NC}
Creates a standalone script for NAS or remote servers:
- Self-contained with embedded SSH keys
- No setup required on remote machine
- Configurable backup paths and retention
- Automatic synchronization with primary server
- Built-in testing and validation

${BLUE}USAGE:${NC}
    $0 [FLAGS] generate-nas-script
    
${BLUE}EXAMPLES:${NC}
    $0 generate-nas-script        # Interactive NAS script generation
    $0 --yes generate-nas-script  # Auto-confirm generation

${BLUE}GENERATED SCRIPT FEATURES:${NC}
    • nas-backup-client.sh - Complete standalone script
    • Embedded SSH private key (no separate key files)
    • Configurable LOCAL_BACKUP_PATH in script header
    • Built-in commands: test, list, sync, stats
    • Retention management for local and remote backups
    
${BLUE}NAS SCRIPT COMMANDS:${NC}
    ./nas-backup-client.sh test   # Test SSH connection
    ./nas-backup-client.sh list   # List available backups
    ./nas-backup-client.sh sync   # Sync backups from primary
    ./nas-backup-client.sh stats  # Show backup statistics
    
${BLUE}DEPLOYMENT:${NC}
    1. Copy generated script to your NAS/remote server
    2. Edit LOCAL_BACKUP_PATH in script header if needed
    3. Make executable: chmod +x nas-backup-client.sh
    4. Test connection: ./nas-backup-client.sh test
    5. Schedule with cron: ./nas-backup-client.sh sync
    
${BLUE}TROUBLESHOOTING:${NC}
    ${YELLOW}❌ "SSH key generation failed"${NC}
        → Check SSH directory: ls -la /home/portainer/.ssh/
        → Repair SSH setup: $0 config
        → Verify portainer user exists
        
    ${YELLOW}❌ "Cannot connect to primary server"${NC}
        → Verify primary server SSH access
        → Check firewall settings
        → Test from NAS: ./nas-backup-client.sh test
        
    ${YELLOW}❌ "Permission denied on NAS"${NC}
        → Make script executable: chmod +x nas-backup-client.sh
        → Check backup directory permissions
        → Create directory: mkdir -p /volume1/backup/docker-backups
        
    ${YELLOW}❌ "Backup sync failed"${NC}
        → Check network connectivity
        → Verify primary server backup path
        → Review SSH key permissions on primary
        → Check disk space on NAS: df -h

${BLUE}SYNOLOGY NAS INTEGRATION:${NC}
    1. Upload script via File Station or SSH
    2. Set LOCAL_BACKUP_PATH=/volume1/backup/docker-backups
    3. Schedule via Control Panel > Task Scheduler
    4. Create task: ./nas-backup-client.sh sync
    5. Set appropriate schedule (daily/weekly)

${YELLOW}💡 TIP: Generated script is completely self-contained - no dependencies on primary server${NC}

EOF
)"
            ;;
        update)
            printf "%b" "$(cat << EOF
Docker Backup Manager v${VERSION} - Update Command Help

${BLUE}COMMAND:${NC} update
${BLUE}PURPOSE:${NC} Update script to latest version from GitHub

${BLUE}DESCRIPTION:${NC}
Automatically updates Docker Backup Manager to the latest version:
- Downloads latest release from GitHub
- Backs up current version before updating
- Verifies download integrity
- Updates both user script and system script
- Preserves existing configuration

${BLUE}USAGE:${NC}
    $0 [FLAGS] update
    
${BLUE}EXAMPLES:${NC}
    $0 update                     # Interactive update with prompts
    $0 --yes update               # Auto-confirm update

${BLUE}UPDATE PROCESS:${NC}
    1. Check internet connectivity to GitHub
    2. Compare current vs latest version
    3. Backup current version
    4. Download and verify new version
    5. Update user script and system script
    6. Preserve configuration files
    
${BLUE}UPDATE OPTIONS:${NC}
    • User script only (/path/to/backup-manager.sh)
    • System script only (/opt/backup/backup-manager.sh)
    • Both locations (recommended)
    
${BLUE}VERSION INFORMATION:${NC}
    • Current version: ${VERSION}
    • Latest version: Checked from GitHub releases
    • Automatic version comparison
    • Backup of previous version available
    
${BLUE}TROUBLESHOOTING:${NC}
    ${YELLOW}❌ "No internet connection"${NC}
        → Check connectivity: ping github.com
        → Verify DNS resolution: nslookup github.com
        → Check firewall/proxy settings
        
    ${YELLOW}❌ "GitHub API rate limit exceeded"${NC}
        → Wait 60 minutes for rate limit reset
        → Use authenticated requests if available
        → Try again later
        
    ${YELLOW}❌ "Download verification failed"${NC}
        → Corrupted download detected
        → Check network stability
        → Try update again
        → May indicate network interference
        
    ${YELLOW}❌ "Permission denied updating system script"${NC}
        → System script requires elevated privileges
        → Check sudo access
        → Verify /opt/backup/ directory permissions
        
    ${YELLOW}❌ "Backup of current version failed"${NC}
        → Check available disk space
        → Verify write permissions in backup directory
        → May continue without backup (not recommended)

${BLUE}ROLLBACK:${NC}
    If update causes issues, restore from backup:
    • Backup location: /opt/backup/backup-manager-{version}-{timestamp}.sh
    • Copy backup over current script
    • Restore both user and system scripts

${YELLOW}💡 TIP: Always test updated script in development before production use${NC}

EOF
)"
            ;;
        uninstall)
            printf "%b" "$(cat << EOF
Docker Backup Manager v${VERSION} - Uninstall Command Help

${BLUE}COMMAND:${NC} uninstall
${BLUE}PURPOSE:${NC} Complete system cleanup and removal

${RED}⚠️  WARNING: This is a destructive operation that cannot be undone!${NC}

${BLUE}DESCRIPTION:${NC}
Completely removes Docker Backup Manager and ALL data:
- Stops and removes all containers
- Removes all Docker images and volumes
- Deletes all configuration files
- Removes system directories (/opt/portainer, /opt/tools, /opt/backup)
- Cleans up Docker networks and system

${BLUE}USAGE:${NC}
    $0 [FLAGS] uninstall
    
${BLUE}EXAMPLES:${NC}
    $0 uninstall                  # Interactive with double confirmation
    $0 --yes uninstall            # Still requires double confirmation

${BLUE}UNINSTALL PROCESS:${NC}
    1. ${RED}DOUBLE CONFIRMATION${NC} - Two separate confirmations required
    2. Stop all running containers
    3. Remove all containers and images
    4. Clean Docker system (volumes, networks, cache)
    5. Remove system directories and files
    6. Remove configuration files
    7. Clean up cron jobs and logs
    
${BLUE}WHAT GETS REMOVED:${NC}
    • All Docker containers and images
    • All Docker volumes and networks
    • /opt/portainer/ directory (Portainer data)
    • /opt/tools/ directory (nginx-proxy-manager, etc.)
    • /opt/backup/ directory (ALL BACKUPS)
    • /etc/docker-backup-manager.conf
    • Cron jobs for scheduled backups
    • Log files
    
${BLUE}WHAT GETS PRESERVED:${NC}
    • Docker installation (only cleaned, not removed)
    • System users (portainer user remains)
    • SSH keys (in /home/portainer/.ssh/)
    • Generated NAS scripts (if copied elsewhere)
    
${BLUE}BEFORE UNINSTALLING:${NC}
    ${YELLOW}📋 RECOMMENDED STEPS:${NC}
    1. Create final backup: $0 backup
    2. Copy important data elsewhere
    3. Export configurations if needed
    4. Document any customizations
    5. Save generated NAS scripts
    
${BLUE}TROUBLESHOOTING:${NC}
    ${YELLOW}❌ "Container stop failed"${NC}
        → Force removal will continue anyway
        → Some containers may be unresponsive
        → Manual cleanup may be needed: docker system prune -af
        
    ${YELLOW}❌ "Directory removal failed"${NC}
        → Check if files are in use
        → Verify permissions
        → May need manual cleanup: sudo rm -rf /opt/portainer
        
    ${YELLOW}❌ "Cron job removal failed"${NC}
        → Check cron permissions
        → Manual removal: crontab -e (remove backup entries)
        → System cron: sudo crontab -u portainer -r
        
${BLUE}POST-UNINSTALL CLEANUP:${NC}
    Manual steps if needed:
    • sudo docker system prune -af --volumes
    • sudo rm -rf /opt/portainer /opt/tools /opt/backup
    • sudo rm -f /etc/docker-backup-manager.conf
    • sudo userdel portainer (if desired)

${RED}⚠️  FINAL WARNING: This removes ALL backups and data permanently!${NC}

EOF
)"
            ;;
        *)
            printf "%b\n" "${RED}Unknown command: $command${NC}"
            printf "Use '$0 --help' to see all available commands\n"
            ;;
    esac
}

# Main function dispatcher
main() {
    # Parse flags first - help should work even as root
    local temp_args=()
    local has_command=false
    
    # First pass: check if we have a command followed by --help
    for arg in "$@"; do
        if [[ "$arg" =~ ^(setup|backup|restore|schedule|config|generate-nas-script|update|uninstall)$ ]]; then
            has_command=true
            break
        fi
    done
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes|--auto-yes|-y)
                AUTO_YES="true"
                shift
                ;;
            --non-interactive|--no-interactive|-n)
                NON_INTERACTIVE="true"
                shift
                ;;
            --quiet|-q)
                QUIET_MODE="true"
                shift
                ;;
            --timeout=*)
                PROMPT_TIMEOUT="${1#*=}"
                shift
                ;;
            --timeout)
                PROMPT_TIMEOUT="$2"
                shift 2
                ;;
            --config-file=*)
                CONFIG_FILE="${1#*=}"
                USER_SPECIFIED_CONFIG_FILE=true
                shift
                ;;
            --config-file)
                CONFIG_FILE="$2"
                USER_SPECIFIED_CONFIG_FILE=true
                shift 2
                ;;
            --help|-h)
                # If we have a command, let command-specific help handle it
                if [[ "$has_command" == "true" ]]; then
                    temp_args+=("$1")
                    shift
                else
                    usage
                    exit 0
                fi
                ;;
            -*)
                error "Unknown flag: $1"
                usage
                exit 1
                ;;
            *)
                # Not a flag, add to remaining arguments
                temp_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Validate config file early if explicitly specified by user
    if [[ "$USER_SPECIFIED_CONFIG_FILE" == "true" && -n "$CONFIG_FILE" ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            error "Configuration file not found: $CONFIG_FILE"
            exit 1
        fi
        
        # Validate syntax early to catch errors before processing
        if ! bash -n "$CONFIG_FILE" 2>/dev/null; then
            error "Configuration file has syntax errors: $CONFIG_FILE"
            exit 1
        fi
    fi
    
    # Check root after flag parsing (help should work even as root)
    check_root
    
    # Set the remaining arguments
    if [[ ${#temp_args[@]} -gt 0 ]]; then
        set -- "${temp_args[@]}"
    else
        set --
    fi
    
    # Handle command-specific help
    local command="${1:-}"
    local help_requested="false"
    if [[ "${2:-}" == "--help" || "${2:-}" == "-h" ]]; then
        help_requested="true"
    fi
    
    case "$command" in
        setup)
            if [[ "$help_requested" == "true" ]]; then
                show_command_help "setup"
                exit 0
            fi
            # Create operation lock and recovery info
            create_operation_lock "setup" || exit 1
            create_recovery_info "setup"
            
            # Setup doesn't need to load config - it creates it
            install_dependencies
            setup_fixed_configuration
            verify_dns_and_ssl
            install_docker
            create_portainer_user
            create_directories
            create_docker_network
            prepare_nginx_proxy_manager_files
            deploy_portainer
            # NPM must be deployed as a Portainer stack - no fallback
            info "nginx-proxy-manager will be configured after Portainer stack deployment"
            
            # Configure nginx-proxy-manager proxy hosts
            configure_nginx_proxy_manager
            
            # Validate SSH setup for NAS backup functionality
            if validate_ssh_setup; then
                success "SSH key validation passed - NAS backup functionality ready"
            else
                warn "SSH key validation failed - NAS backup functionality may not work properly"
            fi
            
            # Validate system state after setup
            if validate_system_state "setup"; then
                success "Setup completed successfully!"
                echo
                printf "%b\n" "${BLUE}🎉 Docker Stack Backup Manager is Ready!${NC}"
            else
                error "Setup completed but system validation failed"
                error "Some components may not be working correctly"
                error "Check recovery information and logs for troubleshooting"
                exit 1
            fi
            echo "═══════════════════════════════════════════════════════════════"
            echo
            printf "%b\n" "${BLUE}📱 Service Access URLs:${NC}"
            
            # Show Portainer URL
            if ! is_test_environment && [[ "${SKIP_SSL_CERTIFICATES:-false}" != "true" ]]; then
                printf "  • Portainer:              %b\n" "${GREEN}${PORTAINER_URL:-"portainer.domain.com"}${NC}"
            else
                if is_test_environment; then
                    printf "  • Portainer:              %b\n" "${GREEN}http://localhost:9000${NC} (test environment)"
                else
                    printf "  • Portainer:              %b\n" "${YELLOW}http://${PORTAINER_URL:-"portainer.domain.com"}${NC} (configure DNS for HTTPS)"
                fi
            fi
            
            # Show nginx-proxy-manager URL
            if ! is_test_environment && [[ "${SKIP_SSL_CERTIFICATES:-false}" != "true" ]]; then
                printf "  • nginx-proxy-manager:    %b\n" "${GREEN}https://${NPM_URL:-"npm.domain.com"}${NC}"
            else
                if is_test_environment; then
                    printf "  • nginx-proxy-manager:    %b\n" "${GREEN}http://localhost:81${NC} (test environment)"
                else
                    printf "  • nginx-proxy-manager:    %b\n" "${YELLOW}http://${NPM_URL:-"npm.domain.com"}${NC} (configure DNS for HTTPS)"
                fi
            fi
            
            echo
            printf "%b\n" "${BLUE}🔑 Login Credentials (for both services):${NC}"
            printf "  • Username: %b\n" "${GREEN}admin@${DOMAIN_NAME}${NC}"
            printf "  • Password: %b\n" "${GREEN}AdminPassword123!${NC}"
            echo
            printf "%b\n" "${BLUE}💡 Next Steps:${NC}"
            echo "  1. Access Portainer to manage your Docker stacks"
            echo "  2. Use nginx-proxy-manager to configure additional proxy hosts"
            echo "  3. Run './backup-manager.sh backup' to create your first backup"
            echo "  4. Set up automated backups with './backup-manager.sh schedule'"
            echo
            success "Your Docker environment is ready for production use!"
            ;;
        backup)
            if [[ "$help_requested" == "true" ]]; then
                show_command_help "backup"
                exit 0
            fi
            install_dependencies
            load_config
            check_setup_required "backup" || return 1
            create_backup
            ;;
        restore)
            if [[ "$help_requested" == "true" ]]; then
                show_command_help "restore"
                exit 0
            fi
            install_dependencies
            load_config
            check_setup_required "restore" || return 1
            restore_backup
            ;;
        schedule)
            if [[ "$help_requested" == "true" ]]; then
                show_command_help "schedule"
                exit 0
            fi
            install_dependencies
            load_config
            check_setup_required "schedule" || return 1
            setup_schedule
            ;;
        config)
            if [[ "$help_requested" == "true" ]]; then
                show_command_help "config"
                exit 0
            fi
            install_dependencies
            load_config
            interactive_setup_configuration
            
            # Validate SSH setup after configuration
            if ! validate_ssh_setup 2>/dev/null; then
                warn "SSH key validation failed"
                if prompt_yes_no "Would you like to repair SSH key setup? (required for NAS backup functionality)" "y"; then
                    setup_ssh_keys
                    if validate_ssh_setup; then
                        success "SSH key setup repaired successfully"
                    else
                        error "SSH key repair failed - NAS backup functionality may not work"
                    fi
                fi
            else
                success "SSH key setup is valid"
            fi
            ;;
        generate-nas-script)
            if [[ "$help_requested" == "true" ]]; then
                show_command_help "generate-nas-script"
                exit 0
            fi
            install_dependencies
            load_config
            check_setup_required "generate-nas-script" || return 1
            generate_nas_script
            ;;
        update)
            if [[ "$help_requested" == "true" ]]; then
                show_command_help "update"
                exit 0
            fi
            install_dependencies
            update_script
            ;;
        uninstall)
            if [[ "$help_requested" == "true" ]]; then
                show_command_help "uninstall"
                exit 0
            fi
            install_dependencies
            uninstall_system
            ;;
        help|--help|-h)
            usage
            exit 0
            ;;
        "")
            printf "%b\n" "${YELLOW}⚠️  No command specified${NC}"
            echo
            usage
            exit 1
            ;;
        *)
            printf "%b\n" "${RED}❌ Unknown command: $command${NC}"
            echo "💡 Did you mean one of these commands?"
            echo "   • setup, backup, restore, schedule, config, update, uninstall"
            echo "   • Use '$0 --help' to see all available commands"
            echo "   • Use '$0 <command> --help' for command-specific help"
            echo
            exit 1
            ;;
    esac
}

# Only execute main if not being sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi