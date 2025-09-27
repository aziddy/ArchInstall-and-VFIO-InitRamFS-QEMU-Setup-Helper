#!/bin/bash

# Disable Memballoon Script for VFIO Passthrough VMs
# Based on "Prevent Crashing on Hard Workloads QEMU Windows VM.md" section 6
# This script disables memballoon device in VMs to prevent performance issues with VFIO passthrough

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

# Function to list available VMs
list_vms() {
    print_status "Available VMs:"
    
    # Show detailed VM list with status
    echo
    virsh list --all
    echo
    
    local vms=$(virsh list --all --name | grep -v "^$" || true)
    
    if [[ -z "$vms" ]]; then
        print_warning "No VMs found"
        return 1
    fi
    
    print_status "VM names for selection:"
    local count=1
    echo "$vms" | while read -r vm; do
        echo "  $count. $vm"
        ((count++))
    done
    
    return 0
}

# Function to check if VM already has memballoon disabled
check_vm_memballoon() {
    local vm_name="$1"
    # Clean up VM name (remove any extra quotes or whitespace)
    vm_name=$(echo "$vm_name" | tr -d '\n\r"' | xargs)
    
    if ! virsh dominfo "$vm_name" &>/dev/null; then
        print_error "VM '$vm_name' not found"
        return 1
    fi
    
    local xml_config=$(virsh dumpxml "$vm_name" 2>/dev/null || true)
    
    if [[ -z "$xml_config" ]]; then
        print_error "Failed to get VM configuration for '$vm_name'"
        return 1
    fi
    
    # Check if memballoon is already disabled
    if echo "$xml_config" | grep -q '<memballoon model="none"' || echo "$xml_config" | grep -q "<memballoon model='none'"; then
        print_warning "VM '$vm_name' already has memballoon disabled"
        return 0
    fi
    
    # Check if memballoon section exists at all
    if echo "$xml_config" | grep -q '<memballoon'; then
        print_status "VM '$vm_name' has memballoon enabled (needs to be disabled)"
        return 1
    else
        print_status "VM '$vm_name' has no memballoon section (will add disabled memballoon)"
        return 1
    fi
}

# Function to configure VM to disable memballoon
configure_vm_memballoon() {
    local vm_name="$1"
    # Clean up VM name (remove any extra quotes or whitespace)
    vm_name=$(echo "$vm_name" | tr -d '\n\r"' | xargs)
    local backup_file="/tmp/${vm_name}_memballoon_backup_$(date +%Y%m%d_%H%M%S).xml"
    
    print_status "Configuring VM '$vm_name' to disable memballoon..."
    
    # Create backup of current VM configuration
    if virsh dumpxml "$vm_name" > "$backup_file"; then
        print_status "Created VM configuration backup: $backup_file"
    else
        print_error "Failed to create VM configuration backup"
        return 1
    fi
    
    # Check if VM is running
    local vm_state=$(virsh domstate "$vm_name" 2>/dev/null || echo "unknown")
    
    if [[ "$vm_state" == "running" ]]; then
        print_warning "VM '$vm_name' is currently running"
        print_warning "Memballoon configuration will be applied after VM shutdown"
    fi
    
    # Configure memballoon by editing the XML directly
    local temp_xml="/tmp/${vm_name}_memballoon_temp.xml"
    
    # Get current XML configuration
    if ! virsh dumpxml "$vm_name" > "$temp_xml"; then
        print_error "Failed to get VM XML configuration for '$vm_name'"
        return 1
    fi
    
    # Check if memballoon section already exists
    local memballoon_exists=false
    local memballoon_disabled=false
    
    if grep -q '<memballoon' "$temp_xml"; then
        memballoon_exists=true
        if grep -q 'model="none"' "$temp_xml" || grep -q "model='none'" "$temp_xml"; then
            memballoon_disabled=true
        fi
    fi
    
    if [[ "$memballoon_exists" == true && "$memballoon_disabled" == true ]]; then
        print_warning "Memballoon is already disabled in VM '$vm_name'"
        print_warning "No changes needed. Exiting."
        rm -f "$temp_xml"
        return 0
    fi
    
    # Modify XML to disable memballoon
    print_status "Modifying XML configuration..."
    
    if [[ "$memballoon_exists" == true ]]; then
        # Replace existing memballoon with disabled version (handle multi-line structure)
        print_status "Replacing existing memballoon configuration with disabled version..."
        # Use perl for multi-line replacement
        perl -i -0pe 's|<memballoon[^>]*>.*?</memballoon>|<memballoon model="none"/>|gs' "$temp_xml"
    else
        # Add disabled memballoon section
        print_status "Adding disabled memballoon configuration..."
        # Find a good place to insert the memballoon section (after devices section)
        if grep -q '</devices>' "$temp_xml"; then
            # Insert before closing devices tag
            sed -i 's|</devices>|  <memballoon model="none"/>\n</devices>|g' "$temp_xml"
        else
            # Fallback: add at the end before closing domain tag
            sed -i 's|</domain>|  <memballoon model="none"/>\n</domain>|g' "$temp_xml"
        fi
    fi
    
    # Show the modified memballoon section for verification
    print_status "Modified memballoon section:"
    grep -A 1 -B 1 '<memballoon' "$temp_xml" || true
    
    # Debug: Show the exact memballoon lines
    print_status "Debug - All memballoon related lines in temp XML:"
    grep -n 'memballoon' "$temp_xml" || echo "No memballoon lines found"
    
    # Apply the modified configuration
    if virsh define "$temp_xml"; then
        print_success "Successfully applied configuration to VM '$vm_name'"
        
        # Verify the changes were actually applied
        print_status "Verifying memballoon configuration..."
        local verify_xml=$(virsh dumpxml "$vm_name" 2>/dev/null || true)
        
        if echo "$verify_xml" | grep -q '<memballoon model="none"' || echo "$verify_xml" | grep -q "<memballoon model='none'"; then
            print_success "✓ Verification successful: memballoon is now disabled"
            print_status "Memballoon device is now disabled for better VFIO passthrough performance"
        else
            print_error "✗ Verification failed: memballoon is still enabled"
            print_error "The configuration may not have been applied correctly"
            print_error "Restoring backup configuration..."
            virsh define "$backup_file" &>/dev/null || true
            rm -f "$temp_xml"
            return 1
        fi
        
        if [[ "$vm_state" == "running" ]]; then
            print_warning "VM is currently running. You may need to restart the VM for changes to take effect"
        fi
        
        # Clean up temp file
        rm -f "$temp_xml"
        return 0
    else
        print_error "Failed to configure VM '$vm_name' to disable memballoon"
        print_error "Restoring backup configuration..."
        virsh define "$backup_file" &>/dev/null || true
        rm -f "$temp_xml"
        return 1
    fi
}

# Function to show memballoon information
show_memballoon_info() {
    echo
    print_status "Memballoon Information:"
    echo
    echo "What is memballoon?"
    echo "  - The VirtIO memballoon device enables the host to dynamically reclaim memory"
    echo "  - It grows the balloon inside the guest, reserving reclaimed memory"
    echo "  - Libvirt adds this device to guests by default"
    echo
    echo "Why disable it for VFIO passthrough?"
    echo "  - Causes major performance issues with VFIO passthrough setups"
    echo "  - Can cause crashing if CPU or VFIO passthrough device (ex dGPU) tries to access"
    echo "    memory that memballoon takes away from RAM"
    echo "  - Prevents memory conflicts between host and guest"
    echo
    echo "Configuration:"
    echo "  - Sets memballoon model to 'none' to disable the device"
    echo "  - Improves VM stability and performance with GPU passthrough"
    echo
}

# Function to interactively select VM
select_vm() {
    echo
    read -p "Enter VM name to configure (or 'all' for all VMs): " vm_input
    
    # Clean up input (remove extra whitespace/newlines)
    vm_input=$(echo "$vm_input" | tr -d '\n\r' | xargs)
    
    if [[ "$vm_input" == "all" ]]; then
        echo "all"
    elif [[ -n "$vm_input" ]]; then
        # Verify VM exists
        if virsh dominfo "$vm_input" &>/dev/null; then
            echo "$vm_input"
        else
            print_error "VM '$vm_input' not found"
            return 1
        fi
    else
        print_error "No VM specified"
        return 1
    fi
}

# Main function
main() {
    echo "=========================================="
    echo "Disable Memballoon Script for VFIO VMs"
    echo "=========================================="
    echo
    
    check_root
    
    show_memballoon_info
    
    # Check if libvirt is available
    if ! command -v virsh &>/dev/null; then
        print_error "libvirt (virsh) not found. Please install libvirt first"
        exit 1
    fi
    
    # List available VMs first
    if ! list_vms; then
        exit 1
    fi
    
    # Select VM(s) to configure
    local vm_selection
    if ! vm_selection=$(select_vm); then
        exit 1
    fi
    
    # Debug: Show what VM was selected
    print_status "Selected VM: '$vm_selection'"
    
    if [[ "$vm_selection" == "all" ]]; then
        # Configure all VMs
        local vms=$(virsh list --all --name | grep -v "^$")
        local configured_count=0
        local skipped_count=0
        
        echo "$vms" | while read -r vm; do
            if [[ -n "$vm" ]]; then
                echo
                print_status "Processing VM: $vm"
                
                if check_vm_memballoon "$vm"; then
                    print_warning "Skipping VM '$vm' (memballoon already disabled)"
                    ((skipped_count++))
                else
                    if configure_vm_memballoon "$vm"; then
                        ((configured_count++))
                    fi
                fi
            fi
        done
        
        echo
        print_status "Configuration summary:"
        print_status "  - VMs configured: $configured_count"
        print_status "  - VMs skipped (already configured): $skipped_count"
        
    else
        # Configure single VM
        if check_vm_memballoon "$vm_selection"; then
            print_warning "VM '$vm_selection' already has memballoon disabled"
            print_warning "No changes needed. Exiting."
            exit 0
        fi
        
        configure_vm_memballoon "$vm_selection"
    fi
    
    echo
    print_success "Memballoon configuration completed!"
    echo
    print_status "Memballoon device is now disabled for better VFIO passthrough performance"
    print_status "This should prevent memory conflicts and improve VM stability"
    print_status "Restart your VMs for the changes to take effect"
}

# Run main function
main "$@"