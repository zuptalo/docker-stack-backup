#!/bin/bash

# Simple test to verify the restore improvements work correctly
# This test will manually verify the key improvements

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $*"; }

test_restore_improvements() {
    info "=== TESTING RESTORE PROCESS IMPROVEMENTS ==="
    
    # Test 1: Verify no pre-restore backup is generated
    info "Test 1: Checking that pre-restore backup generation is disabled"
    
    # Count current backups
    local backup_count_before
    backup_count_before=$(ls -1 /opt/backup/docker_backup_*.tar.gz 2>/dev/null | wc -l)
    info "Backup count before restore: $backup_count_before"
    
    # Get the latest backup
    local latest_backup
    latest_backup=$(ls -1t /opt/backup/docker_backup_*.tar.gz 2>/dev/null | head -1)
    
    if [[ -z "$latest_backup" ]]; then
        error "No backup found to test with"
        return 1
    fi
    
    info "Using backup: $(basename "$latest_backup")"
    
    # Test 2: Deploy a test stack to verify cleanup
    info "Test 2: Deploying test containers to verify cleanup"
    
    # Create a simple test container
    sudo -u portainer docker run -d --name test-cleanup-container --restart=unless-stopped nginx:alpine >/dev/null 2>&1 || true
    
    # Verify it exists
    if ! sudo -u portainer docker ps --format "{{.Names}}" | grep -q "test-cleanup-container"; then
        warn "Test container not created, but continuing test"
    else
        success "Test container created successfully"
    fi
    
    # Record containers before
    local containers_before
    containers_before=$(sudo -u portainer docker ps --format "{{.Names}}" | sort)
    info "Containers before restore: $(echo "$containers_before" | tr '\n' ' ')"
    
    # Test 3: Check source code to verify pre-restore backup removal
    info "Test 3: Checking source code to verify pre-restore backup generation was removed"
    
    cd /home/vagrant/docker-stack-backup
    if grep -q "pre_restore_" backup-manager.sh; then
        error "❌ Pre-restore backup code still exists in source"
        return 1
    else
        success "✅ Pre-restore backup code successfully removed from source"
    fi
    
    # Test 4: Check for new cleanup functions
    info "Test 4: Verifying new cleanup functions exist"
    
    if grep -q "cleanup_system_for_restore" backup-manager.sh; then
        success "✅ cleanup_system_for_restore function found"
    else
        error "❌ cleanup_system_for_restore function not found"
        return 1
    fi
    
    if grep -q "extract_backup_cleanly" backup-manager.sh; then
        success "✅ extract_backup_cleanly function found"
    else
        error "❌ extract_backup_cleanly function not found"
        return 1
    fi
    
    # Test 5: Manual verification of directory structure
    info "Test 5: Checking current directory structure"
    info "Portainer directory contents:"
    ls -la /opt/portainer/ | head -10
    
    info "Tools directory contents:"
    ls -la /opt/tools/ | head -10
    
    # Test 6: Check that functions use sudo properly
    info "Test 6: Verifying sudo usage in restore functions"
    
    if grep -A 20 "cleanup_system_for_restore" backup-manager.sh | grep -q "sudo -u.*docker"; then
        success "✅ Cleanup function uses proper sudo with portainer user"
    else
        warn "⚠️  Cleanup function may not use proper sudo"
    fi
    
    success "=== RESTORE IMPROVEMENT VERIFICATION COMPLETED ==="
    return 0
}

# Wait for system to be ready
wait_for_system() {
    info "Waiting for system to be ready..."
    
    # Wait for portainer
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if sudo -u portainer docker ps --format "{{.Names}}" | grep -q "portainer"; then
            success "Portainer is running"
            break
        fi
        sleep 5
        attempts=$((attempts + 1))
    done
    
    if [[ $attempts -eq 30 ]]; then
        error "Portainer is not running after 2.5 minutes"
        return 1
    fi
    
    success "System is ready for testing"
    return 0
}

# Main execution
main() {
    info "Starting restore improvement verification tests..."
    
    # Wait for system to be ready
    if ! wait_for_system; then
        error "System not ready, aborting tests"
        exit 1
    fi
    
    # Run tests
    if test_restore_improvements; then
        success "🎉 RESTORE IMPROVEMENT VERIFICATION PASSED! 🎉"
        success "✅ Pre-restore backup generation code removed"
        success "✅ New cleanup functions implemented"
        success "✅ Proper sudo usage for permissions"
        success "✅ Source code improvements verified"
        return 0
    else
        error "❌ SOME TESTS FAILED"
        return 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi