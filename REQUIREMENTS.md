# Docker Stack Backup - Complete Requirements

## Project Vision
A single-script solution for self-hosters to transform any Ubuntu LTS server into a production-ready Docker environment with automated backup, restore, and management capabilities.

## Core Philosophy
- **Safety First**: Always backup before risky operations
- **User Choice with Smart Defaults**: Provide options but make sensible assumptions
- **Production Ready**: Proper error handling, logging, and reliability
- **Self-Contained**: Minimal external dependencies, maximum portability

## Target Users
Individual self-hosters managing their own Ubuntu servers with sudo access.

## System Requirements
- Ubuntu LTS (24.04 recommended)
- User with sudo privileges (NOT root)
- Ports 80 and 443 available
- Internet connectivity for Docker installation and updates

## Command Structure

### `./backup-manager.sh` (no arguments)
Shows help with available commands and usage examples.

### `./backup-manager.sh setup`
**Complete infrastructure deployment:**

1. **Docker Installation**: Install Docker and Docker Compose if not present
2. **User Management**: Create `portainer` system user with:
   - Docker group access
   - Passwordless sudo for backup operations
   - Log file write permissions
   - Crontab scheduling access

3. **Configuration Collection**:
   - Domain name for services
   - Subdomains for Portainer and NPM
   - Data paths (`/opt/portainer`, `/opt/nginx-proxy-manager`, `/opt/tools`, `/opt/backup`)
   - Backup retention settings
   - Public IP detection and DNS record instructions

4. **DNS Verification** (using `dig` or `nslookup`):
   - Check if `portainer.domain.com` and `npm.domain.com` resolve to server IP
   - Offer HTTP-only fallback if DNS not ready
   - Warn about SSL certificate requirements

5. **Core Service Deployment**:
   - Deploy Portainer with Docker Compose in always-restart mode
   - Initialize admin user via API (`admin@domain.com` / `AdminPassword123!`)
   - Store credentials in `/opt/portainer/.credentials`
   - Create local Docker endpoint in Portainer

6. **NPM Integration**:
   - Deploy nginx-proxy-manager as Portainer stack
   - Configure via API (default→custom credentials)
   - Store credentials in `/opt/nginx-proxy-manager/.credentials`
   - Create proxy hosts for both services
   - Request SSL certificates if DNS ready

7. **Final Configuration**:
   - Ensure only ports 80/443 exposed externally
   - Implement health checks for both services
   - Provide final HTTPS URLs to user

### `./backup-manager.sh config`
**Dynamic reconfiguration:**

1. **Current State Display**: Show existing configuration values as defaults
2. **Safety Check**: Inventory deployed stacks
   - If only Portainer + NPM: Proceed with migration
   - If additional stacks: Warn user about complexity, require confirmation
3. **Pre-Migration Backup**: Create safety backup before path changes
4. **Migration Process**:
   - Capture all stack configurations via Portainer API
   - Stop containers gracefully
   - Move data folders to new paths
   - Update stack configurations with new paths
   - Redeploy with updated configurations
5. **Validation**: Verify all services restart successfully

### `./backup-manager.sh backup`
**Comprehensive backup creation:**

1. **Stack State Capture**: Use Portainer API to record:
   - Running stack IDs and names
   - Complete compose YAML files
   - Environment variables
   - Stack-level settings and policies

2. **Graceful Shutdown**: Stop all containers except Portainer

3. **Archive Creation**: Dual approach for reliability:
   - Create tar.gz with `--same-owner --same-permissions`
   - Generate metadata file with ownership/permissions details
   - Include stack state JSON in archive

4. **Service Restart**: Bring services back online in proper order

5. **Retention Management**: Clean old backups based on configured retention

### `./backup-manager.sh restore`
**Interactive restore process:**

1. **Backup Selection**: List available backups with timestamps and sizes
2. **Architecture Check**: Warn if CPU architecture mismatch detected
3. **Safety Backup**: Create current state backup before restore
4. **Graceful Shutdown**: Stop all containers
5. **Data Restoration**: 
   - Extract tar.gz archive
   - Apply metadata file for ownership/permissions
   - Restore to original paths
6. **Service Recovery**: 
   - Start core services (Portainer, NPM)
   - Use stored stack states to restart previously running stacks
7. **Validation**: Verify all services are accessible

### `./backup-manager.sh schedule`
**Automated backup scheduling:**

1. **Current Schedule Display**: Show existing cron jobs
2. **Schedule Options**: 
   - Predefined intervals (daily, 12h, 6h)
   - Custom cron expressions
   - Test mode (frequent backups for testing)
   - Schedule removal
3. **Cron Management**: Update portainer user's crontab
4. **System Script Deployment**: Ensure `/opt/backup/backup-manager.sh` exists for cron execution

### `./backup-manager.sh generate-nas-script`
**Self-contained remote backup client:**

1. **SSH Key Embedding**: Create standalone script with embedded private key
2. **Configuration Template**: Include configurable paths and settings
3. **Full Functionality**: 
   - Test connectivity
   - List remote backups
   - Sync backups with rsync
   - Local retention management
   - Statistics reporting

### `./backup-manager.sh update`
**Self-update mechanism:**

1. **Internet Connectivity Check**: Verify GitHub access
2. **Version Comparison**: Check current vs. latest release
3. **Dual Update Options**: 
   - Update user's script copy
   - Update system copy at `/opt/backup/backup-manager.sh`
   - Ask user preference for both
4. **Backup Current Version**: Before updating, save current version

## Technical Architecture

### User & Permissions Model
- **portainer** system user owns all Docker operations
- Passwordless sudo for backup operations only
- Docker group membership for container management
- Proper file ownership: services owned by portainer, backups system-wide

### Network Architecture
- **prod-network**: External Docker network for all services
- nginx-proxy-manager: Reverse proxy on ports 80/443/81
- Internal routing: All services accessible via container names
- No direct port exposure except through NPM

### Data Persistence Strategy
```
/opt/portainer/              # Portainer data and configurations
├── data/                    # Portainer application data
├── docker-compose.yml       # Service definition
└── .credentials            # API credentials

/opt/nginx-proxy-manager/
├── data/               # NPM application data
├── letsencrypt/        # SSL certificates
├── docker-compose.yml  # Service definition
└── .credentials        # API credentials

/opt/tools/                  # Additional services
├── dashboard/
├── grafana/
├── postgres/
└── [other-services]/

/opt/backup/                 # System-wide backup storage
├── backup-manager.sh       # System script copy
├── docker_backup_*.tar.gz  # Backup archives
└── metadata/               # Backup metadata files
```

### Backup Reliability Features
- **Dual Preservation**: tar + metadata file for permissions/ownership
- **Stack State Capture**: Full Portainer stack configurations
- **Cross-Architecture Support**: Detection and warnings
- **Graceful Handling**: Proper container shutdown/restart sequences
- **Retention Management**: Configurable cleanup policies

### Error Handling & Logging
- Comprehensive logging to `/var/log/backup-manager.log`
- Graceful API fallbacks if services unavailable
- User-friendly error messages with recovery suggestions
- Test environment detection for appropriate behavior

## Quality Assurance

### Testing Strategy
- **Vagrant Environment**: Full Ubuntu 24.04 VMs for realistic testing
- **Development Environment**: Since the coding could happen on a macOS or Windows as well, all the test runs and code executions should happen inside the vagrant vm created from the Vagrantfile
- **Comprehensive Test Suite**: 22 tests covering all functionality
- **Integration Testing**: Real Docker deployment, API calls, SSH connectivity
- **Cross-Architecture Testing**: Ensure compatibility across platforms

### Production Readiness
- **Security**: Restricted SSH access, proper user isolation
- **Reliability**: Health checks, graceful shutdowns, state preservation
- **Maintainability**: Clear logging, self-updating capability
- **Scalability**: Efficient backup/restore for growing environments

## Success Metrics
- **Single Command Setup**: Fresh Ubuntu → Production ready in one command
- **Zero Data Loss**: Reliable backup/restore with permission preservation
- **Minimal Maintenance**: Self-updating, automated scheduling
- **User Independence**: Works regardless of setup user or environment
- **Production Grade**: Suitable for real-world self-hosting scenarios

This solution transforms the complex process of setting up a production Docker environment into a simple, reliable, single-script experience for self-hosters.