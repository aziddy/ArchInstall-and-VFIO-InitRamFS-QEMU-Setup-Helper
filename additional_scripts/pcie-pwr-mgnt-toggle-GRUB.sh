#!/bin/bash

# PCIe Power Management Toggle Script for VFIO Passthrough
# Based on "Prevent Crashing on Hard Workloads QEMU Windows VM.md" section 3
# This script toggles pcie_aspm=off parameter in GRUB configuration

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

# Function to check if pcie_aspm=off is present in GRUB
check_pcie_aspm_status() {
    local grub_file="/etc/default/grub"
    
    if [[ ! -f "$grub_file" ]]; then
        print_error "GRUB configuration file not found: $grub_file"
        exit 1
    fi
    
    # Source the grub file to get GRUB_CMDLINE_LINUX_DEFAULT
    source "$grub_file"
    
    if [[ "$GRUB_CMDLINE_LINUX_DEFAULT" == *"pcie_aspm=off"* ]]; then
        print_status "pcie_aspm=off is currently ENABLED in GRUB configuration"
        return 0  # Present
    else
        print_status "pcie_aspm=off is currently DISABLED (not present) in GRUB configuration"
        return 1  # Not present
    fi
}

# Function to add pcie_aspm=off parameter
add_pcie_aspm() {
    local grub_file="/etc/default/grub"
    local backup_file="${grub_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup
    cp "$grub_file" "$backup_file"
    print_status "Created backup: $backup_file"
    
    # Source the grub file to get current GRUB_CMDLINE_LINUX_DEFAULT
    source "$grub_file"
    
    # Check if already present
    if [[ "$GRUB_CMDLINE_LINUX_DEFAULT" == *"pcie_aspm=off"* ]]; then
        print_warning "pcie_aspm=off is already present in GRUB configuration"
        print_warning "No changes needed. Removing backup file."
        rm "$backup_file"
        return 0
    fi
    
    # Add pcie_aspm=off to the command line
    local new_cmdline="$GRUB_CMDLINE_LINUX_DEFAULT pcie_aspm=off"
    
    # Update the GRUB_CMDLINE_LINUX_DEFAULT line
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\"|" "$grub_file"
    
    print_success "Added pcie_aspm=off to GRUB_CMDLINE_LINUX_DEFAULT"
    print_status "New GRUB_CMDLINE_LINUX_DEFAULT: $new_cmdline"
    
    # Generate new GRUB configuration
    print_status "Generating new GRUB configuration..."
    if grub-mkconfig -o /boot/grub/grub.cfg; then
        print_success "GRUB configuration updated successfully"
        print_warning "Please reboot your system for changes to take effect"
    else
        print_error "Failed to generate GRUB configuration"
        print_error "Restoring backup..."
        cp "$backup_file" "$grub_file"
        exit 1
    fi
}

# Function to remove pcie_aspm=off parameter
remove_pcie_aspm() {
    local grub_file="/etc/default/grub"
    local backup_file="${grub_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup
    cp "$grub_file" "$backup_file"
    print_status "Created backup: $backup_file"
    
    # Source the grub file to get current GRUB_CMDLINE_LINUX_DEFAULT
    source "$grub_file"
    
    # Check if present
    if [[ "$GRUB_CMDLINE_LINUX_DEFAULT" != *"pcie_aspm=off"* ]]; then
        print_warning "pcie_aspm=off is not present in GRUB configuration"
        print_warning "No changes needed. Removing backup file."
        rm "$backup_file"
        return 0
    fi
    
    # Remove pcie_aspm=off from the command line
    local new_cmdline=$(echo "$GRUB_CMDLINE_LINUX_DEFAULT" | sed 's/pcie_aspm=off//g' | sed 's/  / /g' | sed 's/^ //g' | sed 's/ $//g')
    
    # Update the GRUB_CMDLINE_LINUX_DEFAULT line
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\"|" "$grub_file"
    
    print_success "Removed pcie_aspm=off from GRUB_CMDLINE_LINUX_DEFAULT"
    print_status "New GRUB_CMDLINE_LINUX_DEFAULT: $new_cmdline"
    
    # Generate new GRUB configuration
    print_status "Generating new GRUB configuration..."
    if grub-mkconfig -o /boot/grub/grub.cfg; then
        print_success "GRUB configuration updated successfully"
        print_warning "Please reboot your system for changes to take effect"
    else
        print_error "Failed to generate GRUB configuration"
        print_error "Restoring backup..."
        cp "$backup_file" "$grub_file"
        exit 1
    fi
}

# Function to display information about PCIe ASPM
show_pcie_aspm_info() {
    echo
    print_status "PCIe ASPM (Active State Power Management) Information:"
    echo
    echo "What is pcie_aspm=off?"
    echo "  - Disables PCIe Active State Power Management"
    echo "  - Prevents PCIe devices from entering low-power states"
    echo "  - Forces PCIe devices to remain in active state"
    echo
    echo "Why disable it for VFIO passthrough?"
    echo "  - PCIe power management can cause issues with GPU passthrough"
    echo "  - Prevents GPU from entering power-saving modes that cause crashes"
    echo "  - Ensures consistent PCIe link performance"
    echo "  - Reduces latency and improves stability for gaming VMs"
    echo
    echo "When to use:"
    echo "  - Enable (add pcie_aspm=off): For VFIO GPU passthrough setups"
    echo "  - Disable (remove pcie_aspm=off): For normal desktop use or troubleshooting"
    echo
    echo "Current GRUB configuration:"
    source /etc/default/grub
    echo "  GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_CMDLINE_LINUX_DEFAULT\""
    echo
}

# Function to get user choice
get_user_choice() {
    local current_status=$1
    
    echo >&2
    if [[ $current_status -eq 0 ]]; then
        echo "Current status: pcie_aspm=off is ENABLED" >&2
        echo >&2
        echo "What would you like to do?" >&2
        echo "  1) Remove pcie_aspm=off (disable PCIe power management control)" >&2
        echo "  2) Exit (keep current configuration)" >&2
        echo >&2
        while true; do
            read -p "Enter your choice [1-2]: " choice
            choice=$(echo "$choice" | tr -d '\n\r' | xargs)  # Clean up input
            
            case $choice in
                1)
                    echo "remove"
                    break
                    ;;
                2)
                    echo "exit"
                    break
                    ;;
                *)
                    print_error "Invalid choice. Please enter 1 or 2." >&2
                    continue
                    ;;
            esac
        done
    else
        echo "Current status: pcie_aspm=off is DISABLED (not present)" >&2
        echo >&2
        echo "What would you like to do?" >&2
        echo "  1) Add pcie_aspm=off (enable PCIe power management control)" >&2
        echo "  2) Exit (keep current configuration)" >&2
        echo >&2
        while true; do
            read -p "Enter your choice [1-2]: " choice
            choice=$(echo "$choice" | tr -d '\n\r' | xargs)  # Clean up input
            
            case $choice in
                1)
                    echo "add"
                    break
                    ;;
                2)
                    echo "exit"
                    break
                    ;;
                *)
                    print_error "Invalid choice. Please enter 1 or 2." >&2
                    continue
                    ;;
            esac
        done
    fi
}

# Main function
main() {
    echo "=========================================="
    echo "PCIe Power Management Toggle Script"
    echo "=========================================="
    echo
    
    check_root
    
    # Check current status
    local current_status
    if check_pcie_aspm_status; then
        current_status=0  # Present
    else
        current_status=1  # Not present
    fi
    
    show_pcie_aspm_info
    
    # Get user choice
    local user_choice
    if ! user_choice=$(get_user_choice $current_status); then
        exit 1
    fi
    
    case $user_choice in
        "add")
            print_status "Adding pcie_aspm=off to GRUB configuration..."
            add_pcie_aspm
            ;;
        "remove")
            print_status "Removing pcie_aspm=off from GRUB configuration..."
            remove_pcie_aspm
            ;;
        "exit")
            print_status "Exiting without making changes."
            exit 0
            ;;
        *)
            print_error "Invalid choice received: $user_choice"
            exit 1
            ;;
    esac
    
    echo
    print_success "PCIe power management configuration completed!"
    echo
    print_warning "IMPORTANT: Reboot your system for the changes to take effect"
    if [[ "$user_choice" == "add" ]]; then
        print_status "After reboot, PCIe power management will be disabled for better VFIO stability"
    else
        print_status "After reboot, PCIe power management will be enabled (default system behavior)"
    fi
}

# Run main function
main "$@"
