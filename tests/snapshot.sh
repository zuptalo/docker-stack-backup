#!/bin/bash
# Vagrant Snapshot Management Script
# Manages VM snapshots for different test states

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VM_NAME="primary"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Print usage
usage() {
    cat << EOF
Usage: $0 <command> [snapshot-name]

COMMANDS:
    create <name>       Create a new snapshot
    restore <name>      Restore to a snapshot
    list                List all snapshots
    delete <name>       Delete a snapshot
    init                Create all base snapshots

BASE SNAPSHOTS:
    base-clean              Fresh Ubuntu 22.04 (after vagrant up)
    base-prepared           System packages installed (after tests 01-02)
    docker-ready            Docker installed and configured (after tests 01-03)
    full-stack-ready        Complete stack deployed (after setup complete)
    backup-created          First backup created (after backup command)

EXAMPLES:
    $0 list                     # List all snapshots
    $0 create base-clean        # Create base-clean snapshot
    $0 restore base-clean       # Restore to base-clean
    $0 init                     # Create all base snapshots
    $0 delete test-snapshot     # Delete a snapshot

EOF
}

# Check if vagrant is available
check_vagrant() {
    if ! command -v vagrant >/dev/null 2>&1; then
        printf "${RED}✗ Vagrant not found${NC}\n"
        printf "  Install Vagrant: https://www.vagrantup.com/downloads\n"
        exit 1
    fi
}

# Check if VM is running
check_vm_running() {
    cd "$PROJECT_ROOT"
    if ! vagrant status "$VM_NAME" 2>/dev/null | grep -q "running"; then
        printf "${RED}✗ VM is not running${NC}\n"
        printf "  Start VM: vagrant up\n"
        exit 1
    fi
}

# Create snapshot
create_snapshot() {
    local snapshot_name="$1"

    printf "${BLUE}Creating snapshot: %s${NC}\n" "$snapshot_name"

    cd "$PROJECT_ROOT"
    if vagrant snapshot save "$VM_NAME" "$snapshot_name" 2>&1; then
        printf "${GREEN}✓ Snapshot created successfully${NC}\n"
    else
        printf "${RED}✗ Failed to create snapshot${NC}\n"
        exit 1
    fi
}

# Restore snapshot
restore_snapshot() {
    local snapshot_name="$1"

    printf "${BLUE}Restoring snapshot: %s${NC}\n" "$snapshot_name"

    cd "$PROJECT_ROOT"
    if vagrant snapshot restore "$VM_NAME" "$snapshot_name" --no-provision 2>&1; then
        printf "${GREEN}✓ Snapshot restored successfully${NC}\n"
    else
        printf "${RED}✗ Failed to restore snapshot${NC}\n"
        exit 1
    fi
}

# List snapshots
list_snapshots() {
    printf "${BLUE}Available snapshots:${NC}\n\n"

    cd "$PROJECT_ROOT"
    vagrant snapshot list "$VM_NAME" 2>&1 | grep -v "==>" | sed 's/^/  /'
}

# Delete snapshot
delete_snapshot() {
    local snapshot_name="$1"

    printf "${BLUE}Deleting snapshot: %s${NC}\n" "$snapshot_name"

    cd "$PROJECT_ROOT"
    if vagrant snapshot delete "$VM_NAME" "$snapshot_name" 2>&1; then
        printf "${GREEN}✓ Snapshot deleted successfully${NC}\n"
    else
        printf "${RED}✗ Failed to delete snapshot${NC}\n"
        exit 1
    fi
}

# Initialize all base snapshots
init_base_snapshots() {
    printf "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${CYAN}║${NC}  Initializing Base Snapshots                                  ${CYAN}║${NC}\n"
    printf "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}\n\n"

    printf "${YELLOW}This will create the following snapshots:${NC}\n"
    printf "  1. base-clean          - Fresh Ubuntu 22.04\n"
    printf "  2. base-prepared       - System packages installed\n"
    printf "  3. docker-ready        - Docker installed and configured\n"
    printf "  4. full-stack-ready    - Complete stack deployed\n"
    printf "  5. backup-created      - First backup created\n\n"

    printf "${YELLOW}⚠ This process will take 15-30 minutes${NC}\n"
    printf "${YELLOW}⚠ The VM will be modified during this process${NC}\n\n"

    read -p "Continue? (y/n) " -n 1 -r
    printf "\n"
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        printf "${YELLOW}Cancelled${NC}\n"
        exit 0
    fi

    # Ensure VM is running
    cd "$PROJECT_ROOT"
    printf "\n${BLUE}Step 1/5: Starting VM...${NC}\n"
    vagrant up

    # Create base-clean snapshot
    printf "\n${BLUE}Step 2/5: Creating base-clean snapshot...${NC}\n"
    create_snapshot "base-clean"

    # Install system packages
    printf "\n${BLUE}Step 3/5: Installing system packages...${NC}\n"
    vagrant ssh -c "sudo apt-get update && sudo apt-get install -y curl jq dnsutils rsync net-tools" 2>&1 | tail -5
    create_snapshot "base-prepared"

    # Install Docker
    printf "\n${BLUE}Step 4/5: Installing Docker...${NC}\n"
    vagrant ssh -c "cd ~/docker-stack-backup && sudo ./backup-manager.sh --non-interactive --yes install_dependencies 2>&1 | tail -10" || true
    # Check if Docker is installed
    if vagrant ssh -c "command -v docker" >/dev/null 2>&1; then
        printf "${GREEN}✓ Docker installed${NC}\n"
        create_snapshot "docker-ready"
    else
        printf "${YELLOW}⚠ Docker installation may need manual verification${NC}\n"
        printf "${YELLOW}  You can manually install Docker and create docker-ready snapshot${NC}\n"
    fi

    # Full stack and backup snapshots (manual)
    printf "\n${BLUE}Step 5/5: Remaining snapshots${NC}\n"
    printf "${YELLOW}The following snapshots require manual creation:${NC}\n"
    printf "  1. full-stack-ready - After running: sudo ./backup-manager.sh install\n"
    printf "     Create with: ./tests/snapshot.sh create full-stack-ready\n"
    printf "  2. backup-created - After running: sudo ./backup-manager.sh backup\n"
    printf "     Create with: ./tests/snapshot.sh create backup-created\n\n"

    printf "${GREEN}✓ Base snapshots created successfully${NC}\n"
    printf "${CYAN}Available snapshots:${NC}\n"
    list_snapshots
}

# Main execution
main() {
    local command="${1:-}"

    if [[ -z "$command" ]]; then
        usage
        exit 1
    fi

    check_vagrant

    case "$command" in
        create)
            local snapshot_name="${2:-}"
            if [[ -z "$snapshot_name" ]]; then
                printf "${RED}✗ Snapshot name required${NC}\n"
                usage
                exit 1
            fi
            check_vm_running
            create_snapshot "$snapshot_name"
            ;;
        restore)
            local snapshot_name="${2:-}"
            if [[ -z "$snapshot_name" ]]; then
                printf "${RED}✗ Snapshot name required${NC}\n"
                usage
                exit 1
            fi
            restore_snapshot "$snapshot_name"
            ;;
        list)
            list_snapshots
            ;;
        delete)
            local snapshot_name="${2:-}"
            if [[ -z "$snapshot_name" ]]; then
                printf "${RED}✗ Snapshot name required${NC}\n"
                usage
                exit 1
            fi
            delete_snapshot "$snapshot_name"
            ;;
        init)
            init_base_snapshots
            ;;
        help|--help|-h)
            usage
            exit 0
            ;;
        *)
            printf "${RED}✗ Unknown command: %s${NC}\n" "$command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
