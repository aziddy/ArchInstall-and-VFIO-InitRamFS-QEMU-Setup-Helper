#!/bin/bash

# CPU Pinning Script for 7800X3D (6 Cores, No SMT/Hyperthreading)
# Based on "Prevent Crashing on Hard Workloads QEMU Windows VM.md" section 5 - Option 5.A
# This script configures CPU pinning for VFIO passthrough VMs to prevent crashes during intensive workloads

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

# Function to check if VM already has CPU pinning configured
check_vm_cpu_pinning() {
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
    
    # Check if CPU pinning is already configured for 6 cores (2-7)
    # Handle both single and double quotes in cpuset attributes
    if echo "$xml_config" | grep -q '<cputune>' && echo "$xml_config" | grep -q '<vcpupin' && (echo "$xml_config" | grep -q 'cpuset="2"' || echo "$xml_config" | grep -q "cpuset='2'"); then
        print_warning "VM '$vm_name' already has CPU pinning configured (6 cores: 2-7)"
        return 0
    fi
    
    # Check if any CPU pinning exists
    if echo "$xml_config" | grep -q '<cputune>' && echo "$xml_config" | grep -q '<vcpupin'; then
        print_status "VM '$vm_name' has different CPU pinning configuration"
        print_warning "Current configuration will be replaced with 7800X3D 6-core setup"
        return 1
    else
        print_status "VM '$vm_name' has no CPU pinning configured (will add 7800X3D 6-core setup)"
        return 1
    fi
}

# Function to configure VM CPU pinning for 7800X3D (6 cores, no SMT)
configure_vm_cpu_pinning() {
    local vm_name="$1"
    # Clean up VM name (remove any extra quotes or whitespace)
    vm_name=$(echo "$vm_name" | tr -d '\n\r"' | xargs)
    local backup_file="/tmp/${vm_name}_cpu_pinning_backup_$(date +%Y%m%d_%H%M%S).xml"
    
    print_status "Configuring VM '$vm_name' with CPU pinning for 7800X3D (6 cores, no SMT)..."
    
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
        print_warning "CPU pinning configuration will be applied after VM shutdown"
    fi
    
    # Configure CPU pinning by editing the XML directly
    local temp_xml="/tmp/${vm_name}_cpu_pinning_temp.xml"
    
    # Get current XML configuration
    if ! virsh dumpxml "$vm_name" > "$temp_xml"; then
        print_error "Failed to get VM XML configuration for '$vm_name'"
        return 1
    fi
    
    # Check if CPU configuration already exists
    local cpu_pinning_exists=false
    local vcpu_exists=false
    
    if grep -q '<cputune>' "$temp_xml"; then
        cpu_pinning_exists=true
    fi
    
    if grep -q '<vcpu' "$temp_xml"; then
        vcpu_exists=true
    fi
    
    print_status "Modifying XML configuration for 7800X3D CPU pinning..."
    
    # Remove existing CPU pinning configuration if it exists
    if [[ "$cpu_pinning_exists" == true ]]; then
        print_status "Removing existing CPU pinning configuration..."
        # Use perl to remove the entire cputune section
        perl -i -0pe 's|<cputune>.*?</cputune>||gs' "$temp_xml"
    fi
    
    # Update vcpu configuration
    if [[ "$vcpu_exists" == true ]]; then
        print_status "Updating vCPU configuration to 6 cores..."
        # Replace existing vcpu line with new configuration (just set to 6, no cpuset in vcpu tag)
        sed -i 's|<vcpu[^>]*>[^<]*</vcpu>|<vcpu placement="static">6</vcpu>|g' "$temp_xml"
    else
        print_status "Adding vCPU configuration..."
        # Add vcpu configuration after the first <domain> tag
        sed -i 's|<domain[^>]*>|<domain type="kvm">\n  <vcpu placement="static">6</vcpu>|g' "$temp_xml"
    fi
    
    # Add CPU pinning configuration
    print_status "Adding CPU pinning configuration..."
    
    # Find a good place to insert the cputune section (after vcpu, before memory)
    if grep -q '<memory' "$temp_xml"; then
        # Insert before memory tag
        sed -i 's|<memory|<cputune>\n    <!-- Pin guest vCPUs to cores 2-7 -->\n    <vcpupin vcpu="0" cpuset="2"/>\n    <vcpupin vcpu="1" cpuset="3"/>\n    <vcpupin vcpu="2" cpuset="4"/>\n    <vcpupin vcpu="3" cpuset="5"/>\n    <vcpupin vcpu="4" cpuset="6"/>\n    <vcpupin vcpu="5" cpuset="7"/>\n    \n    <!-- Pin QEMU emulator threads to cores 0-1 -->\n    <emulatorpin cpuset="0-1"/>\n  </cputune>\n\n  <memory|g' "$temp_xml"
    else
        # Fallback: add after vcpu
        sed -i 's|</vcpu>|</vcpu>\n  <cputune>\n    <!-- Pin guest vCPUs to cores 2-7 -->\n    <vcpupin vcpu="0" cpuset="2"/>\n    <vcpupin vcpu="1" cpuset="3"/>\n    <vcpupin vcpu="2" cpuset="4"/>\n    <vcpupin vcpu="3" cpuset="5"/>\n    <vcpupin vcpu="4" cpuset="6"/>\n    <vcpupin vcpu="5" cpuset="7"/>\n    \n    <!-- Pin QEMU emulator threads to cores 0-1 -->\n    <emulatorpin cpuset="0-1"/>\n  </cputune>|g' "$temp_xml"
    fi
    
    # Show the modified CPU configuration for verification
    print_status "Modified CPU configuration:"
    grep -A 15 -B 2 '<vcpu\|<cputune>' "$temp_xml" || true
    
    # Apply the modified configuration
    if virsh define "$temp_xml"; then
        print_success "Successfully applied CPU pinning configuration to VM '$vm_name'"
        
        # Verify the changes were actually applied
        print_status "Verifying CPU pinning configuration..."
        local verify_xml=$(virsh dumpxml "$vm_name" 2>/dev/null || true)
        
        if [[ -z "$verify_xml" ]]; then
            print_error "Failed to get VM configuration for verification"
            print_error "VM may not be defined in libvirt. Please define it first with:"
            print_error "  sudo virsh define /etc/libvirt/qemu/$vm_name.xml"
            return 1
        fi
        
        # Debug: Show what we're checking for
        print_status "Debug - Checking for cputune section:"
        echo "$verify_xml" | grep -A 10 '<cputune>' || echo "No cputune section found"
        
        # Check for cputune section and vcpupin entries (check for core 2 and core 7 to verify range)
        # Handle both single and double quotes in cpuset attributes
        if echo "$verify_xml" | grep -q '<cputune>' && echo "$verify_xml" | grep -q '<vcpupin' && (echo "$verify_xml" | grep -q 'cpuset="2"' || echo "$verify_xml" | grep -q "cpuset='2'") && (echo "$verify_xml" | grep -q 'cpuset="7"' || echo "$verify_xml" | grep -q "cpuset='7'"); then
            print_success "✓ Verification successful: CPU pinning is now configured"
            print_status "CPU Layout:"
            print_status "  - Core 0: Host OS + QEMU emulator"
            print_status "  - Core 1: Host OS + QEMU emulator"
            print_status "  - Core 2: VM vCPU 0"
            print_status "  - Core 3: VM vCPU 1"
            print_status "  - Core 4: VM vCPU 2"
            print_status "  - Core 5: VM vCPU 3"
            print_status "  - Core 6: VM vCPU 4"
            print_status "  - Core 7: VM vCPU 5"
        else
            print_error "✗ Verification failed: CPU pinning configuration not applied correctly"
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
        print_error "Failed to configure VM '$vm_name' with CPU pinning"
        print_error "Restoring backup configuration..."
        virsh define "$backup_file" &>/dev/null || true
        rm -f "$temp_xml"
        return 1
    fi
}

# Function to show CPU pinning information
show_cpu_pinning_info() {
    echo
    print_status "CPU Pinning Information for 7800X3D:"
    echo
    echo "What is CPU pinning?"
    echo "  - CPU pinning assigns specific VM vCPUs to dedicated physical CPU cores"
    echo "  - Prevents CPU scheduler conflicts between host and guest"
    echo "  - Improves performance and reduces latency for intensive workloads"
    echo
    echo "7800X3D 6-Core Configuration (No SMT/Hyperthreading):"
    echo "  - Total 6 vCPUs for the VM (cores 2-7)"
    echo "  - Cores 0-1: Reserved for host OS and QEMU emulator"
    echo "  - Cores 2-7: Dedicated to VM vCPUs"
    echo "  - No hyperthreading/SMT to avoid scheduling conflicts"
    echo
    echo "Benefits:"
    echo "  - Prevents VM crashes during intensive gaming/workloads"
    echo "  - Reduces CPU context switching overhead"
    echo "  - Improves VM responsiveness and stability"
    echo "  - Better performance isolation from host system"
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
    echo "CPU Pinning Script for 7800X3D (6C, No SMT)"
    echo "=========================================="
    echo
    
    check_root
    
    show_cpu_pinning_info
    
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
                
                if check_vm_cpu_pinning "$vm"; then
                    print_warning "Skipping VM '$vm' (CPU pinning already configured for 6 cores)"
                    ((skipped_count++))
                else
                    if configure_vm_cpu_pinning "$vm"; then
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
        if check_vm_cpu_pinning "$vm_selection"; then
            print_warning "VM '$vm_selection' already has CPU pinning configured for 7800X3D"
            print_warning "No changes needed. Exiting."
            exit 0
        fi
        
        configure_vm_cpu_pinning "$vm_selection"
    fi
    
    echo
    print_success "CPU pinning configuration completed!"
    echo
    print_status "CPU pinning is now configured for 7800X3D with 6 cores (no SMT)"
    print_status "This should prevent VM crashes during intensive workloads"
    print_status "Restart your VMs for the changes to take effect"
    print_status ""
    print_status "CPU Layout:"
    print_status "  - Core 0: Host OS + QEMU emulator"
    print_status "  - Core 1: Host OS + QEMU emulator"
    print_status "  - Core 2: VM vCPU 0"
    print_status "  - Core 3: VM vCPU 1"
    print_status "  - Core 4: VM vCPU 2"
    print_status "  - Core 5: VM vCPU 3"
    print_status "  - Core 6: VM vCPU 4"
    print_status "  - Core 7: VM vCPU 5"
}

# Run main function
main "$@"
