#!/bin/bash

set -euo pipefail

# Docker Backup Manager
# Comprehensive script for Docker-based deployment backup and management
# Compatible with Ubuntu 24.04

VERSION="2025.08.19.2016"
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

# Configuration file
CONFIG_FILE="/etc/docker-backup-manager.conf"

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
cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT

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
    if [[ ! -f "$CONFIG_FILE" ]]; then
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
    if [[ -n "$CONFIG_FILE" ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            error "Configuration file not found: $CONFIG_FILE"
            exit 1
        fi

        info "Loading configuration from: $CONFIG_FILE"

        # Validate and source the config file safely
        if ! bash -n "$CONFIG_FILE" 2>/dev/null; then
            error "Configuration file has syntax errors: $CONFIG_FILE"
            exit 1
        fi

        source "$CONFIG_FILE"
        info "Configuration loaded successfully"
    elif [[ -f "/etc/docker-backup-manager.conf" ]]; then
        # Load system config if it exists and no explicit config file specified
        info "Loading system configuration from: /etc/docker-backup-manager.conf"
        source "/etc/docker-backup-manager.conf"
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
    sudo tee "$CONFIG_FILE" > /dev/null << EOF
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
    success "Configuration saved to $CONFIG_FILE"
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
    local max_wait=60
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
        info "Admin credentials: $PORTAINER_ADMIN_USERNAME / $PORTAINER_ADMIN_PASSWORD"
        
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
        info "Admin credentials: $PORTAINER_ADMIN_USERNAME / $PORTAINER_ADMIN_PASSWORD"
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


# Get stack states from Portainer
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
    
    # Get stack information
    local stacks_response
    stacks_response=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/stacks")
    
    # Create state information
    local stack_states="{}"
    if [[ "$stacks_response" != "null" && -n "$stacks_response" ]]; then
        stack_states=$(echo "$stacks_response" | jq '[.[] | {id: .Id, name: .Name, status: .Status}] | {stacks: .}')
    fi
    
    echo "$stack_states" > "$output_file"
    info "Stack states captured: $(echo "$stack_states" | jq -r '.stacks | length') stacks"
}

# Stop containers gracefully (excluding Portainer)
stop_containers() {
    info "Stopping containers gracefully..."
    info "Keeping Portainer running to manage backup process"
    
    # Stop nginx-proxy-manager
    if sudo -u "$PORTAINER_USER" docker ps | grep -q "nginx-proxy-manager"; then
        sudo -u "$PORTAINER_USER" docker stop nginx-proxy-manager
        info "Stopped nginx-proxy-manager"
    fi
    
    # Stop all other containers (excluding Portainer - keep it running for API management)
    local running_containers
    running_containers=$(sudo -u "$PORTAINER_USER" docker ps --format "{{.Names}}")
    
    if [[ -n "$running_containers" ]]; then
        # Stop each container except Portainer
        echo "$running_containers" | while read -r container_name; do
            if [[ "$container_name" != "portainer" ]]; then
                sudo -u "$PORTAINER_USER" docker stop "$container_name"
                info "Stopped container: $container_name"
            fi
        done
    fi
    
    success "Containers stopped gracefully (Portainer kept running)"
}

# Start containers
start_containers() {
    info "Starting containers..."
    
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
    
    # Start nginx-proxy-manager
    cd "$TOOLS_PATH/nginx-proxy-manager"
    sudo -u "$PORTAINER_USER" docker compose up -d
    
    # Wait a bit for services to be ready
    sleep 10
    
    success "Core containers started"
}

# Restart Portainer stacks based on saved state
restart_stacks() {
    local state_file="$1"
    
    if [[ ! -f "$state_file" ]]; then
        warn "Stack state file not found: $state_file"
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
        warn "Failed to authenticate with Portainer API for stack restart"
        return 0
    fi
    
    # Read stack states and restart running stacks
    local stack_count
    stack_count=$(jq -r '.stacks | length' "$state_file")
    
    if [[ "$stack_count" -gt 0 ]]; then
        info "Restarting $stack_count stacks..."
        
        # Get current stacks
        local current_stacks
        current_stacks=$(curl -s -H "Authorization: Bearer $jwt_token" "$PORTAINER_API_URL/stacks")
        
        # Restart stacks that were running
        jq -r '.stacks[] | select(.status == 1) | .name' "$state_file" | while read -r stack_name; do
            local stack_id
            stack_id=$(echo "$current_stacks" | jq -r ".[] | select(.Name == \"$stack_name\") | .Id")
            
            if [[ -n "$stack_id" && "$stack_id" != "null" ]]; then
                curl -s -X POST "$PORTAINER_API_URL/stacks/$stack_id/start" \
                    -H "Authorization: Bearer $jwt_token" >/dev/null
                info "Restarted stack: $stack_name"
            fi
        done
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

# Create backup
create_backup() {
    info "Starting backup process..."
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_name="docker_backup_${timestamp}"
    local temp_backup_dir="/tmp/${backup_name}"
    local final_backup_file="$BACKUP_PATH/${backup_name}.tar.gz"
    
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
    
    # Create backup with preserved permissions  
    cd /
    if [[ -f "$temp_backup_dir/stack_states.json" ]] || [[ -f "$temp_backup_dir/backup_metadata.json" ]]; then
        # Create uncompressed tar first, add additional files, then compress
        sudo tar --same-owner --same-permissions -cf "${final_backup_file%.gz}" \
            "$(echo $PORTAINER_PATH | sed 's|^/||')" \
            "$(echo $TOOLS_PATH | sed 's|^/||')"
        
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
            "$(echo $TOOLS_PATH | sed 's|^/||')"
    fi
    
    # Ensure backup file has correct ownership
    sudo chown "$PORTAINER_USER:$PORTAINER_USER" "$final_backup_file"
    
    # Start containers again
    start_containers
    
    # Clean up temporary directory
    rm -rf "$temp_backup_dir"
    
    # Manage backup retention
    manage_backup_retention
    
    if [[ -f "$final_backup_file" ]]; then
        success "Backup created: $final_backup_file"
        info "Backup size: $(du -h "$final_backup_file" | cut -f1)"
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
        local max_permissions=1000
        local actual_count=$((permissions_count > max_permissions ? max_permissions : permissions_count))
        
        for ((i=0; i<actual_count; i++)); do
            # Break if this is taking too long (safety mechanism)
            if [[ $((i % 10)) -eq 0 ]] && [[ $i -gt 0 ]]; then
                info "Processing permission entry $i/$actual_count"
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
                
                ((restored_count++))
            fi
        done
        
        success "Restored permissions for $restored_count files/directories"
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
    
    # Start containers
    start_containers
    
    # Wait for Portainer to be ready
    info "Waiting for Portainer to be ready..."
    sleep 30
    
    # Restore stack states
    local stack_state_file="/tmp/stack_states.json"
    if tar -tf "$selected_backup" | grep -q "stack_states.json"; then
        sudo tar -xzf "$selected_backup" -C /tmp stack_states.json 2>/dev/null || true
        if [[ -f "$stack_state_file" ]]; then
            restart_stacks "$stack_state_file"
            sudo rm -f "$stack_state_file"
        fi
    fi
    
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
    
    success "Restore completed and validated successfully"
    success "Portainer available at: $PORTAINER_URL"
    info "Note: Services may take a few minutes to fully initialize"
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
    
    info "Downloading latest version..."
    
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
    
    # Verify downloaded file is valid
    if ! bash -n "$source_file" 2>/dev/null; then
        error "Downloaded $script_type script has syntax errors"
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

# Show usage information
usage() {
    printf "%b" "$(cat << EOF
Docker Backup Manager v${VERSION}

Usage: $0 [FLAGS] {setup|config|backup|restore|schedule|generate-nas-script|update}

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


# Main function dispatcher
main() {
    # Parse flags first - help should work even as root
    local temp_args=()
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
                shift
                ;;
            --config-file)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
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
    
    # Check root after flag parsing (help should work even as root)
    check_root
    
    # Set the remaining arguments
    if [[ ${#temp_args[@]} -gt 0 ]]; then
        set -- "${temp_args[@]}"
    else
        set --
    fi
    
    case "${1:-}" in
        setup)
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
            
            success "Setup completed successfully!"
            success "Portainer available at: $PORTAINER_URL"
            success "nginx-proxy-manager admin panel: http://localhost:81"
            ;;
        backup)
            install_dependencies
            load_config
            check_setup_required || return 1
            create_backup
            ;;
        restore)
            install_dependencies
            load_config
            check_setup_required || return 1
            restore_backup
            ;;
        schedule)
            install_dependencies
            load_config
            check_setup_required || return 1
            setup_schedule
            ;;
        config)
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
            install_dependencies
            load_config
            check_setup_required || return 1
            generate_nas_script
            ;;
        update)
            install_dependencies
            update_script
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
            printf "%b\n" "${RED}❌ Unknown command: $1${NC}"
            echo
            usage
            exit 1
            ;;
    esac
}

# Only execute main if not being sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi