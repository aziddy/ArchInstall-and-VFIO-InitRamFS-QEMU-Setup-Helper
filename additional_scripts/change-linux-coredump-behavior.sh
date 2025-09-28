#!/bin/bash

# Change Linux Core Dump Behavior Script
# This script allows you to disable core dumps completely or set a specific GB limit
# Based on "Prevent Crashing on Hard Workloads QEMU Windows VM.md" section

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to check current core dump settings
check_current_settings() {
    print_status "Current core dump settings:"
    echo
    
    # Check limits.conf
    if grep -q "core" /etc/security/limits.conf 2>/dev/null; then
        print_status "Current limits.conf core settings:"
        grep "core" /etc/security/limits.conf | grep -v "^#" || echo "  No core settings found"
    else
        print_status "No core settings found in limits.conf"
    fi
    
    echo
    
    # Check systemd core dump settings
    if systemctl is-active systemd-coredump &>/dev/null; then
        print_status "systemd-coredump service status:"
        systemctl is-active systemd-coredump
        echo
        print_status "Current systemd core dump configuration:"
        cat /etc/systemd/coredump.conf 2>/dev/null | grep -E "^(Storage|Compress|ProcessSizeMax|ExternalSizeMax|JournalSizeMax|MaxUse|KeepFree)" | grep -v "^#" || echo "  Using default settings"
    else
        print_warning "systemd-coredump service not active"
    fi
    
    echo
}

# Function to check if core dump settings are already applied
check_existing_settings() {
    local action="$1"
    local limit="$2"
    
    if [[ "$action" == "disable" ]]; then
        if grep -q "^\* hard core 0" /etc/security/limits.conf 2>/dev/null; then
            print_warning "Core dumps are already disabled in limits.conf"
            return 0
        fi
    elif [[ "$action" == "limit" ]]; then
        local expected_limit=$((limit * 1024))  # Convert GB to KB
        if grep -q "^\* hard core $expected_limit" /etc/security/limits.conf 2>/dev/null; then
            print_warning "Core dump limit is already set to ${limit}GB in limits.conf"
            return 0
        fi
    fi
    
    return 1
}

# Function to disable core dumps
disable_core_dumps() {
    print_status "Disabling core dumps..."
    
    # Check if already disabled
    if check_existing_settings "disable" 0; then
        print_warning "Core dumps are already disabled. No changes needed."
        return 0
    fi
    
    # Remove any existing core settings
    print_status "Removing existing core dump settings..."
    sed -i '/^\* hard core/d' /etc/security/limits.conf
    
    # Add disable setting
    print_status "Adding core dump disable setting..."
    echo '* hard core 0' >> /etc/security/limits.conf
    
    # Disable systemd-coredump service
    print_status "Disabling systemd-coredump service..."
    systemctl mask systemd-coredump.service &>/dev/null || true
    systemctl stop systemd-coredump.service &>/dev/null || true
    
    print_success "Core dumps have been disabled"
    print_status "Changes applied:"
    print_status "  - Added '* hard core 0' to /etc/security/limits.conf"
    print_status "  - Disabled systemd-coredump service"
}

# Function to set core dump limit
set_core_dump_limit() {
    local limit_gb="$1"
    local limit_kb=$((limit_gb * 1024))  # Convert GB to KB
    
    print_status "Setting core dump limit to ${limit_gb}GB (${limit_kb}KB)..."
    
    # Check if already set to this limit
    if check_existing_settings "limit" "$limit_gb"; then
        print_warning "Core dump limit is already set to ${limit_gb}GB. No changes needed."
        return 0
    fi
    
    # Remove any existing core settings
    print_status "Removing existing core dump settings..."
    sed -i '/^\* hard core/d' /etc/security/limits.conf
    
    # Add limit setting
    print_status "Adding core dump limit setting..."
    echo "* hard core $limit_kb" >> /etc/security/limits.conf
    
    # Enable systemd-coredump service with limits
    print_status "Configuring systemd-coredump service..."
    systemctl unmask systemd-coredump.service &>/dev/null || true
    
    # Create systemd-coredump configuration
    cat > /etc/systemd/coredump.conf << EOF
[Coredump]
Storage=external
Compress=yes
ProcessSizeMax=${limit_gb}G
ExternalSizeMax=${limit_gb}G
JournalSizeMax=${limit_gb}G
MaxUse=${limit_gb}G
KeepFree=${limit_gb}G
EOF
    
    systemctl restart systemd-coredump.service &>/dev/null || true
    
    print_success "Core dump limit has been set to ${limit_gb}GB"
    print_status "Changes applied:"
    print_status "  - Added '* hard core $limit_kb' to /etc/security/limits.conf"
    print_status "  - Configured systemd-coredump with ${limit_gb}GB limits"
}

# Function to show core dump information
show_core_dump_info() {
    echo
    print_status "Core Dump Information:"
    echo
    echo "What are core dumps?"
    echo "  - Core dumps are files created when a program crashes"
    echo "  - They contain the memory state of the program at the time of crash"
    echo "  - Useful for debugging but can consume significant disk space"
    echo
    echo "Why manage core dumps?"
    echo "  - Large core dumps can fill up disk space quickly"
    echo "  - In VFIO setups, crashes might generate very large core dumps"
    echo "  - Disabling or limiting them can prevent disk space issues"
    echo
    echo "Options:"
    echo "  - Disable completely: No core dumps will be created"
    echo "  - Set GB limit: Core dumps will be limited to specified size"
    echo
}

# Function to get user choice
get_user_choice() {
    while true; do
        echo
        echo "=========================================="
        echo "[INFO] Choose an option:"
        echo "=========================================="
        echo "  1. Disable core dumps completely"
        echo "  2. Set core dump size limit (in GB)"
        echo "  3. Show current settings only"
        echo "  4. Exit"
        echo "=========================================="
        echo
        
        read -p "Enter your choice (1-4): " choice
        case $choice in
            1)
                USER_CHOICE="disable"
                return
                ;;
            2)
                USER_CHOICE="limit"
                return
                ;;
            3)
                USER_CHOICE="show"
                return
                ;;
            4)
                USER_CHOICE="exit"
                return
                ;;
            *)
                print_error "Invalid choice. Please enter 1, 2, 3, or 4."
                ;;
        esac
    done
}

# Function to get limit size
get_limit_size() {
    while true; do
        read -p "Enter core dump size limit in GB (1-100): " limit
        
        if [[ "$limit" =~ ^[0-9]+$ ]]; then
            if [[ $limit -ge 1 && $limit -le 100 ]]; then
                echo "$limit"
                return
            else
                print_error "Please enter a number between 1 and 100"
            fi
        else
            print_error "Please enter a valid number"
        fi
    done
}

# Function to create backup
create_backup() {
    local backup_file="/etc/security/limits.conf.backup.$(date +%Y%m%d_%H%M%S)"
    
    if cp /etc/security/limits.conf "$backup_file" 2>/dev/null; then
        print_status "Created backup: $backup_file"
        return 0
    else
        print_warning "Could not create backup of limits.conf"
        return 1
    fi
}

# Main function
main() {
    echo "=========================================="
    echo "Change Linux Core Dump Behavior Script"
    echo "=========================================="
    echo
    
    check_root
    
    show_core_dump_info
    
    # Show current settings
    check_current_settings
    
    # Clear separator before showing options
    echo "=========================================="
    echo
    
    # Get user choice
    get_user_choice
    local choice="$USER_CHOICE"
    
    case $choice in
        "disable")
            create_backup
            disable_core_dumps
            ;;
        "limit")
            local limit_size
            limit_size=$(get_limit_size)
            create_backup
            set_core_dump_limit "$limit_size"
            ;;
        "show")
            print_status "Current settings displayed above"
            exit 0
            ;;
        "exit")
            print_status "Exiting without changes"
            exit 0
            ;;
    esac
    
    echo
    print_success "Core dump configuration completed!"
    echo
    print_status "Note: Changes to limits.conf take effect for new login sessions"
    print_status "You may need to log out and log back in for changes to take effect"
    print_status "For immediate effect, you can run: ulimit -c <new_limit>"
}

# Run main function
main "$@"
