#!/bin/bash

# CPU Pinning GRUB Configuration Script for AMD 7800X3D (6 Cores, SMT OFF)
# Based on "Prevent Crashing on Hard Workloads QEMU Windows VM.md" section 5 - Option 5.A
# This script configures GRUB parameters for CPU pinning on AMD 7800X3D with SMT/Hyperthreading disabled

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# CPU pinning parameters for 7800X3D (6 cores, SMT OFF)
CPU_PINNING_PARAMS="isolcpus=2-7 nohz_full=2-7 rcu_nocbs=2-7"

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

# Function to show CPU pinning information
show_cpu_pinning_info() {
    echo
    print_status "CPU Pinning Information for AMD 7800X3D (6 Cores, SMT OFF):"
    echo
    echo "What is CPU Pinning?"
    echo "  - Assigns specific CPU cores exclusively to your VM"
    echo "  - Prevents host system processes from interrupting VM execution"
    echo "  - Improves VM performance and reduces latency for gaming"
    echo
    echo "Configuration for 7800X3D (6 cores, SMT OFF):"
    echo "  - Cores 0-1: Host OS + QEMU emulator"
    echo "  - Cores 2-7: VM vCPUs (6 cores total)"
    echo
    echo "GRUB Parameters being added:"
    echo "  - isolcpus=2-7: Removes cores 2-7 from Linux kernel scheduler"
    echo "  - nohz_full=2-7: Disables periodic timer ticks on cores 2-7"
    echo "  - rcu_nocbs=2-7: Moves RCU callback processing off cores 2-7"
    echo
    echo "Benefits:"
    echo "  - Eliminates 1000+ interruptions per second on VM cores"
    echo "  - Reduces CPU cache pollution"
    echo "  - Improves gaming performance and reduces jitter"
    echo "  - Prevents VM crashes during intensive workloads"
    echo
}

# Function to check current GRUB configuration
check_grub_config() {
    local grub_file="/etc/default/grub"
    
    if [[ ! -f "$grub_file" ]]; then
        print_error "GRUB configuration file not found: $grub_file"
        return 1
    fi
    
    print_status "Checking current GRUB configuration..."
    echo
    
    # Check for GRUB_CMDLINE_LINUX_DEFAULT line
    local grub_line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" || echo "")
    
    if [[ -z "$grub_line" ]]; then
        print_warning "GRUB_CMDLINE_LINUX_DEFAULT line not found in $grub_file"
        print_warning "This is unusual - GRUB configuration may be incomplete"
        return 1
    fi
    
    # Remove the variable name and quotes to get just the parameters
    local current_params=$(echo "$grub_line" | sed 's/^GRUB_CMDLINE_LINUX_DEFAULT=//' | sed 's/^"//' | sed 's/"$//')
    
    print_status "Current GRUB parameters:"
    echo "  $current_params"
    echo
    
    # Check each parameter individually
    local isolcpus_present=false
    local nohz_full_present=false
    local rcu_nocbs_present=false
    
    if echo "$current_params" | grep -q "isolcpus=2-7"; then
        isolcpus_present=true
        print_success "✓ isolcpus=2-7 is present"
    else
        print_warning "✗ isolcpus=2-7 is missing"
    fi
    
    if echo "$current_params" | grep -q "nohz_full=2-7"; then
        nohz_full_present=true
        print_success "✓ nohz_full=2-7 is present"
    else
        print_warning "✗ nohz_full=2-7 is missing"
    fi
    
    if echo "$current_params" | grep -q "rcu_nocbs=2-7"; then
        rcu_nocbs_present=true
        print_success "✓ rcu_nocbs=2-7 is present"
    else
        print_warning "✗ rcu_nocbs=2-7 is missing"
    fi
    
    echo
    
    if [[ "$isolcpus_present" == true && "$nohz_full_present" == true && "$rcu_nocbs_present" == true ]]; then
        print_success "All CPU pinning parameters are already configured!"
        return 0
    else
        print_warning "Some CPU pinning parameters are missing"
        return 1
    fi
}

# Function to add CPU pinning parameters to GRUB
add_cpu_pinning_params() {
    local grub_file="/etc/default/grub"
    local backup_file="/etc/default/grub.backup.$(date +%Y%m%d_%H%M%S)"
    
    print_status "Adding CPU pinning parameters to GRUB configuration..."
    
    # Create backup
    if cp "$grub_file" "$backup_file"; then
        print_status "Created backup: $backup_file"
    else
        print_error "Failed to create backup of GRUB configuration"
        return 1
    fi
    
    # Get current GRUB_CMDLINE_LINUX_DEFAULT line
    local grub_line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" || echo "")
    
    if [[ -z "$grub_line" ]]; then
        print_error "GRUB_CMDLINE_LINUX_DEFAULT line not found"
        return 1
    fi
    
    # Extract current parameters (remove variable name and quotes)
    local current_params=$(echo "$grub_line" | sed 's/^GRUB_CMDLINE_LINUX_DEFAULT=//' | sed 's/^"//' | sed 's/"$//')
    
    print_status "Current parameters: $current_params"
    
    # Check if parameters are already present to avoid duplicates
    local new_params="$current_params"
    
    if ! echo "$current_params" | grep -q "isolcpus=2-7"; then
        new_params="$new_params isolcpus=2-7"
    fi
    
    if ! echo "$current_params" | grep -q "nohz_full=2-7"; then
        new_params="$new_params nohz_full=2-7"
    fi
    
    if ! echo "$current_params" | grep -q "rcu_nocbs=2-7"; then
        new_params="$new_params rcu_nocbs=2-7"
    fi
    
    # Clean up extra spaces
    new_params=$(echo "$new_params" | sed 's/^ *//' | sed 's/ *$//' | sed 's/  */ /g')
    
    print_status "New parameters: $new_params"
    
    # Replace the line in the file
    local new_grub_line="GRUB_CMDLINE_LINUX_DEFAULT=\"$new_params\""
    
    if sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|$new_grub_line|" "$grub_file"; then
        print_success "Successfully updated GRUB configuration"
        
        # Verify the change
        print_status "Verifying GRUB configuration..."
        local verify_line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" || echo "")
        local verify_params=$(echo "$verify_line" | sed 's/^GRUB_CMDLINE_LINUX_DEFAULT=//' | sed 's/^"//' | sed 's/"$//')
        
        print_status "Verified parameters: $verify_params"
        
        # Update GRUB configuration
        print_status "Updating GRUB configuration..."
        if grub-mkconfig -o /boot/grub/grub.cfg; then
            print_success "GRUB configuration updated successfully"
            print_warning "REBOOT REQUIRED for changes to take effect"
            return 0
        else
            print_error "Failed to update GRUB configuration"
            print_error "Restoring backup..."
            cp "$backup_file" "$grub_file"
            return 1
        fi
    else
        print_error "Failed to update GRUB configuration file"
        print_error "Restoring backup..."
        cp "$backup_file" "$grub_file"
        return 1
    fi
}

# Function to remove CPU pinning parameters from GRUB
remove_cpu_pinning_params() {
    local grub_file="/etc/default/grub"
    local backup_file="/etc/default/grub.backup.$(date +%Y%m%d_%H%M%S)"
    
    print_status "Removing CPU pinning parameters from GRUB configuration..."
    
    # Create backup
    if cp "$grub_file" "$backup_file"; then
        print_status "Created backup: $backup_file"
    else
        print_error "Failed to create backup of GRUB configuration"
        return 1
    fi
    
    # Get current GRUB_CMDLINE_LINUX_DEFAULT line
    local grub_line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" || echo "")
    
    if [[ -z "$grub_line" ]]; then
        print_error "GRUB_CMDLINE_LINUX_DEFAULT line not found"
        return 1
    fi
    
    # Extract current parameters (remove variable name and quotes)
    local current_params=$(echo "$grub_line" | sed 's/^GRUB_CMDLINE_LINUX_DEFAULT=//' | sed 's/^"//' | sed 's/"$//')
    
    print_status "Current parameters: $current_params"
    
    # Remove CPU pinning parameters
    local new_params="$current_params"
    new_params=$(echo "$new_params" | sed 's/isolcpus=2-7//g')
    new_params=$(echo "$new_params" | sed 's/nohz_full=2-7//g')
    new_params=$(echo "$new_params" | sed 's/rcu_nocbs=2-7//g')
    
    # Clean up extra spaces
    new_params=$(echo "$new_params" | sed 's/^ *//' | sed 's/ *$//' | sed 's/  */ /g')
    
    print_status "New parameters: $new_params"
    
    # Replace the line in the file
    local new_grub_line="GRUB_CMDLINE_LINUX_DEFAULT=\"$new_params\""
    
    if sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|$new_grub_line|" "$grub_file"; then
        print_success "Successfully removed CPU pinning parameters from GRUB configuration"
        
        # Verify the change
        print_status "Verifying GRUB configuration..."
        local verify_line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" || echo "")
        local verify_params=$(echo "$verify_line" | sed 's/^GRUB_CMDLINE_LINUX_DEFAULT=//' | sed 's/^"//' | sed 's/"$//')
        
        print_status "Verified parameters: $verify_params"
        
        # Update GRUB configuration
        print_status "Updating GRUB configuration..."
        if grub-mkconfig -o /boot/grub/grub.cfg; then
            print_success "GRUB configuration updated successfully"
            print_warning "REBOOT REQUIRED for changes to take effect"
            return 0
        else
            print_error "Failed to update GRUB configuration"
            print_error "Restoring backup..."
            cp "$backup_file" "$grub_file"
            return 1
        fi
    else
        print_error "Failed to update GRUB configuration file"
        print_error "Restoring backup..."
        cp "$backup_file" "$grub_file"
        return 1
    fi
}

# Function to show user menu
show_menu() {
    echo
    echo "CPU Pinning GRUB Configuration Menu"
    echo "===================================="
    echo "1. Check current GRUB configuration"
    echo "2. Add CPU pinning parameters"
    echo "3. Remove CPU pinning parameters"
    echo "4. Show CPU pinning information"
    echo "5. Exit"
    echo
}

# Main function
main() {
    echo "=========================================="
    echo "CPU Pinning GRUB Script for AMD 7800X3D"
    echo "=========================================="
    echo
    
    check_root
    
    while true; do
        show_menu
        read -p "Select an option (1-5): " choice
        
        case $choice in
            1)
                echo
                check_grub_config
                ;;
            2)
                echo
                if check_grub_config; then
                    print_warning "CPU pinning parameters are already configured!"
                    print_warning "No changes needed."
                else
                    add_cpu_pinning_params
                fi
                ;;
            3)
                echo
                if check_grub_config; then
                    remove_cpu_pinning_params
                else
                    print_warning "CPU pinning parameters are not currently configured!"
                    print_warning "Nothing to remove."
                fi
                ;;
            4)
                show_cpu_pinning_info
                ;;
            5)
                print_status "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-5."
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Run main function
main "$@"
