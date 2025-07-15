#!/bin/bash

set -euo pipefail

# Docker Backup Manager
# Comprehensive script for Docker-based deployment backup and management
# Compatible with Ubuntu 24.04

VERSION="2025.07.15.2230"
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

# Test environment defaults
TEST_DOMAIN="zuptalo.local"
TEST_PORTAINER_SUBDOMAIN="pt"
TEST_NPM_SUBDOMAIN="npm"

# Configuration file
CONFIG_FILE="/etc/docker-backup-manager.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Display message to console
    echo -e "${timestamp} [${level}] ${message}"
    
    # Try to write to log file, use sudo if needed
    if echo -e "${timestamp} [${level}] ${message}" >> "${LOG_FILE}" 2>/dev/null; then
        # Success - normal write worked
        :
    else
        # Failed - try with sudo
        echo -e "${timestamp} [${level}] ${message}" | sudo tee -a "${LOG_FILE}" >/dev/null 2>&1 || true
    fi
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

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        die "This script should not be run as root for security reasons. Run as a regular user with sudo privileges."
    fi
}

# Check if running in test environment
is_test_environment() {
    [[ "${DOCKER_BACKUP_TEST:-}" == "true" ]] || [[ -f "/.dockerenv" ]]
}

# Setup log file with proper permissions
setup_log_file() {
    # Create log file if it doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        sudo touch "$LOG_FILE"
        info "Created log file: $LOG_FILE"
    fi
    
    # Set proper permissions so both vagrant and portainer users can write
    sudo chmod 666 "$LOG_FILE"
    
    # Test write access
    if echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Log file setup completed" >> "$LOG_FILE" 2>/dev/null; then
        success "Log file permissions configured successfully"
    else
        warn "Log file permissions may need adjustment"
    fi
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
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

# Interactive configuration
configure_paths() {
    # Skip interactive configuration in test environment or if config already exists
    if is_test_environment; then
        info "Skipping interactive configuration in test environment"
        save_config
        return 0
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        info "Using existing configuration"
        return 0
    fi
    
    echo -e "${BLUE}=== Docker Backup Manager Configuration ===${NC}"
    echo
    
    read -p "Portainer data path [$PORTAINER_PATH]: " input
    PORTAINER_PATH="${input:-$PORTAINER_PATH}"
    
    read -p "Tools data path [$TOOLS_PATH]: " input
    TOOLS_PATH="${input:-$TOOLS_PATH}"
    
    read -p "Backup storage path [$BACKUP_PATH]: " input
    BACKUP_PATH="${input:-$BACKUP_PATH}"
    
    read -p "Local backup retention (days) [$BACKUP_RETENTION]: " input
    BACKUP_RETENTION="${input:-$BACKUP_RETENTION}"
    
    read -p "Remote backup retention (days) [$REMOTE_RETENTION]: " input
    REMOTE_RETENTION="${input:-$REMOTE_RETENTION}"
    
    read -p "Domain name [$DOMAIN_NAME]: " input
    DOMAIN_NAME="${input:-$DOMAIN_NAME}"
    
    read -p "Portainer subdomain [$PORTAINER_SUBDOMAIN]: " input
    PORTAINER_SUBDOMAIN="${input:-$PORTAINER_SUBDOMAIN}"
    
    read -p "NPM admin subdomain [$NPM_SUBDOMAIN]: " input
    NPM_SUBDOMAIN="${input:-$NPM_SUBDOMAIN}"
    
    read -p "Portainer system user [$PORTAINER_USER]: " input
    PORTAINER_USER="${input:-$PORTAINER_USER}"
    
    PORTAINER_URL="${PORTAINER_SUBDOMAIN}.${DOMAIN_NAME}"
    NPM_URL="${NPM_SUBDOMAIN}.${DOMAIN_NAME}"
    
    echo
    echo -e "${BLUE}Configuration Summary:${NC}"
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
    
    read -p "Save this configuration? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "Configuration not saved. Exiting."
        exit 0
    fi
    
    save_config
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

# Check DNS resolution using dig or nslookup
check_dns_resolution() {
    local domain="$1"
    local expected_ip="$2"
    
    local resolved_ip=""
    
    # Try dig first (more reliable)
    if command -v dig >/dev/null 2>&1; then
        resolved_ip=$(dig +short "$domain" A 2>/dev/null | head -1)
    elif command -v nslookup >/dev/null 2>&1; then
        resolved_ip=$(nslookup "$domain" 2>/dev/null | grep -A1 "^Name:" | grep "Address:" | awk '{print $2}' | head -1)
    fi
    
    # Clean up any trailing characters
    resolved_ip=$(echo "$resolved_ip" | tr -d '\r\n ')
    
    # Check if resolved IP matches expected IP
    if [[ "$resolved_ip" == "$expected_ip" ]]; then
        return 0
    else
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
        read -p "Continue without DNS verification? [y/N]: " continue_without_dns
        if [[ ! "$continue_without_dns" =~ ^[Yy]$ ]]; then
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
    
    # Check Portainer domain
    if check_dns_resolution "$PORTAINER_URL" "$public_ip"; then
        success "✅ $PORTAINER_URL resolves to $public_ip"
        portainer_dns_ok=true
    else
        local resolved_ip=$(dig +short "$PORTAINER_URL" A 2>/dev/null | head -1)
        if [[ -n "$resolved_ip" ]]; then
            error "❌ $PORTAINER_URL resolves to $resolved_ip (expected: $public_ip)"
        else
            error "❌ $PORTAINER_URL does not resolve to any IP address"
        fi
    fi
    
    # Check NPM domain
    if check_dns_resolution "$NPM_URL" "$public_ip"; then
        success "✅ $NPM_URL resolves to $public_ip"
        npm_dns_ok=true
    else
        local resolved_ip=$(dig +short "$NPM_URL" A 2>/dev/null | head -1)
        if [[ -n "$resolved_ip" ]]; then
            error "❌ $NPM_URL resolves to $resolved_ip (expected: $public_ip)"
        else
            error "❌ $NPM_URL does not resolve to any IP address"
        fi
    fi
    
    echo
    
    # Provide DNS record instructions
    if [[ "$portainer_dns_ok" == false ]] || [[ "$npm_dns_ok" == false ]]; then
        warn "DNS records need to be configured for SSL certificates to work"
        echo
        info "Please add the following DNS records to your domain provider:"
        echo
        echo -e "${BLUE}DNS Records Required:${NC}"
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
        
        read -p "Select option [1-3]: " dns_choice
        
        case "$dns_choice" in
            1)
                echo
                info "Waiting for DNS propagation..."
                echo "Press Ctrl+C to cancel or wait..."
                sleep 10
                
                # Re-check DNS after wait
                return $(verify_dns_and_ssl)
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
    
    # Generate SSH key pair
    sudo -u "$PORTAINER_USER" ssh-keygen -t rsa -b 4096 -f "/home/$PORTAINER_USER/.ssh/id_rsa" -N ""
    
    # Set up SSH access for backups
    if ! is_test_environment; then
        # Restricted SSH access for production
        sudo -u "$PORTAINER_USER" tee "/home/$PORTAINER_USER/.ssh/authorized_keys" > /dev/null << EOF
# Restricted key for backup access only
command="rsync --server --daemon .",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty $(cat /home/$PORTAINER_USER/.ssh/id_rsa.pub | cut -d' ' -f1-2)
EOF
        info "Set up restricted SSH access for production"
    else
        # Full SSH access for test environment
        sudo -u "$PORTAINER_USER" cp "/home/$PORTAINER_USER/.ssh/id_rsa.pub" "/home/$PORTAINER_USER/.ssh/authorized_keys"
        info "Set up full SSH access for test environment"
    fi
    
    sudo chmod 600 "/home/$PORTAINER_USER/.ssh/authorized_keys"
    sudo chown "$PORTAINER_USER:$PORTAINER_USER" "/home/$PORTAINER_USER/.ssh/authorized_keys"
    
    success "User $PORTAINER_USER created with SSH key pair"
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
    
    # Create docker-compose.yml for nginx-proxy-manager
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
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    networks:
      - prod-network
    environment:
      DB_SQLITE_FILE: "/data/database.sqlite"
      DISABLE_IPV6: 'true'

networks:
  prod-network:
    external: true
EOF

    # Create credentials file with default values
    sudo -u "$PORTAINER_USER" tee "$npm_path/.credentials" > /dev/null << EOF
NPM_ADMIN_EMAIL=admin@example.com
NPM_ADMIN_PASSWORD=changeme
NPM_API_URL=http://localhost:81/api
EOF

    success "nginx-proxy-manager files prepared"
    info "Compose file: $npm_path/docker-compose.yml"
    info "Credentials file: $npm_path/.credentials"
    info "Will be deployed as a Portainer stack"
}

# Configure nginx-proxy-manager via API
configure_nginx_proxy_manager() {
    info "Configuring nginx-proxy-manager..."
    
    local npm_path="$TOOLS_PATH/nginx-proxy-manager"
    
    # Use default credentials first (nginx-proxy-manager always starts with these)
    NPM_ADMIN_EMAIL="admin@example.com"
    NPM_ADMIN_PASSWORD="changeme"
    
    # Try to source custom credentials if they exist, but fall back to defaults
    if [[ -f "$npm_path/.credentials" ]]; then
        source "$npm_path/.credentials" || true
    fi
    
    # Wait for API to be available - API endpoint responds even during initialization
    info "Waiting for nginx-proxy-manager API to be ready..."
    local max_attempts=20
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        # Test actual authentication rather than just endpoint availability
        local test_token
        test_token=$(curl -s -X POST "http://localhost:81/api/tokens" \
            -H "Content-Type: application/json" \
            -d '{"identity": "admin@example.com", "secret": "changeme"}' | \
            jq -r '.token // empty' 2>/dev/null)
        
        if [[ -n "$test_token" && "$test_token" != "null" ]]; then
            info "nginx-proxy-manager API is ready and authenticated"
            break
        fi
        info "Waiting for nginx-proxy-manager API... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        warn "nginx-proxy-manager API not available after $max_attempts attempts"
        warn "nginx-proxy-manager deployed but automatic configuration skipped"
        warn "You can configure it manually at: http://localhost:81"
        warn "Default credentials: admin@example.com / changeme"
        return 0
    fi
    
    # Login and get token (using default credentials first)
    local token
    token=$(curl -s -X POST "http://localhost:81/api/tokens" \
        -H "Content-Type: application/json" \
        -d '{"identity": "admin@example.com", "secret": "changeme"}' | \
        jq -r '.token // empty')
    
    if [[ -z "$token" ]]; then
        warn "Failed to authenticate with nginx-proxy-manager"
        warn "nginx-proxy-manager is running but API configuration failed"
        warn "You can configure it manually at: http://localhost:81"
        warn "Default credentials: admin@example.com / changeme"
        return 0
    fi
    
    info "Successfully authenticated with nginx-proxy-manager API"
    
    # Update admin user password (skip in test environment to avoid conflicts)
    if ! is_test_environment; then
        local user_id
        user_id=$(curl -s -H "Authorization: Bearer $token" "http://localhost:81/api/users" | \
            jq -r '.[] | select(.email == "admin@example.com") | .id')
        
        if [[ -n "$user_id" ]]; then
            curl -s -X PUT "http://localhost:81/api/users/$user_id" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" \
                -d "{\"email\": \"$NPM_ADMIN_EMAIL\", \"password\": \"$NPM_ADMIN_PASSWORD\"}" >/dev/null
            
            info "Updated admin credentials"
        fi
    fi
    
    # Create proxy hosts for both services
    create_portainer_proxy_host "$token"
    create_npm_proxy_host "$token"
}

# Create proxy host for Portainer
create_portainer_proxy_host() {
    local token="$1"
    
    info "Creating proxy host for $PORTAINER_URL..."
    
    # Create proxy host with minimal required fields
    local proxy_response
    proxy_response=$(curl -s -X POST "http://localhost:81/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_names\": [\"$PORTAINER_URL\"],
            \"forward_scheme\": \"http\",
            \"forward_host\": \"portainer\",
            \"forward_port\": 9000
        }")
    
    local proxy_id
    proxy_id=$(echo "$proxy_response" | jq -r '.id // empty')
    
    if [[ -n "$proxy_id" ]]; then
        success "Proxy host created for $PORTAINER_URL (ID: $proxy_id)"
        
        # Request SSL certificate (skip in test environment or if DNS not configured)
        if is_test_environment; then
            warn "Skipping SSL certificate request in test environment"
        elif [[ "${SKIP_SSL_CERTIFICATES:-false}" == "true" ]]; then
            warn "Skipping SSL certificate request - DNS not configured"
        else
            info "Requesting SSL certificate for $PORTAINER_URL..."
            curl -s -X POST "http://localhost:81/api/nginx/certificates" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" \
                -d "{
                    \"provider\": \"letsencrypt\",
                    \"domain_names\": [\"$PORTAINER_URL\"],
                    \"meta\": {
                        \"letsencrypt_email\": \"$NPM_ADMIN_EMAIL\",
                        \"letsencrypt_agree\": true
                    }
                }" >/dev/null
            
            success "SSL certificate requested for $PORTAINER_URL"
        fi
    else
        error "Failed to create proxy host for $PORTAINER_URL"
    fi
}

# Create proxy host for nginx-proxy-manager admin interface
create_npm_proxy_host() {
    local token="$1"
    
    info "Creating proxy host for $NPM_URL..."
    
    # Create proxy host for NPM admin interface with minimal required fields
    local proxy_response
    proxy_response=$(curl -s -X POST "http://localhost:81/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_names\": [\"$NPM_URL\"],
            \"forward_scheme\": \"http\",
            \"forward_host\": \"localhost\",
            \"forward_port\": 81
        }")
    
    local proxy_id
    proxy_id=$(echo "$proxy_response" | jq -r '.id // empty')
    
    if [[ -n "$proxy_id" ]]; then
        success "Proxy host created for $NPM_URL (ID: $proxy_id)"
        
        # Request SSL certificate (skip in test environment or if DNS not configured)
        if is_test_environment; then
            warn "Skipping SSL certificate request in test environment"
        elif [[ "${SKIP_SSL_CERTIFICATES:-false}" == "true" ]]; then
            warn "Skipping SSL certificate request - DNS not configured"
        else
            info "Requesting SSL certificate for $NPM_URL..."
            curl -s -X POST "http://localhost:81/api/nginx/certificates" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" \
                -d "{
                    \"provider\": \"letsencrypt\",
                    \"domain_names\": [\"$NPM_URL\"],
                    \"meta\": {
                        \"letsencrypt_email\": \"$NPM_ADMIN_EMAIL\",
                        \"letsencrypt_agree\": true
                    }
                }" >/dev/null
            
            success "SSL certificate requested for $NPM_URL"
        fi
    else
        error "Failed to create proxy host for $NPM_URL"
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
    sudo -u "$PORTAINER_USER" tee "$PORTAINER_PATH/.credentials" > /dev/null << EOF
PORTAINER_ADMIN_USERNAME=admin
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
    
    # Stop containers gracefully
    stop_containers
    
    info "Creating backup archive..."
    
    # Ensure backup directory has correct permissions
    sudo chown -R "$PORTAINER_USER:$PORTAINER_USER" "$BACKUP_PATH"
    sudo chmod 755 "$BACKUP_PATH"
    
    # Create backup with preserved permissions  
    cd /
    if [[ -f "$temp_backup_dir/stack_states.json" ]]; then
        # Create uncompressed tar first, add stack_states.json, then compress
        sudo tar --same-owner --same-permissions -cf "${final_backup_file%.gz}" \
            "$(echo $PORTAINER_PATH | sed 's|^/||')" \
            "$(echo $TOOLS_PATH | sed 's|^/||')"
        sudo tar --same-owner --same-permissions -rf "${final_backup_file%.gz}" \
            -C "$temp_backup_dir" stack_states.json
        sudo gzip "${final_backup_file%.gz}"
    else
        # Create compressed tar directly if no stack_states.json
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

# List available backups
list_backups() {
    echo -e "${BLUE}Available backups:${NC}"
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
    read -p "Select backup number to restore (or 'q' to quit): " choice
    
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
    echo -e "${YELLOW}WARNING: This will stop all containers and restore data from backup!${NC}"
    echo "Selected backup: $backup_name"
    echo
    read -p "Are you sure you want to continue? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
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
    tar --same-owner --same-permissions -czf "$BACKUP_PATH/${current_backup_name}.tar.gz" \
        "$(echo $PORTAINER_PATH | sed 's|^/||')" \
        "$(echo $TOOLS_PATH | sed 's|^/||')" 2>/dev/null || true
    
    # Extract backup
    info "Extracting backup..."
    cd /
    tar --same-owner --same-permissions -xzf "$selected_backup"
    
    # Start containers
    start_containers
    
    # Wait for Portainer to be ready
    info "Waiting for Portainer to be ready..."
    sleep 30
    
    # Restore stack states
    local stack_state_file="/tmp/stack_states.json"
    if tar -tf "$selected_backup" | grep -q "stack_states.json"; then
        tar -xzf "$selected_backup" -C /tmp stack_states.json 2>/dev/null || true
        if [[ -f "$stack_state_file" ]]; then
            restart_stacks "$stack_state_file"
            rm -f "$stack_state_file"
        fi
    fi
    
    success "Restore completed successfully"
    success "Portainer available at: $PORTAINER_URL"
}

# Setup backup scheduling
setup_schedule() {
    echo -e "${BLUE}=== Backup Scheduling Setup ===${NC}"
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
            echo "Enter cron schedule (e.g., '0 3 * * *' for daily at 3 AM):"
            if is_test_environment && [[ ! -t 0 ]]; then
                # Non-interactive mode - read from stdin
                read cron_schedule
            else
                read -p "Cron schedule: " cron_schedule
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
    SSH_KEY_PATH="/home/$PORTAINER_USER/.ssh/id_rsa"
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
LOCAL_BACKUP_PATH="/volume1/backup/zuptalo"  # Change this path as needed
RETENTION_DAYS=30

# Temporary directory for SSH key
TEMP_DIR="/tmp/docker-backup-$$"
SSH_KEY_FILE="$TEMP_DIR/primary_key"

# =================================================================
# EMBEDDED SSH PRIVATE KEY (DO NOT EDIT BELOW THIS LINE)
# =================================================================

SSH_PRIVATE_KEY_B64="__SSH_PRIVATE_KEY_B64__"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}"
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
    
    # Remove 'v' prefix if present
    version1=$(echo "$version1" | sed 's/^v//')
    version2=$(echo "$version2" | sed 's/^v//')
    
    # Handle legacy semantic versions (X.Y.Z) by treating them as older than any date
    if [[ "$version1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # version1 is semantic (old), version2 should be date-based (newer)
        return 2  # version1 < version2
    elif [[ "$version2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # version2 is semantic (old), version1 should be date-based (newer) 
        return 1  # version1 > version2
    fi
    
    # Both are date-based (YYYY.MM.DD.HHMM or YYYY.MM.DD), convert to comparable format
    local date1=$(echo "$version1" | tr -d '.')
    local date2=$(echo "$version2" | tr -d '.')
    
    # Pad shorter format (YYYY.MM.DD) to match longer format (YYYY.MM.DD.HHMM)
    # This ensures backward compatibility with YYYY.MM.DD format
    if [[ ${#date1} -eq 8 ]]; then
        date1="${date1}0000"  # Add 0000 for midnight
    fi
    if [[ ${#date2} -eq 8 ]]; then
        date2="${date2}0000"  # Add 0000 for midnight
    fi
    
    # Numeric comparison of date strings
    if (( date1 > date2 )); then
        return 1  # version1 > version2
    elif (( date1 < date2 )); then
        return 2  # version1 < version2
    else
        return 0  # versions are equal
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
    
    # Compare versions
    compare_versions "$VERSION" "$latest_version"
    local comparison=$?
    
    case $comparison in
        0)
            success "You are already running the latest version ($VERSION)"
            return 0
            ;;
        1)
            warn "You are running a newer version ($VERSION) than the latest release ($latest_version)"
            warn "This might be a development version"
            read -p "Continue with update anyway? [y/N]: " continue_update
            if [[ ! "$continue_update" =~ ^[Yy]$ ]]; then
                info "Update cancelled"
                return 0
            fi
            ;;
        2)
            info "Update available: $VERSION → $latest_version"
            ;;
    esac
    
    # Download latest version
    local temp_file
    if ! temp_file=$(download_latest_version); then
        return 1
    fi
    
    success "Latest version downloaded"
    
    # Ask user what to update
    echo
    echo "Select what to update:"
    echo "1) Current script only ($(realpath "$0"))"
    echo "2) System script only (/opt/backup/backup-manager.sh)"
    echo "3) Both scripts (recommended)"
    echo "4) Cancel update"
    echo
    
    read -p "Select option [1-4]: " update_choice
    
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
    cat << EOF
Docker Backup Manager v${VERSION}

Usage: $0 {setup|backup|restore|schedule|config|generate-nas-script|update}

Commands:
    setup               - Initial setup (install Docker, create user, deploy services)
    backup              - Create backup of all data
    restore             - Restore from backup (interactive selection)
    schedule            - Setup automated backups
    config              - Interactive configuration
    generate-nas-script - Generate self-contained NAS backup script
    update              - Update script to latest version from GitHub

Examples:
    $0 setup               # First-time setup
    $0 backup              # Create backup now
    $0 restore             # Choose and restore backup
    $0 schedule            # Setup cron job for backups
    $0 generate-nas-script # Create NAS backup client script
    $0 update              # Update to latest version

EOF
}

# Main function dispatcher
main() {
    check_root
    load_config
    
    case "${1:-}" in
        setup)
            setup_log_file
            configure_paths
            verify_dns_and_ssl
            install_docker
            create_portainer_user
            create_directories
            create_docker_network
            prepare_nginx_proxy_manager_files
            deploy_portainer
            # NPM must be deployed as a Portainer stack - no fallback
            info "nginx-proxy-manager will be configured after Portainer stack deployment"
            success "Setup completed successfully!"
            success "Portainer available at: $PORTAINER_URL"
            success "nginx-proxy-manager admin panel: http://localhost:81"
            ;;
        backup)
            create_backup
            ;;
        restore)
            restore_backup
            ;;
        schedule)
            setup_schedule
            ;;
        config)
            configure_paths
            ;;
        generate-nas-script)
            generate_nas_script
            ;;
        update)
            update_script
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# Only execute main if not being sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi