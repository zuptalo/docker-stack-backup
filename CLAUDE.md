# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker Stack Backup is a comprehensive backup solution for Docker-based deployments with automated Portainer and nginx-proxy-manager integration. It provides:

- Complete infrastructure setup with Docker, Portainer, and nginx-proxy-manager
- Intelligent backup with stack state preservation via Portainer API
- Remote backup synchronization with self-contained NAS scripts
- Interactive restore functionality
- Automated scheduling with configurable retention

## Key Commands

### Development and Testing
```bash
# Main development testing (requires Vagrant + VirtualBox)
./dev-test.sh fresh      # Clean test environment (slow but thorough)
./dev-test.sh run        # Test on existing VMs (faster)
./dev-test.sh up         # Start VMs for manual testing
./dev-test.sh shell      # Interactive VM access

# Manual Vagrant operations
vagrant up               # Start both VMs
vagrant ssh primary      # Access main server
vagrant ssh remote       # Access backup server
```

### Production Operations
```bash
# Initial deployment
sudo ./backup-manager.sh setup

# Backup operations
./backup-manager.sh backup
./backup-manager.sh restore
./backup-manager.sh schedule

# NAS integration
./backup-manager.sh generate-nas-script
```

## Architecture

### Core Components
- **backup-manager.sh**: Main script handling all operations (production script)
- **dev-test.sh**: Vagrant-based testing environment with 22 comprehensive tests
- **Vagrantfile**: Defines Ubuntu 24.04 VMs for realistic testing

### System Layout
```
/opt/portainer/              # Portainer data and compose files
/opt/tools/                  # nginx-proxy-manager and other services
  └── nginx-proxy-manager/
/opt/backup/                 # System-wide backup storage
  └── backup-manager.sh      # System script location for cron
```

### User Architecture
- **portainer** system user: Manages all Docker operations and backups
- Has Docker group access and passwordless sudo for backup operations
- Owns service directories but backup storage is system-wide

### Network Design
- **prod-network**: External Docker network connecting all services
- nginx-proxy-manager handles reverse proxy on ports 80/443/81
- Portainer accessible via subdomain through nginx-proxy-manager

## Development Workflow

### Testing Strategy
The project uses enterprise-grade Vagrant testing with full Ubuntu 24.04 VMs:

1. **Initial setup**: `./dev-test.sh fresh` (destroys/recreates VMs)
2. **Iterative development**: `./dev-test.sh run` (uses existing VMs)
3. **Manual testing**: `./dev-test.sh up` then access via Vagrant SSH

### Test Coverage (22 Tests)
- Docker installation and functionality
- User creation and permissions
- Service deployment (Portainer, nginx-proxy-manager)
- Backup creation and restoration
- SSH key management
- Cron scheduling
- NAS script generation
- Remote backup synchronization

### Configuration Management
- `/etc/docker-backup-manager.conf`: Main configuration
- Test environment uses `DOCKER_BACKUP_TEST=true` for non-interactive defaults
- Configuration is interactive in production, automated in tests

## Key Implementation Details

### Backup Process
1. Captures Portainer stack states via API
2. Gracefully stops containers (except Portainer)
3. Creates tar.gz with preserved permissions
4. Restarts services in proper order (nginx-proxy-manager first)
5. Manages retention policies

### NAS Integration
- Generates self-contained scripts with embedded SSH keys
- No setup required on remote NAS
- Configurable local backup paths
- Automated retention management

### Error Handling
- Comprehensive logging to `/var/log/docker-backup-manager.log`
- Graceful fallbacks for API operations
- Test environment detection for appropriate behavior

## Common Issues

### Development
- Ensure VirtualBox and Vagrant are installed for testing
- Tests require ~4GB RAM (3GB primary + 1GB remote VM)
- Use `./dev-test.sh destroy` to completely clean environment

### Production
- Script must be run as regular user with sudo privileges (not root)
- Domain DNS must point to server for SSL certificate generation
- SSH keys are automatically managed for backup operations

## File Structure

```
├── backup-manager.sh        # Main production script
├── dev-test.sh             # Testing environment
├── Vagrantfile             # VM configuration
└── README.md               # Comprehensive documentation
```

The system is designed for user-independent deployment (works with any setup user) and maintains production-ready permissions and error handling throughout.

please go through the TODO.md and REQUIREMENTS.md and then based on the highest priority to lowest start going through addressing the items in TODO.md, for every item that you complete make sure proper tests are added if missing or updated if existing, verify that the whole test suite passes and the commit the changes you made with a proper commit message, push it to the GitHub repo and move on to the next. make sure to add in the commit message that the whole process was done by purely by you following the instructions and no human intervention if you managed to actually start from an item in the todo list and do everything that I requested and push to GitHub, if for any reason you were stopped during implementing an item, make sure to include that in the commit message so other users of the system can see your power and autonomy in action and learn from the experience.