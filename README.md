# Docker Stack Backup

[![Create Release on Push to Main](https://github.com/zuptalo/docker-stack-backup/actions/workflows/release.yml/badge.svg)](https://github.com/zuptalo/docker-stack-backup/actions/workflows/release.yml)
[![Latest Release](https://img.shields.io/github/v/release/zuptalo/docker-stack-backup)](https://github.com/zuptalo/docker-stack-backup/releases/latest)

Single-script solution to transform any Ubuntu LTS server into a production-ready Docker environment with automated backup, restore, and management capabilities for self-hosters.

## 🚀 Features

- **Complete Infrastructure Setup**: Automatically installs Docker, creates users, and deploys services
- **nginx-proxy-manager Integration**: Automatic SSL certificate management and reverse proxy
- **Portainer Management**: Pre-configured with API integration for stack management
- **Intelligent Backups**: Preserves file permissions, captures stack states, and graceful container handling
- **Automated Scheduling**: Cron-based backup scheduling with configurable retention
- **Remote Backup Sync**: Secure SSH-based backup synchronization to remote servers
- **Interactive Restore**: Select and restore from available backups with automatic stack restart
- **Self-Contained NAS Scripts**: Generate standalone backup clients with embedded SSH keys
- **User-Independent**: Works with any setup user (vagrant, ubuntu, admin, etc.)
- **System-Wide Architecture**: Uses `/opt/backup` for consistent, production-ready deployment

## 📁 Scripts

### 1. backup-manager.sh
Main script for local Docker environment management and backup operations. Includes integrated NAS backup script generation.

### 2. dev-test.sh
Development test environment for comprehensive testing using Vagrant VMs.

## 🚀 Quick Start

### Production Deployment

```bash
# Download latest release
curl -fsSL https://raw.githubusercontent.com/zuptalo/docker-stack-backup/main/backup-manager.sh -o backup-manager.sh
chmod +x backup-manager.sh

# Run initial setup
./backup-manager.sh setup
```

   This will:
   - Configure paths and settings interactively
   - Install Docker and Docker Compose
   - Create portainer system user with SSH keys
   - Create required directories with proper permissions
   - Deploy nginx-proxy-manager on ports 80/443/81
   - Deploy Portainer with pre-configured admin credentials
   - Create Docker network `prod-network`
   - Configure SSL certificates for your domain

### Configuration

During setup, you'll configure:
- **Portainer Path**: `/opt/portainer` (default)
- **Tools Path**: `/opt/tools` (default)
- **Backup Path**: `/opt/backup` (default)
- **Domain**: `zuptalo.com` (default)
- **Portainer Subdomain**: `pt` (default)
- **Backup Retention**: 7 days (default)

## 💻 Usage

### Backup Operations

```bash
# Create a backup
./backup-manager.sh backup

# List and restore from backups
./backup-manager.sh restore

# Setup automated backups
./backup-manager.sh schedule

# Update to latest version
./backup-manager.sh update

# Reconfigure settings
./backup-manager.sh config
```

### NAS Backup Generation

```bash
# Generate self-contained NAS backup script (integrated into main script)
./backup-manager.sh generate-nas-script

# The generated script is completely self-contained:
# - Contains embedded SSH private key
# - No additional setup required on remote machine
# - No portainer user needed on NAS
# - Configurable backup path in script header
```

### NAS Backup Usage

```bash
# On your NAS, test the generated script:
./nas-backup-client.sh test

# List available backups:
./nas-backup-client.sh list

# Sync backups:
./nas-backup-client.sh sync

# Show statistics:
./nas-backup-client.sh stats
```

## 🏗️ Architecture

### Network Setup
- **prod-network**: External Docker network for all services
- **nginx-proxy-manager**: Entry point (ports 80, 443, 81)
- **Portainer**: Management interface (internal port 9000)
- **User Stacks**: All deployed via Portainer on prod-network

### File Structure
```
/opt/portainer/              # Portainer data and config
├── docker-compose.yml
├── .credentials
└── data/

/opt/tools/                  # Other services data
├── nginx-proxy-manager/
│   ├── docker-compose.yml
│   ├── .credentials
│   ├── data/
│   └── letsencrypt/
└── [other-services]/

/opt/backup/                # Backup storage (system-wide)
├── backup-manager.sh    # System script location
├── docker_backup_YYYYMMDD_HHMMSS.tar.gz
└── ...
```

## 🔒 Security Features

### User Management
- Dedicated `portainer` system user for all operations
- SSH key generation with restricted access
- Proper file permissions and ownership
- System-wide script deployment at `/opt/backup/backup-manager.sh`

### Backup Security
- File permissions and ownership preservation
- Secure credential storage
- Graceful container shutdown for data consistency

### Remote Access
- SSH key-based authentication
- Self-contained backup scripts with embedded keys
- Configurable retention policies

## 🔄 Backup Process

1. **Pre-backup**: Capture running stack states via Portainer API
2. **Graceful Shutdown**: Stop all containers except Portainer
3. **Create Archive**: tar.gz with preserved permissions/ownership
4. **Restart Services**: nginx-proxy-manager first, then other stacks
5. **Cleanup**: Manage retention policy (default: 7 local, 30 remote)

## 🔧 Restore Process

1. **Interactive Selection**: Choose from available backups
2. **Safety Backup**: Create backup of current state
3. **Graceful Shutdown**: Stop all containers
4. **Extract Data**: Restore files with original permissions
5. **Service Restart**: Bring services back online
6. **Stack Recovery**: Restart only previously running stacks

## 📝 Configuration Files

### Main Configuration
- `/etc/backup-manager.conf`: Main script settings

### Service Credentials
- `/opt/portainer/.credentials`: Portainer admin credentials
- `/opt/tools/nginx-proxy-manager/.credentials`: NPM admin credentials

## 📊 Logs

- `/var/log/backup-manager.log`: Main script logs

## 🧪 Testing Environment

### Vagrant Testing (Recommended)

The project includes a comprehensive Vagrant-based testing environment that provides **enterprise-grade testing** in a **realistic environment**.

#### Why Vagrant + VirtualBox?

**✅ Perfect for Testing:**
- **Real Ubuntu 24.04 VMs** - exactly like production
- **Full systemd support** - all services work properly 
- **Native Docker installation** - tests actual installation process
- **Proper SSH connectivity** - authentic remote backup testing
- **All services work natively** - nginx-proxy-manager, Portainer, etc.

#### Prerequisites (macOS)

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install VirtualBox
brew install --cask virtualbox

# Install Vagrant
brew install --cask vagrant

# Install vagrant-scp plugin (for file copying)
vagrant plugin install vagrant-scp
```

#### Quick Start Testing

```bash
# Make script executable
chmod +x dev-test.sh

# Run comprehensive tests
./dev-test.sh fresh
```

This will:
1. ✅ **Create 2 Ubuntu 24.04 VMs** (primary + remote)
2. ✅ **Install all dependencies** automatically
3. ✅ **Run comprehensive tests** (31 tests total)
4. ✅ **Test remote backup sync** between VMs

#### Manual Testing

```bash
# Start VMs only
./dev-test.sh up

# Access primary server
vagrant ssh primary

# Access remote server  
vagrant ssh remote

# Interactive VM access
./dev-test.sh shell
```

#### Test Commands

```bash
# Development test environment
./dev-test.sh run        # Fast: run tests on existing VMs
./dev-test.sh fresh      # Slow: clean start with fresh VMs
./dev-test.sh up         # Start VMs only (for manual testing)
./dev-test.sh down       # Stop VMs
./dev-test.sh destroy    # Destroy VMs completely
./dev-test.sh ps         # Show VM status and access info
./dev-test.sh shell      # Interactive VM access menu

# Direct Vagrant commands
vagrant up               # Start both VMs
vagrant ssh primary      # Access primary server
vagrant ssh remote       # Access remote server
vagrant halt             # Stop VMs
vagrant destroy -f       # Destroy VMs
```

#### VM Architecture

```
Host Machine (macOS)
├── Port 8090 → Primary VM nginx-proxy-manager HTTP (80)
├── Port 8091 → Primary VM nginx-proxy-manager Admin (81) 
├── Port 8453 → Primary VM nginx-proxy-manager HTTPS (443)
├── Port 9001 → Primary VM Portainer (9000)
└── Port 2223 → Remote VM SSH (22)

Primary VM (192.168.56.10)
├── Ubuntu 24.04 LTS
├── Docker Stack Backup
├── nginx-proxy-manager
├── Portainer  
├── Full systemd support
└── SSH client for remote backup

Remote VM (192.168.56.11)
├── Ubuntu 24.04 LTS
├── SSH server
├── portainer user (matching primary)
└── Remote backup storage
```

#### Test Coverage

**✅ 100% Testable:**
- Complete Docker installation process
- Real systemd service management
- Authentic nginx-proxy-manager deployment
- Native Portainer functionality
- SSH-based backup synchronization
- Real file permissions/ownership preservation
- Production-like environment testing

**31 Comprehensive Tests:**
1. Script Syntax Check
2. Help Command
3. **Docker Setup and Installation** (real installation!)
4. Docker Functionality
5. Portainer User Creation
6. Directory Structure
7. Docker Network Creation
8. nginx-proxy-manager Deployment
9. Portainer Deployment
10. Configuration Files
11. **Service Accessibility** (real HTTP endpoints)
12. Backup Creation
13. Container Restart After Backup
14. Backup Listing
15. SSH Key Setup
16. Log Files
17. Cron Scheduling (automated backup scheduling)
18. **NAS Backup Script Generation** (self-contained script creation)
19. NAS Backup Script Functionality
20. **Remote Backup Sync** (real SSH between VMs)
21. Backup File Validation
22. Architecture Validation

#### Expected Results

All 31 tests should pass in this environment:

```
Tests Passed: 31
Tests Failed: 0
Total Tests: 31

🎉 ALL TESTS PASSED!
Docker Stack Backup is working correctly!
```

#### Service Access (After Testing)

- **nginx-proxy-manager**: http://localhost:8091
- **Portainer**: http://localhost:9001
- **Primary VM SSH**: `vagrant ssh primary`
- **Remote VM SSH**: `vagrant ssh remote`

#### Resource Usage

- **Primary VM**: 3GB RAM, 2 CPU cores
- **Remote VM**: 1GB RAM, 1 CPU core
- **Total**: ~4GB RAM usage (reasonable for testing)

#### Cleanup

```bash
# Stop VMs (keep disks)
./dev-test.sh down

# Completely remove VMs and disks
./dev-test.sh destroy
```

## 📋 Requirements

### System Requirements
- Ubuntu 24.04 LTS (recommended)
- User with sudo privileges
- Internet connection for package downloads

### Network Requirements
- Domain pointing to server IP (for SSL certificates)
- Ports 80, 443 open for nginx-proxy-manager
- Port 81 open for nginx-proxy-manager admin (optional)

### Remote Backup Requirements
- SSH access to remote server (NAS)
- Remote server with sufficient storage
- SSH key authentication configured (automatic with generated scripts)

## 🌐 Default Access

After setup completion:

- **Portainer**: `https://pt.zuptalo.com` (or your configured domain)
- **nginx-proxy-manager**: `http://server-ip:81`

Credentials are stored in respective `.credentials` files.

## 🔧 Troubleshooting

### Check Service Status
```bash
docker ps
docker logs nginx-proxy-manager
docker logs portainer
```

### Verify Network
```bash
docker network ls
docker network inspect prod-network
```

### Check Logs
```bash
tail -f /var/log/backup-manager.log
```

### Manual Service Restart
```bash
cd /opt/tools/nginx-proxy-manager
sudo -u portainer docker compose restart

cd /opt/portainer
sudo -u portainer docker compose restart
```

### Check Backup System
```bash
# Check system-wide script location
ls -la /opt/backup/backup-manager.sh

# Check cron jobs
sudo -u portainer crontab -l

# Test backup creation
sudo -u portainer /opt/backup/backup-manager.sh backup
```

## 🏢 Production Deployment

### For Synology NAS Integration

1. **Set up primary server** with Docker Stack Backup
2. **Generate NAS backup script**: `./backup-manager.sh generate-nas-script`
3. **Copy script to NAS**: Transfer `nas-backup-client.sh` to your Synology NAS
4. **Configure NAS path**: Edit `LOCAL_BACKUP_PATH` in script header (e.g., `/volume1/backup/docker-backups`)
5. **Schedule with DSM**: Use Synology Task Scheduler to run `./nas-backup-client.sh sync`

### For Any Linux Server

The system works with any Linux distribution and user account:
- Works with `ubuntu` user on AWS EC2
- Works with `admin` user on corporate servers
- Works with any custom username
- Automatically handles permissions and script deployment

## 🎯 Key Benefits

- **User-Independent**: Works regardless of setup user (vagrant, ubuntu, admin, etc.)
- **System-Wide Deployment**: Script installed at `/opt/backup/backup-manager.sh`
- **Production-Ready**: Robust permissions, error handling, and logging
- **Self-Contained NAS Scripts**: No setup required on remote servers
- **Comprehensive Testing**: 31 automated tests covering all functionality
- **Enterprise-Grade**: Suitable for production environments and compliance requirements

## 🤝 Contributing & Community

This project started as a personal hobby project to solve my own Docker backup needs, and I'm sharing it openly for others who might find it useful. While I've put effort into testing and documentation, please understand this comes with typical hobby project caveats.

### 🔧 Use at Your Own Risk
- Test thoroughly in your environment before production use
- No warranty or guarantees provided - this is hobby code shared freely
- Evaluate and adapt to your specific needs and requirements
- Always backup your data before trying new backup tools! 😉

### 🌟 Contributions Welcome!
- 🐛 **Bug reports** - Found an issue? Please open an issue with details!
- 💡 **Feature suggestions** - Have ideas? Let's discuss them in discussions!
- 🔀 **Pull requests** - Improvements, fixes, and new features are always welcome!
- 📖 **Documentation** - Help make it clearer for others
- 🧪 **Testing** - More test coverage and edge cases are always valuable
- 🎨 **Code improvements** - Refactoring, optimization, better error handling

### 👥 Community Guidelines
- Be respectful and constructive in all interactions
- Test your changes thoroughly with `./dev-test.sh fresh`
- Follow existing code style and patterns in the codebase
- Update documentation when adding or changing features
- Include test cases for new functionality when possible

### 🚀 Development Workflow
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes and test thoroughly
4. Ensure all 31 tests pass: `./dev-test.sh fresh`
5. Commit with a descriptive message
6. Push to your branch and create a Pull Request

This project benefits from community input while maintaining its hobby project spirit. Your contributions help make it better for everyone in the self-hosting community!

**💬 Questions or Ideas?** Start a [Discussion](https://github.com/zuptalo/docker-stack-backup/discussions) - I'd love to hear how you're using this tool and what improvements would help you most.

## 📄 License

This project is open source and available under the MIT License.