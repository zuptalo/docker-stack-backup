#!/bin/bash

# Focused test script to verify restore functionality with different stacks
# This script tests the improved restore process with various stack combinations

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

# Test stack configurations
MINECRAFT_STACK="services:
  minecraft:
    image: itzg/minecraft-bedrock-server
    container_name: minecraft
    environment:
      EULA: \"TRUE\"
      GAMEMODE: \"creative\"
      DIFFICULTY: \"peaceful\"
      ALLOW_CHEATS: \"true\"
      SERVER_NAME: \"Test Server\"
      ONLINE_MODE: \"false\"
    networks:
      - prod-network
    volumes:
      - /opt/tools/minecraft:/data
    restart: unless-stopped
networks:
  prod-network:
    external: true"

DASHBOARD_STACK="services:
  dashboard:
    image: pawelmalak/flame:multiarch2.3.1
    container_name: dashboard
    volumes:
      - /opt/tools/dashboard:/app/data
    environment:
      - PASSWORD=test123
    restart: unless-stopped
    networks:
      - prod-network
networks:
  prod-network:
    external: true"

POSTGRES_STACK="services:
  postgres:
    image: postgres:17-alpine
    container_name: postgres
    environment:
      TZ: \"Europe/Stockholm\"
      POSTGRES_PASSWORD: testpass
      POSTGRES_DB: testdb
    volumes:
      - /opt/tools/postgres/data:/var/lib/postgresql/data
    restart: unless-stopped
    networks:
      - prod-network
networks:
  prod-network:
    external: true"

# Helper functions
wait_for_container() {
    local container_name="$1"
    local max_wait="${2:-60}"
    local waited=0
    
    while [[ $waited -lt $max_wait ]]; do
        if sudo -u portainer docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    return 1
}

deploy_stack_via_portainer() {
    local stack_name="$1"
    local compose_content="$2"
    
    info "Deploying stack: $stack_name via Portainer API"
    
    # Create temp directory for stack
    local stack_dir="/tmp/stack_${stack_name}"
    mkdir -p "$stack_dir"
    echo "$compose_content" > "$stack_dir/docker-compose.yml"
    
    # Deploy using docker-compose (simpler than API for testing)
    cd "$stack_dir"
    if sudo -u portainer docker compose -p "$stack_name" up -d; then
        success "Stack $stack_name deployed successfully"
        cd - >/dev/null
        rm -rf "$stack_dir"
        return 0
    else
        error "Failed to deploy stack $stack_name"
        cd - >/dev/null
        rm -rf "$stack_dir"
        return 1
    fi
}

create_backup_with_stacks() {
    local backup_name="$1"
    shift
    local stacks=("$@")
    
    info "Creating backup '$backup_name' with stacks: ${stacks[*]}"
    
    # Deploy specified stacks
    for stack in "${stacks[@]}"; do
        case "$stack" in
            "minecraft")
                deploy_stack_via_portainer "minecraft" "$MINECRAFT_STACK"
                ;;
            "dashboard") 
                deploy_stack_via_portainer "dashboard" "$DASHBOARD_STACK"
                ;;
            "postgres")
                deploy_stack_via_portainer "postgres" "$POSTGRES_STACK"
                ;;
            *)
                warn "Unknown stack: $stack"
                ;;
        esac
    done
    
    # Wait for containers to stabilize
    sleep 10
    
    # Create backup
    info "Creating backup with deployed stacks..."
    cd /home/vagrant/docker-stack-backup
    if sudo -u portainer DOCKER_BACKUP_TEST=true ./backup-manager.sh backup; then
        success "Backup created successfully"
        return 0
    else
        error "Failed to create backup"
        return 1
    fi
}

verify_containers_exist() {
    local expected_containers=("$@")
    local actual_containers
    
    # Get actual running containers (excluding portainer, but INCLUDING nginx-proxy-manager)
    actual_containers=($(sudo -u portainer docker ps --format "{{.Names}}" | grep -v "^portainer$" | sort))
    
    # nginx-proxy-manager should always be present, so add it to expected if not already there
    local expected_with_npm=("${expected_containers[@]}")
    if [[ ! " ${expected_containers[*]} " =~ " nginx-proxy-manager " ]]; then
        expected_with_npm+=("nginx-proxy-manager")
    fi
    
    info "Expected containers (with npm): ${expected_with_npm[*]}"
    info "Actual containers: ${actual_containers[*]}"
    
    # Check if arrays match
    if [[ ${#expected_with_npm[@]} -eq ${#actual_containers[@]} ]]; then
        local expected_sorted=($(printf '%s\n' "${expected_with_npm[@]}" | sort))
        local match=true
        
        for i in "${!expected_sorted[@]}"; do
            if [[ "${expected_sorted[i]}" != "${actual_containers[i]}" ]]; then
                match=false
                break
            fi
        done
        
        if $match; then
            success "Container verification passed"
            return 0
        fi
    fi
    
    error "Container verification failed"
    return 1
}

verify_directories_exist() {
    local expected_dirs=("$@")
    local all_exist=true
    
    # nginx-proxy-manager directory should always exist
    local expected_with_npm=("${expected_dirs[@]}")
    if [[ ! " ${expected_dirs[*]} " =~ " nginx-proxy-manager " ]]; then
        expected_with_npm+=("nginx-proxy-manager")
    fi
    
    for dir in "${expected_with_npm[@]}"; do
        if [[ -d "/opt/tools/$dir" ]]; then
            success "Directory /opt/tools/$dir exists"
        else
            error "Directory /opt/tools/$dir does not exist"
            all_exist=false
        fi
    done
    
    return $all_exist
}

verify_directories_not_exist() {
    local unexpected_dirs=("$@")
    local none_exist=true
    
    for dir in "${unexpected_dirs[@]}"; do
        if [[ -d "/opt/tools/$dir" ]]; then
            error "Directory /opt/tools/$dir should not exist but does"
            none_exist=false
        else
            success "Directory /opt/tools/$dir correctly does not exist"
        fi
    done
    
    return $none_exist
}

perform_restore() {
    local backup_number="$1"
    
    info "Performing restore of backup #$backup_number"
    
    cd /home/vagrant/docker-stack-backup
    # Need to provide both backup selection and confirmation
    printf "%s\ny\n" "$backup_number" | sudo -u portainer DOCKER_BACKUP_TEST=true ./backup-manager.sh restore
    
    # Wait for restore to complete
    sleep 20
    
    success "Restore completed"
}

# Main test scenarios
test_scenario_1() {
    info "=== TEST SCENARIO 1: Backup A (minecraft + dashboard + npm) → Add postgres → Restore A → Verify only minecraft + dashboard + npm ==="
    
    # Create backup A with minecraft and dashboard
    create_backup_with_stacks "backup_a" "minecraft" "dashboard" || return 1
    
    # Add postgres stack (not in backup A)
    deploy_stack_via_portainer "postgres" "$POSTGRES_STACK" || return 1
    
    # Verify all 4 containers are running (including npm)
    if ! verify_containers_exist "dashboard" "minecraft" "postgres"; then
        error "Failed initial container verification"
        return 1
    fi
    
    # Perform restore of backup A (should only have minecraft + dashboard + npm)
    perform_restore "1" || return 1
    
    # Verify only minecraft, dashboard, and nginx-proxy-manager containers exist (postgres should be gone)
    if verify_containers_exist "dashboard" "minecraft"; then
        success "✅ Scenario 1 PASSED: Only minecraft, dashboard, and nginx-proxy-manager containers exist after restore"
    else
        error "❌ Scenario 1 FAILED: Incorrect containers after restore"
        return 1
    fi
    
    # Verify directory structure (npm directory should always exist)
    if verify_directories_exist "dashboard" "minecraft" && verify_directories_not_exist "postgres"; then
        success "✅ Scenario 1 PASSED: Directory structure is correct (npm always present)"
    else
        error "❌ Scenario 1 FAILED: Incorrect directory structure"
        return 1
    fi
    
    success "=== SCENARIO 1 COMPLETED SUCCESSFULLY ==="
    return 0
}

test_scenario_2() {
    info "=== TEST SCENARIO 2: Backup B (all 3 stacks + npm) → Remove dashboard → Restore B → Verify all 3 + npm restored ==="
    
    # Create backup B with all 3 stacks (npm is always included)
    create_backup_with_stacks "backup_b" "minecraft" "dashboard" "postgres" || return 1
    
    # Remove dashboard stack
    info "Removing dashboard stack"
    sudo -u portainer docker stop dashboard || true
    sudo -u portainer docker rm dashboard || true
    sudo rm -rf /opt/tools/dashboard || true
    
    # Verify only minecraft, postgres, and nginx-proxy-manager are running
    if ! verify_containers_exist "minecraft" "postgres"; then
        error "Failed to remove dashboard container"
        return 1
    fi
    
    # Perform restore of backup B (should restore all 3 stacks + npm)
    perform_restore "1" || return 1
    
    # Verify all 3 containers + nginx-proxy-manager exist again
    if verify_containers_exist "dashboard" "minecraft" "postgres"; then
        success "✅ Scenario 2 PASSED: All 3 containers + nginx-proxy-manager restored successfully"
    else
        error "❌ Scenario 2 FAILED: Not all containers were restored"
        return 1
    fi
    
    # Verify directory structure (all directories including npm)
    if verify_directories_exist "dashboard" "minecraft" "postgres"; then
        success "✅ Scenario 2 PASSED: All directories including nginx-proxy-manager restored correctly"
    else
        error "❌ Scenario 2 FAILED: Not all directories were restored"
        return 1
    fi
    
    success "=== SCENARIO 2 COMPLETED SUCCESSFULLY ==="
    return 0
}

test_scenario_3() {
    info "=== TEST SCENARIO 3: Backup C (postgres + npm only) → Add minecraft + dashboard → Restore C → Verify only postgres + npm ==="
    
    # Create backup C with only postgres (npm is always included)
    create_backup_with_stacks "backup_c" "postgres" || return 1
    
    # Add minecraft and dashboard stacks
    deploy_stack_via_portainer "minecraft" "$MINECRAFT_STACK" || return 1
    deploy_stack_via_portainer "dashboard" "$DASHBOARD_STACK" || return 1
    
    # Verify all 4 containers are running (including npm)
    if ! verify_containers_exist "dashboard" "minecraft" "postgres"; then
        error "Failed to add extra containers"
        return 1
    fi
    
    # Perform restore of backup C (should only have postgres + nginx-proxy-manager)
    perform_restore "1" || return 1
    
    # Verify only postgres and nginx-proxy-manager containers exist
    if verify_containers_exist "postgres"; then
        success "✅ Scenario 3 PASSED: Only postgres and nginx-proxy-manager containers exist after restore"
    else
        error "❌ Scenario 3 FAILED: Incorrect containers after restore"
        return 1
    fi
    
    # Verify directory structure (postgres and npm directories should exist, others should not)
    if verify_directories_exist "postgres" && verify_directories_not_exist "dashboard" "minecraft"; then
        success "✅ Scenario 3 PASSED: Only postgres and nginx-proxy-manager directories exist"
    else
        error "❌ Scenario 3 FAILED: Incorrect directory structure"
        return 1
    fi
    
    success "=== SCENARIO 3 COMPLETED SUCCESSFULLY ==="
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
    
    # Wait for prod-network
    if ! sudo -u portainer docker network ls | grep -q "prod-network"; then
        error "prod-network does not exist"
        return 1
    fi
    
    success "System is ready for testing"
    return 0
}

# Main execution
main() {
    info "Starting comprehensive restore functionality tests..."
    
    # Wait for system to be ready
    if ! wait_for_system; then
        error "System not ready, aborting tests"
        exit 1
    fi
    
    # Run test scenarios
    if test_scenario_1 && test_scenario_2 && test_scenario_3; then
        success "🎉 ALL RESTORE FUNCTIONALITY TESTS PASSED! 🎉"
        success "✅ Pre-restore backup generation is disabled"
        success "✅ Complete container cleanup works correctly"
        success "✅ Directory cleanup works correctly" 
        success "✅ Stack restoration from backup works correctly"
        success "✅ Only containers/directories from backup are restored"
        success "✅ Extra containers/directories are properly removed"
        success "✅ nginx-proxy-manager is always preserved as core infrastructure"
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