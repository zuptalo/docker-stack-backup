# Docker Stack Backup

**Single-script solution for transforming Ubuntu LTS servers into production-ready Docker environments with automated backup/restore capabilities.**

---

## 📋 Overview

- **What**: Self-contained bash script (~7400 lines) that manages Docker infrastructure lifecycle
- **Who**: Individual self-hosters with passwordless sudo access on Ubuntu servers
- **How**: Zero manual intervention - fully automated setup, backup, restore, and scheduling
- **Where**: Ubuntu 22.04/24.04 LTS (other versions may work but untested)

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

## 🚀 Quick Start

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

# Create a backup
sudo ./backup-manager.sh backup

# Restore from backup
sudo ./backup-manager.sh restore
```

## 🏗️ Architecture

### Single-Script Design
- **All functionality in one file**: `backup-manager.sh`
- **No external dependencies**: Only standard Ubuntu tools
- **Self-contained**: Handles installation through operation

### Three-Layer System
1. **Infrastructure Layer**: `/opt/{portainer,nginx-proxy-manager,tools,backup}`
2. **Network Layer**: Internal Docker network with nginx reverse proxy
3. **User/Permission Layer**: Dedicated `portainer` system user

### Key Features
- **Dual-preservation backup**: tar.gz archives + separate metadata for permissions
- **Portainer API integration**: Full stack state capture/restore
- **Graceful operations**: Proper container shutdown/restart sequences
- **Cross-architecture detection**: Warnings for incompatible restores
- **Remote NAS backup**: Self-contained SSH-based client script

## 📚 Documentation Map

- **[README.md](README.md)** ← You are here - Project overview & quick reference
- **[STATUS.md](STATUS.md)** - Detailed feature implementation status & testing coverage
- **[CLAUDE.md](CLAUDE.md)** - Claude Code specific instructions & development guidelines
- **[TESTING.md](TESTING.md)** - Testing infrastructure, procedures, and test writing guide

## 🧪 Development & Testing

**IMPORTANT**: All testing runs inside Vagrant VMs, not on host machine.

```bash
# Start test environment
vagrant up primary nas

# SSH into primary VM
vagrant ssh primary

# Run tests
cd docker-stack-backup
sudo ./tests/run-tests.sh

# Create/restore snapshots for faster testing
./tests/snapshot.sh create my-snapshot
./tests/snapshot.sh restore my-snapshot
```

See [TESTING.md](TESTING.md) for complete testing guide.

## 📖 Available Commands

```bash
./backup-manager.sh install            # Install system (detects existing installations)
./backup-manager.sh backup             # Create backup
./backup-manager.sh restore            # Interactive restore
./backup-manager.sh schedule           # Setup cron jobs
./backup-manager.sh update             # Self-update from GitHub
./backup-manager.sh generate-nas-script # Generate NAS backup client
./backup-manager.sh uninstall          # Complete system cleanup
./backup-manager.sh --help             # Show all commands

# Modify settings by editing:
sudo nano /etc/docker-backup-manager.conf
```

## 🔒 Security Considerations

- SSH keys stored in `/opt/backup/.ssh/` (portainer user)
- Credentials in `.credentials` files (git-ignored)
- Restricted sudo access for portainer user
- No external port exposure except 80/443 via nginx-proxy-manager
- All internal services communicate via Docker network

## 🤝 Contributing

This project uses AI-assisted development:
- **Claude Code**: Primary development assistant
- **Gemini/Other AI CLIs**: Should work with any AI assistant

When starting a new session, AI assistants should read:
1. README.md (this file) for project overview
2. STATUS.md for current implementation state
3. CLAUDE.md for development guidelines
4. TESTING.md for testing procedures

## 🔗 Links

- **GitHub Repository**: https://github.com/zuptalo/docker-stack-backup
- **Issue Tracker**: https://github.com/zuptalo/docker-stack-backup/issues

---

**Design Philosophy**: Safety First | Fully Automated | Production Ready | Self-Contained
