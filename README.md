# Docker Stack Backup

[![Create Release on Push to Main](https://github.com/zuptalo/docker-stack-backup/actions/workflows/release.yml/badge.svg)](https://github.com/zuptalo/docker-stack-backup/actions/workflows/release.yml)
[![Latest Release](https://img.shields.io/github/v/release/zuptalo/docker-stack-backup)](https://github.com/zuptalo/docker-stack-backup/releases/latest)

Single-script solution to transform any Ubuntu LTS server into a production-ready Docker environment with automated backup, restore, and management capabilities for self-hosters.

## 🎯 Project Status

**Last Updated**: 2025-11-02
**Version**: See `backup-manager.sh` line 8

### Implementation Status

| Category | Status | Notes |
|----------|--------|-------|
| Core Infrastructure | ✅ Complete | Docker, Portainer CE, nginx-proxy-manager |
| Local Backup/Restore | ✅ Complete | Dual-preservation (tar + metadata) |
| Remote NAS Backup | ✅ Complete | SSH-based with self-contained client script |
| Cron Scheduling | ✅ Complete | Automated periodic backups |
| Self-Update | ✅ Complete | GitHub release integration |
| Testing Suite | ✅ Complete | 53 tests across 16 categories |
| Documentation | ✅ Complete | Agent-agnostic structure complete |

**See [STATUS.md](STATUS.md) for detailed feature tracking.**

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

## 🚀 Quick Start

### Production Deployment

```bash
# Download latest release
curl -fsSL https://raw.githubusercontent.com/zuptalo/docker-stack-backup/main/backup-manager.sh -o backup-manager.sh
chmod +x backup-manager.sh

# Run initial setup
./backup-manager.sh setup
```

### Development & Testing

```bash
# Clone the repository
git clone https://github.com/zuptalo/docker-stack-backup.git
cd docker-stack-backup

# For testing/development (uses Vagrant VMs)
vagrant up primary
vagrant ssh primary
cd docker-stack-backup

# Install (detects existing installations automatically)
sudo ./backup-manager.sh install
```

## 📚 Documentation Map

- **[README.md](README.md)** ← You are here - Project overview & quick reference
- **[STATUS.md](STATUS.md)** - Detailed feature implementation status & testing coverage
- **[tests/TESTING.md](tests/TESTING.md)** - Complete guide to the testing infrastructure, procedures, and writing tests.

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

The project includes a comprehensive Vagrant-based testing environment that provides **enterprise-grade testing** in a **realistic environment**. See [tests/TESTING.md](tests/TESTING.md) for a complete guide.

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

**💬 Questions or Ideas?** Start a [Discussion](https://github.com/zuptalo/docker-stack-backup/discussions) - I'd love to hear how you're using this tool and what improvements would help you most.

## 📄 License

This project is open source and available under the MIT License.