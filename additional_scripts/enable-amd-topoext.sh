#!/bin/bash

# AMD topoext CPU Feature Flag Enable Script
# Based on "Prevent Crashing on Hard Workloads QEMU Windows VM.md" section 3
# This script checks for AMD topoext support and configures VMs to use it

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

# Function to check if system is AMD
check_amd_cpu() {
    local vendor=$(lscpu | grep "Vendor ID" | awk '{print $3}')
    
    if [[ "$vendor" != "AuthenticAMD" ]]; then
        print_error "This script is for AMD CPUs only. Detected CPU vendor: $vendor"
        print_error "topoext is an AMD-specific CPU feature flag"
        exit 1
    fi
    
    print_success "AMD CPU detected: $vendor"
}

# Function to check if topoext feature flag is available
check_topoext_support() {
    print_status "Checking for topoext CPU feature flag support..."
    
    local topoext_check=$(lscpu | grep -i topoext || true)
    
    if [[ -z "$topoext_check" ]]; then
        print_error "topoext feature flag not found in CPU features"
        print_error "Your AMD CPU does not support topoext"
        print_status "Available CPU flags:"
        lscpu | grep -E "Flags|Features" | head -5
        exit 1
    fi
    
    print_success "topoext feature flag found: $topoext_check"
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

# Function to check if VM already has topoext configured
check_vm_topoext() {
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
    
    # Check if topoext is already configured
    if echo "$xml_config" | grep -q 'name="topoext"' || echo "$xml_config" | grep -q "name='topoext'"; then
        print_warning "VM '$vm_name' already has topoext configured"
        return 0
    fi
    
    return 1
}

# Function to configure VM with topoext
configure_vm_topoext() {
    local vm_name="$1"
    # Clean up VM name (remove any extra quotes or whitespace)
    vm_name=$(echo "$vm_name" | tr -d '\n\r"' | xargs)
    local backup_file="/tmp/${vm_name}_config_backup_$(date +%Y%m%d_%H%M%S).xml"
    
    print_status "Configuring VM '$vm_name' with topoext..."
    
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
        print_warning "topoext configuration will be applied after VM shutdown"
    fi
    
    # Configure topoext by editing the XML directly
    local temp_xml="/tmp/${vm_name}_temp_config.xml"
    
    # Get current XML configuration
    if ! virsh dumpxml "$vm_name" > "$temp_xml"; then
        print_error "Failed to get VM XML configuration for '$vm_name'"
        return 1
    fi
    
    # Check if topoext is already in the XML
    if grep -q 'name="topoext"' "$temp_xml" || grep -q "name='topoext'" "$temp_xml"; then
        print_warning "topoext feature is already configured in VM '$vm_name'"
        print_warning "No changes needed. Exiting."
        rm -f "$temp_xml"
        return 0
    fi
    
    # Modify XML to add topoext feature
    print_status "Modifying XML configuration..."
    
    # Check if CPU section already exists and has host-passthrough mode
    if grep -q "<cpu mode='host-passthrough'" "$temp_xml"; then
        print_status "Found existing host-passthrough CPU section, adding topoext feature..."
        # CPU section exists with host-passthrough, add topoext feature
        sed -i "/<cpu mode='host-passthrough'/a\\    <feature policy=\"require\" name=\"topoext\"/>" "$temp_xml"
    elif grep -q "<cpu mode=" "$temp_xml"; then
        print_status "Found existing CPU section, replacing with host-passthrough and topoext..."
        # CPU section exists but not host-passthrough, replace it
        sed -i "s|<cpu mode='[^']*'[^>]*>|<cpu mode='host-passthrough'>\\n    <feature policy=\"require\" name=\"topoext\"/>|g" "$temp_xml"
    else
        print_status "No CPU section found, adding new CPU section with topoext..."
        # CPU section doesn't exist, add it
        sed -i "s|<vcpu[^>]*>|<vcpu>\\n  <cpu mode='host-passthrough'>\\n    <feature policy=\"require\" name=\"topoext\"/>\\n  </cpu>|g" "$temp_xml"
    fi
    
    # Show the modified CPU section for verification
    print_status "Modified CPU section:"
    grep -A 5 '<cpu mode=' "$temp_xml" || true
    
    # Apply the modified configuration
    if virsh define "$temp_xml"; then
        print_success "Successfully configured VM '$vm_name' with topoext"
        print_status "VM will use topoext feature flag on next boot"
        
        if [[ "$vm_state" == "running" ]]; then
            print_warning "VM is currently running. You may need to restart the VM for changes to take effect"
        fi
        
        # Clean up temp file
        rm -f "$temp_xml"
        return 0
    else
        print_error "Failed to configure VM '$vm_name' with topoext"
        print_error "Restoring backup configuration..."
        virsh define "$backup_file" &>/dev/null || true
        rm -f "$temp_xml"
        return 1
    fi
}

# Function to show topoext information
show_topoext_info() {
    echo
    print_status "AMD topoext CPU Feature Flag Information:"
    echo
    echo "topoext (Topology Extensions):"
    echo "  - AMD-specific CPU feature flag"
    echo "  - Lets the OS inside the VM know CPU core topology"
    echo "  - Distinguishes between real cores and hyper-threaded siblings"
    echo "  - Improves performance and scheduling efficiency in VMs"
    echo "  - Prevents performance degradation from incorrect CPU topology detection"
    echo
    echo "Configuration:"
    echo "  - Sets CPU mode to 'host-passthrough'"
    echo "  - Requires 'topoext' feature flag"
    echo "  - Only works with AMD CPUs that support this feature"
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
    echo "AMD topoext CPU Feature Flag Enable Script"
    echo "=========================================="
    echo
    
    check_root
    check_amd_cpu
    check_topoext_support
    
    show_topoext_info
    
    # Check if libvirt is available
    if ! command -v virsh &>/dev/null; then
        print_error "libvirt (virsh) not found. Please install libvirt first"
        exit 1
    fi
    
    # Check if virt-xml is available
    if ! command -v virt-xml &>/dev/null; then
        print_error "virt-xml not found. Please install libvirt-client first"
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
                
                if check_vm_topoext "$vm"; then
                    print_warning "Skipping VM '$vm' (already configured)"
                    ((skipped_count++))
                else
                    if configure_vm_topoext "$vm"; then
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
        if check_vm_topoext "$vm_selection"; then
            print_warning "VM '$vm_selection' already has topoext configured"
            print_warning "No changes needed. Exiting."
            exit 0
        fi
        
        configure_vm_topoext "$vm_selection"
    fi
    
    echo
    print_success "AMD topoext configuration completed!"
    echo
    print_status "topoext will improve CPU topology detection in your VMs"
    print_status "This should help with performance and scheduling efficiency"
}

# Run main function
main "$@"
