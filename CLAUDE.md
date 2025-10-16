now# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker Stack Backup is a **single-script solution** (backup-manager.sh, ~7900 lines) that transforms Ubuntu LTS servers into production-ready Docker environments with automated backup/restore capabilities. The entire system is self-contained in one bash script with zero external dependencies beyond standard Ubuntu packages.

**Target Users**: Individual self-hosters managing Ubuntu servers with **passwordless sudo** access.

**Design Goal**: **FULLY AUTOMATED** - No manual intervention required. The script handles everything from installation to periodic backups when run by a user with passwordless sudo access.

## Core Architecture

### Single-Script Design Philosophy
- All functionality in `backup-manager.sh` (VERSION tracked at line 8)
- Self-contained: Handles installation, configuration, backup, restore, scheduling, and updates
- No external dependencies: Uses only standard Ubuntu tools (docker, jq, curl, rsync, etc.)
- Test-driven via Vagrant VMs (not host system)

### Three-Layer System Architecture

1. **Infrastructure Layer** (`/opt/` structure)
   - `/opt/portainer/` - Portainer CE (container orchestration UI)
   - `/opt/nginx-proxy-manager/` - Reverse proxy with SSL
   - `/opt/tools/` - Additional Docker stacks
   - `/opt/backup/` - System backup storage and script copy

2. **Network Layer**
   - `prod-network`: External Docker network for all services
   - nginx-proxy-manager on ports 80/443 (only external exposure)
   - Internal routing via container names
   - DNS-based service discovery (subdomain.domain.com)

3. **User/Permission Layer**
   - `portainer` system user owns all Docker operations
   - Passwordless sudo for backup operations only
   - Docker group membership for container management
   - All services run under `portainer` user context

### Portainer API Integration

The script heavily uses Portainer API for:
- Stack state capture/restore (compose files, env vars, settings)
- Container lifecycle management
- Endpoint configuration
- All API calls at `http://localhost:9000/api/` (no external exposure)
- Credentials stored in `.credentials` files (git-ignored)

### Backup Strategy

**Dual-preservation approach** for reliability:
1. `tar.gz` archive with `--same-owner --same-permissions`
2. Separate metadata file for ownership/permissions verification
3. Stack state JSON (via Portainer API) embedded in archive
4. Graceful shutdown sequence (stop containers → backup → restart)
5. Cross-architecture detection and warnings

## Development Workflow

### CRITICAL: All testing runs inside Vagrant

Since development may occur on macOS/Windows, **ALL script execution and testing MUST happen inside the Vagrant VM**:

```bash
# Start VM
vagrant up

# SSH into VM
vagrant ssh

# Navigate to synced project
cd ~/docker-stack-backup

# Run tests/commands
sudo ./backup-manager.sh setup
sudo ./backup-manager.sh backup
```

**Never run the script directly on the host system** - it's designed for Ubuntu and will fail on other systems.

### Vagrant Environment

- **VM**: Ubuntu 22.04 (jammy64) at `192.168.56.10`
- **Synced folder**: Project root → `/home/vagrant/docker-stack-backup`
- **Port forwarding**:
  - 80/443: nginx-proxy-manager (HTTP/HTTPS)
  - 81: nginx-proxy-manager admin
  - 9000: Portainer
  - 22: SSH (for NAS backup testing)
- **Resources**: 3GB RAM, 2 CPUs
- **Provisioning**: Minimal (passwordless sudo only) - actual setup via script

### Common Commands

```bash
# === Primary Commands ===
./backup-manager.sh setup          # Initial system setup (run first)
./backup-manager.sh config         # Reconfigure settings
./backup-manager.sh backup         # Create backup
./backup-manager.sh restore        # Interactive restore
./backup-manager.sh schedule       # Setup cron jobs
./backup-manager.sh update         # Self-update from GitHub

# === Development/Testing ===
./backup-manager.sh --help                    # Show usage
./backup-manager.sh <command> --help          # Command-specific help
./backup-manager.sh --non-interactive setup   # CI/automation mode
./backup-manager.sh --config-file=path setup  # Config from file

# === Vagrant Operations ===
vagrant up                         # Start VM
vagrant ssh                        # SSH into VM
vagrant halt                       # Stop VM
vagrant destroy                    # Delete VM
vagrant provision                  # Re-run provisioning
```

### Testing Infrastructure

The script is designed for comprehensive integration testing:
- Full VM lifecycle testing (clean Ubuntu → production ready)
- Real Docker deployments (not mocked)
- Actual API calls to Portainer/NPM
- SSH connectivity tests for NAS backup
- Architecture compatibility validation

**Test Environment Detection**: Script detects test mode via domain patterns (`*.local`) and adjusts behavior (skips DNS checks, uses HTTP fallback).

## Key Code Sections

### Main Entry Point
- Line 7700-7900: Command dispatcher and argument parsing
- Line 6930-7000: `usage()` function with help text
- Line 0-100: Configuration constants and defaults

### Core Operations
- `interactive_setup_configuration()`: Configuration collection (line ~1158)
- `validate_*` functions: System state validation (lines 313-683)
- Backup/restore functions use Portainer API for stack state
- SSH key management for NAS remote backup integration

### Logging & Error Handling
- Line 66-111: Logging functions (`log()`, `info()`, `warn()`, `error()`, `success()`)
- Line 721: `die()` function for fatal errors
- All output uses color coding (RED, GREEN, YELLOW, BLUE, NC)
- Logs to `/var/log/docker-backup-manager.log` with permission handling

### Configuration Management
- Default config: Lines 13-39
- Config file: `/etc/docker-backup-manager.conf`
- Non-interactive mode: Environment variables (`NON_INTERACTIVE`, `AUTO_YES`, `QUIET_MODE`)
- Test vs. production environment detection

## Release Process

- **Versioning**: UTC timestamp format `YYYY.MM.DD.HHMM` (line 8)
- **CI/CD**: GitHub Actions on push to main (`.github/workflows/release.yml`)
- **Auto-release**: Version auto-incremented, tagged, and released
- **Update mechanism**: Script self-updates from GitHub releases

## File Structure Notes

```
backup-manager.sh       # Single monolithic script (~7900 lines)
Vagrantfile            # VM configuration for testing
REQUIREMENTS.md        # Complete project specification
.claude/               # Claude Code settings
.vagrant/              # Vagrant VM state (git-ignored)
.github/workflows/     # CI/CD automation
```

## Important Implementation Notes

1. **Always preserve bash safety flags**: `set -euo pipefail` at line 2
2. **User context matters**: Most operations run as `portainer` user via `sudo -u portainer`
3. **API authentication**: Portainer requires JWT tokens (obtained via `/auth` endpoint)
4. **Graceful degradation**: Script handles missing dependencies, offline mode, etc.
5. **Permission preservation**: Critical for Docker volume ownership
6. **Color output**: Conditional based on terminal capabilities (lines 42-63)
7. **Cron compatibility**: Script handles both interactive and cron execution contexts

## Configuration File Format

```bash
# /etc/docker-backup-manager.conf
DOMAIN_NAME="example.com"
PORTAINER_SUBDOMAIN="pt"
NPM_SUBDOMAIN="npm"
PORTAINER_PATH="/opt/portainer"
NPM_PATH="/opt/nginx-proxy-manager"
TOOLS_PATH="/opt/tools"
BACKUP_PATH="/opt/backup"
BACKUP_RETENTION=7
REMOTE_RETENTION=30
```

## Security Considerations

- SSH keys for NAS backup stored in `/opt/backup/.ssh/`
- Credentials in `.credentials` files (never committed)
- Portainer user has restricted sudo (backup operations only)
- No external port exposure except 80/443 via nginx-proxy-manager
- All internal services communicate via Docker network

## Version Control

- **Main branch**: Production-ready code
- **Current branch**: `separate-the-tests-to-separate-files-for-each-functionality`
- Git status shows clean working tree
- CI runs on main branch pushes only
