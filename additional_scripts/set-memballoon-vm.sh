#!/bin/bash

# Memballoon Configuration Script for VMs
set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Function to list VMs properly
list_vms() {
    print_status "Available VMs:"
    echo
    
    # Get VM list and check if it's empty
    local vm_output=$(virsh list --all 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        print_error "Failed to connect to libvirt"
        return 1
    fi
    
    echo "$vm_output"
    echo
    
    # Get VM names
    local vm_names=$(virsh list --all --name 2>/dev/null | grep -v '^$')
    if [[ -z "$vm_names" ]]; then
        print_warning "No VMs found"
        return 1
    fi
    
    return 0
}

# Function to check if memballoon is disabled
check_memballoon_status() {
    local vm_name="$1"
    
    print_status "Checking memballoon status for VM: $vm_name"
    
    # Check if VM exists
    if ! virsh dominfo "$vm_name" &>/dev/null; then
        print_error "VM '$vm_name' does not exist"
        return 1
    fi
    
    # Get memballoon configuration
    local memballoon_config=$(virsh dumpxml "$vm_name" 2>/dev/null | grep -A1 '<memballoon' | head -2)
    
    if echo "$memballoon_config" | grep -q 'model="none"'; then
        print_success "Memballoon is DISABLED (model='none')"
        return 0
    elif echo "$memballoon_config" | grep -q '<memballoon'; then
        print_warning "Memballoon is ENABLED (default config - no record in xml)"
        return 1
    else
        print_warning "Memballoon configuration not found (default enabled)"
        return 1
    fi
}

# Function to disable memballoon
disable_memballoon() {
    local vm_name="$1"
    
    print_status "Disabling memballoon for VM: $vm_name"
    
    # Check if VM is running
    if virsh list --state-running | grep -q "$vm_name"; then
        print_warning "VM is currently running. Changes will take effect after VM restart."
    fi
    
    # Create temporary XML file for editing
    local temp_xml="/tmp/${vm_name}_memballoon.xml"
    
    # Dump current VM configuration
    if ! virsh dumpxml "$vm_name" > "$temp_xml" 2>/dev/null; then
        print_error "Failed to export VM configuration"
        return 1
    fi
    
    # Check if memballoon section exists
    if grep -q '<memballoon' "$temp_xml"; then
        # Replace existing memballoon configuration
        sed -i 's/<memballoon[^>]*>/<memballoon model="none"\/>/' "$temp_xml"
    else
        # Add memballoon configuration before closing </devices> tag
        sed -i 's|</devices>|  <memballoon model="none"/>\n</devices>|' "$temp_xml"
    fi
    
    # Apply the configuration
    if virsh define "$temp_xml" &>/dev/null; then
        print_success "Memballoon disabled successfully"
        rm -f "$temp_xml"
        return 0
    else
        print_error "Failed to apply memballoon configuration"
        rm -f "$temp_xml"
        return 1
    fi
}

# Function to enable memballoon
enable_memballoon() {
    local vm_name="$1"
    
    print_status "Enabling memballoon for VM: $vm_name"
    
    # Check if VM is running
    if virsh list --state-running | grep -q "$vm_name"; then
        print_warning "VM is currently running. Changes will take effect after VM restart."
    fi
    
    # Create temporary XML file for editing
    local temp_xml="/tmp/${vm_name}_memballoon.xml"
    
    # Dump current VM configuration
    if ! virsh dumpxml "$vm_name" > "$temp_xml" 2>/dev/null; then
        print_error "Failed to export VM configuration"
        return 1
    fi
    
    # Replace memballoon configuration with default
    if grep -q '<memballoon' "$temp_xml"; then
        # Replace existing memballoon configuration
        sed -i 's/<memballoon[^>]*>/<memballoon model="virtio">\n    <address type="pci" domain="0x0000" bus="0x00" slot="0x07" function="0x0"\/>\n  <\/memballoon>/' "$temp_xml"
    else
        # Add memballoon configuration before closing </devices> tag
        sed -i 's|</devices>|  <memballoon model="virtio">\n    <address type="pci" domain="0x0000" bus="0x00" slot="0x07" function="0x0"\/>\n  <\/memballoon>\n</devices>|' "$temp_xml"
    fi
    
    # Apply the configuration
    if virsh define "$temp_xml" &>/dev/null; then
        print_success "Memballoon enabled successfully"
        rm -f "$temp_xml"
        return 0
    else
        print_error "Failed to apply memballoon configuration"
        rm -f "$temp_xml"
        return 1
    fi
}

# Function to show memballoon information
show_memballoon_info() {
    echo
    print_status "About Memballoon:"
    echo "The VirtIO memballoon device enables the host to dynamically reclaim memory from your VM"
    echo "by growing the balloon inside the guest, reserving reclaimed memory."
    echo
    print_warning "However, this device causes:"
    echo "• Major performance issues with VFIO passthrough setups (like passing in a dGPU)"
    echo "• Can cause crashing if CPU or VFIO Passthrough Device tries to access memory"
    echo "  that memballoon takes away from RAM"
    echo
    print_status "Recommendation: Disable memballoon for VFIO passthrough VMs"
    echo
}

# Main script execution
main() {
    echo "=========================================="
    echo "    VM Memballoon Configuration Script"
    echo "=========================================="
    echo
    
    # Show memballoon information
    show_memballoon_info
    
    # List available VMs
    if ! list_vms; then
        exit 1
    fi
    
    # Get VM name from user
    echo
    read -p "Enter VM name: " vm_name
    
    if [[ -z "$vm_name" ]]; then
        print_error "VM name cannot be empty"
        exit 1
    fi
    
    # Check if VM exists
    if ! virsh dominfo "$vm_name" &>/dev/null; then
        print_error "VM '$vm_name' does not exist"
        exit 1
    fi
    
    # Check current memballoon status
    echo
    check_memballoon_status "$vm_name"
    local current_status=$?
    
    # Show options
    echo
    echo "Choose an option:"
    echo "1) Disable memballoon (recommended for VFIO passthrough)"
    echo "2) Enable memballoon (default libvirt behavior)"
    echo "3) Exit"
    echo
    
    read -p "Enter your choice (1-3): " choice
    
    case $choice in
        1)
            if [[ $current_status -eq 0 ]]; then
                print_warning "Memballoon is already disabled for this VM"
            else
                disable_memballoon "$vm_name"
            fi
            ;;
        2)
            if [[ $current_status -eq 1 ]]; then
                print_warning "Memballoon is already enabled for this VM"
            else
                enable_memballoon "$vm_name"
            fi
            ;;
        3)
            print_status "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid choice. Please run the script again."
            exit 1
            ;;
    esac
    
    echo
    print_status "Script completed. Remember to restart your VM for changes to take effect."
}

# Run main function
main "$@"
