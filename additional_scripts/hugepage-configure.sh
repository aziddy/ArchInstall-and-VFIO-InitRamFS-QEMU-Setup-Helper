#!/bin/bash

# Hugepage Configuration Script for VFIO Passthrough VMs
# Based on "Prevent Crashing on Hard Workloads QEMU Windows VM.md" section 10
# This script manages hugepage configuration for better VM performance

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

# Function to show hugepage information
show_hugepage_info() {
    echo
    print_status "Hugepage Information:"
    echo
    echo "What are Hugepages?"
    echo "  - Standard Linux uses 4KB memory pages by default"
    echo "  - Hugepages are much larger memory pages (typically 2MB or 1GB instead of 4KB)"
    echo "  - Significantly reduces the number of page table entries needed"
    echo "  - Improves memory access performance and reduces CPU overhead"
    echo
    echo "Why use hugepages for VFIO passthrough?"
    echo "  - Better Performance: VM can access memory more efficiently"
    echo "  - Reduced CPU Overhead: Fewer page table lookups = less CPU time on memory management"
    echo "  - Prevents Crashes: More stable memory allocation under heavy workloads (like gaming)"
    echo "  - Memory Dedication: Reserves physical memory specifically for your VM"
    echo
    echo "Configuration:"
    echo "  - Reserves physical memory for VM use"
    echo "  - Configures VM to use hugepages instead of standard pages"
    echo "  - Improves VM stability and performance with GPU passthrough"
    echo
}

# Function to check current hugepage status
check_hugepage_status() {
    echo
    print_status "Current Hugepage Status:"
    echo
    
    # Check if hugepages are configured
    local nr_hugepages=$(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo "0")
    local hugepage_size=$(grep Hugepagesize /proc/meminfo | awk '{print $2}' 2>/dev/null || echo "0")
    local hugepage_unit=$(grep Hugepagesize /proc/meminfo | awk '{print $3}' 2>/dev/null || echo "KB")
    
    echo "  - Number of hugepages allocated: $nr_hugepages"
    echo "  - Hugepage size: $hugepage_size $hugepage_unit"
    
    # Calculate total memory reserved
    if [[ "$hugepage_unit" == "KB" ]]; then
        local total_mb=$((nr_hugepages * hugepage_size / 1024))
        echo "  - Total memory reserved: ${total_mb}MB"
    else
        local total_mb=$((nr_hugepages * hugepage_size))
        echo "  - Total memory reserved: ${total_mb}MB"
    fi
    
    # Check if hugepages are enabled in sysctl.conf
    if grep -q "vm.nr_hugepages" /etc/sysctl.conf 2>/dev/null; then
        local sysctl_value=$(grep "vm.nr_hugepages" /etc/sysctl.conf | awk -F'=' '{print $2}' | tr -d ' ')
        echo "  - Persistent configuration: $sysctl_value hugepages"
    else
        echo "  - Persistent configuration: Not set"
    fi
    
    # Check libvirt group access
    local libvirt_group_id=$(getent group libvirt | cut -d: -f3 2>/dev/null || echo "")
    local hugetlb_group=$(cat /proc/sys/vm/hugetlb_shm_group 2>/dev/null || echo "0")
    
    if [[ -n "$libvirt_group_id" ]]; then
        echo "  - Libvirt group ID: $libvirt_group_id"
        echo "  - Hugepage access group: $hugetlb_group"
        if [[ "$libvirt_group_id" == "$hugetlb_group" ]]; then
            echo "  - Libvirt group access: ✓ Enabled"
        else
            echo "  - Libvirt group access: ✗ Disabled"
        fi
    else
        echo "  - Libvirt group: Not found"
    fi
    
    # Check available hugepage types
    echo
    print_status "Available Hugepage Types:"
    if [[ -d "/sys/kernel/mm/hugepages" ]]; then
        for hugepage_type in /sys/kernel/mm/hugepages/hugepages-*; do
            if [[ -d "$hugepage_type" ]]; then
                local type_name=$(basename "$hugepage_type")
                local type_size=$(cat "$hugepage_type/nr_hugepages" 2>/dev/null || echo "0")
                echo "  - $type_name: $type_size pages"
            fi
        done
    else
        echo "  - No hugepage types available"
    fi
}

# Function to enable hugepages
enable_hugepages() {
    local pages="$1"
    
    echo
    print_status "Enabling hugepages with $pages pages..."
    
    # Calculate memory size for display
    local hugepage_size=$(grep Hugepagesize /proc/meminfo | awk '{print $2}' 2>/dev/null || echo "2048")
    local total_mb=$((pages * hugepage_size / 1024))
    
    print_status "This will reserve approximately ${total_mb}MB of memory"
    
    # Set hugepages immediately
    if echo "$pages" > /proc/sys/vm/nr_hugepages; then
        print_success "Successfully allocated $pages hugepages"
    else
        print_error "Failed to allocate hugepages"
        return 1
    fi
    
    # Add to sysctl.conf for persistence
    print_status "Adding persistent configuration to /etc/sysctl.conf..."
    
    # Remove existing hugepage configuration
    sed -i '/vm.nr_hugepages/d' /etc/sysctl.conf 2>/dev/null || true
    
    # Add new configuration
    echo "vm.nr_hugepages = $pages" >> /etc/sysctl.conf
    
    # Set libvirt group access
    local libvirt_group_id=$(getent group libvirt | cut -d: -f3 2>/dev/null || echo "")
    if [[ -n "$libvirt_group_id" ]]; then
        print_status "Setting libvirt group access to hugepages..."
        echo "$libvirt_group_id" > /proc/sys/vm/hugetlb_shm_group
        
        # Add to sysctl.conf for persistence
        sed -i '/vm.hugetlb_shm_group/d' /etc/sysctl.conf 2>/dev/null || true
        echo "vm.hugetlb_shm_group = $libvirt_group_id" >> /etc/sysctl.conf
        
        print_success "Libvirt group access configured"
    else
        print_warning "Libvirt group not found, skipping group access configuration"
    fi
    
    # Apply sysctl changes
    if sysctl -p >/dev/null 2>&1; then
        print_success "Persistent configuration applied"
    else
        print_warning "Failed to apply sysctl configuration (may need reboot)"
    fi
    
    print_success "Hugepages enabled successfully!"
    print_status "Configuration will persist after reboot"
}

# Function to disable hugepages
disable_hugepages() {
    echo
    print_status "Disabling hugepages..."
    
    # Set hugepages to 0 immediately
    if echo "0" > /proc/sys/vm/nr_hugepages; then
        print_success "Successfully disabled hugepages"
    else
        print_error "Failed to disable hugepages"
        return 1
    fi
    
    # Remove from sysctl.conf
    print_status "Removing persistent configuration from /etc/sysctl.conf..."
    sed -i '/vm.nr_hugepages/d' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/vm.hugetlb_shm_group/d' /etc/sysctl.conf 2>/dev/null || true
    
    # Apply sysctl changes
    if sysctl -p >/dev/null 2>&1; then
        print_success "Persistent configuration removed"
    else
        print_warning "Failed to apply sysctl configuration (may need reboot)"
    fi
    
    print_success "Hugepages disabled successfully!"
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

# Function to check VM hugepage configuration
check_vm_hugepages() {
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
    
    # Check if hugepages are enabled
    if echo "$xml_config" | grep -q '<memoryBacking>'; then
        if echo "$xml_config" | grep -A 5 '<memoryBacking>' | grep -q '<hugepages/>'; then
            print_status "VM '$vm_name' has hugepages enabled"
            return 0
        else
            print_status "VM '$vm_name' has memoryBacking configured but hugepages disabled"
            return 1
        fi
    else
        print_status "VM '$vm_name' has no memoryBacking configuration (hugepages disabled)"
        return 1
    fi
}

# Function to silently check VM hugepage configuration (no output)
check_vm_hugepages_silent() {
    local vm_name="$1"
    # Clean up VM name (remove any extra quotes or whitespace)
    vm_name=$(echo "$vm_name" | tr -d '\n\r"' | xargs)
    
    if ! virsh dominfo "$vm_name" &>/dev/null; then
        return 1
    fi
    
    local xml_config=$(virsh dumpxml "$vm_name" 2>/dev/null || true)
    
    if [[ -z "$xml_config" ]]; then
        return 1
    fi
    
    # Check if hugepages are enabled
    if echo "$xml_config" | grep -q '<memoryBacking>'; then
        if echo "$xml_config" | grep -A 5 '<memoryBacking>' | grep -q '<hugepages/>'; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Function to configure VM hugepages
configure_vm_hugepages() {
    local vm_name="$1"
    local enable="$2"
    # Clean up VM name (remove any extra quotes or whitespace)
    vm_name=$(echo "$vm_name" | tr -d '\n\r"' | xargs)
    local backup_file="/tmp/${vm_name}_hugepages_backup_$(date +%Y%m%d_%H%M%S).xml"
    
    print_status "Configuring VM '$vm_name' hugepages: $enable"
    
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
        print_warning "Hugepage configuration will be applied after VM shutdown"
    fi
    
    # Configure hugepages by editing the XML directly
    local temp_xml="/tmp/${vm_name}_hugepages_temp.xml"
    
    # Get current XML configuration
    if ! virsh dumpxml "$vm_name" > "$temp_xml"; then
        print_error "Failed to get VM XML configuration for '$vm_name'"
        return 1
    fi
    
    if [[ "$enable" == "enable" ]]; then
        # Enable hugepages
        if grep -q '<memoryBacking>' "$temp_xml"; then
            # Replace existing memoryBacking with hugepages enabled
            print_status "Replacing existing memoryBacking configuration with hugepages enabled..."
            perl -i -0pe 's|<memoryBacking>.*?</memoryBacking>|<memoryBacking>\n    <hugepages/>\n  </memoryBacking>|gs' "$temp_xml"
        else
            # Add memoryBacking with hugepages
            print_status "Adding memoryBacking configuration with hugepages enabled..."
            # Find a good place to insert the memoryBacking section (after memory section)
            if grep -q '</memory>' "$temp_xml"; then
                # Insert after memory tag
                sed -i 's|</memory>|</memory>\n  <memoryBacking>\n    <hugepages/>\n  </memoryBacking>|g' "$temp_xml"
            else
                # Fallback: add at the end before closing domain tag
                sed -i 's|</domain>|  <memoryBacking>\n    <hugepages/>\n  </memoryBacking>\n</domain>|g' "$temp_xml"
            fi
        fi
    else
        # Disable hugepages
        if grep -q '<memoryBacking>' "$temp_xml"; then
            print_status "Removing memoryBacking configuration..."
            perl -i -0pe 's|<memoryBacking>.*?</memoryBacking>||gs' "$temp_xml"
        else
            print_warning "VM '$vm_name' already has hugepages disabled"
            rm -f "$temp_xml"
            return 0
        fi
    fi
    
    # Show the modified memoryBacking section for verification
    print_status "Modified memoryBacking section:"
    grep -A 3 -B 1 '<memoryBacking>' "$temp_xml" || echo "No memoryBacking section found"
    
    # Apply the modified configuration
    if virsh define "$temp_xml"; then
        print_success "Successfully applied configuration to VM '$vm_name'"
        
        # Verify the changes were actually applied
        print_status "Verifying hugepage configuration..."
        local verify_xml=$(virsh dumpxml "$vm_name" 2>/dev/null || true)
        
        if [[ "$enable" == "enable" ]]; then
            if echo "$verify_xml" | grep -A 5 '<memoryBacking>' | grep -q '<hugepages/>'; then
                print_success "✓ Verification successful: hugepages are now enabled"
                print_status "VM will now use hugepages for better performance"
            else
                print_error "✗ Verification failed: hugepages are still disabled"
                print_error "The configuration may not have been applied correctly"
                print_error "Restoring backup configuration..."
                virsh define "$backup_file" &>/dev/null || true
                rm -f "$temp_xml"
                return 1
            fi
        else
            if ! echo "$verify_xml" | grep -q '<memoryBacking>'; then
                print_success "✓ Verification successful: hugepages are now disabled"
                print_status "VM will now use standard memory pages"
            else
                print_error "✗ Verification failed: hugepages are still enabled"
                print_error "The configuration may not have been applied correctly"
                print_error "Restoring backup configuration..."
                virsh define "$backup_file" &>/dev/null || true
                rm -f "$temp_xml"
                return 1
            fi
        fi
        
        if [[ "$vm_state" == "running" ]]; then
            print_warning "VM is currently running. You may need to restart the VM for changes to take effect"
        fi
        
        # Clean up temp file
        rm -f "$temp_xml"
        return 0
    else
        print_error "Failed to configure VM '$vm_name' hugepages"
        print_error "Restoring backup configuration..."
        virsh define "$backup_file" &>/dev/null || true
        rm -f "$temp_xml"
        return 1
    fi
}

# Function to interactively select VM
select_vm() {
    echo
    read -p "Enter VM name to configure: " vm_input
    
    # Clean up input (remove extra whitespace/newlines)
    vm_input=$(echo "$vm_input" | tr -d '\n\r' | xargs)
    
    if [[ -n "$vm_input" ]]; then
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

# Function to get number of hugepages from user
get_hugepage_count() {
    echo >&2
    print_status "Hugepage Configuration:" >&2
    echo >&2
    echo "Recommended values:" >&2
    echo "  - 8GB VM: 4096 pages (4096 * 2MB = 8GB)" >&2
    echo "  - 16GB VM: 8192 pages (8192 * 2MB = 16GB)" >&2
    echo "  - 28GB VM: 14336 pages (14336 * 2MB = 28GB)" >&2
    echo "  - 32GB VM: 16384 pages (16384 * 2MB = 32GB)" >&2
    echo >&2
    
    local hugepage_size=$(grep Hugepagesize /proc/meminfo | awk '{print $2}' 2>/dev/null || echo "2048")
    local total_memory=$(free -m | awk 'NR==2{print $2}')
    local max_pages=$((total_memory * 1024 / hugepage_size))
    
    echo "System information:" >&2
    echo "  - Total system memory: ${total_memory}MB" >&2
    echo "  - Hugepage size: ${hugepage_size}KB" >&2
    echo "  - Maximum possible pages: $max_pages" >&2
    echo >&2
    
    while true; do
        read -p "Enter number of hugepages to allocate: " pages_input
        
        if [[ "$pages_input" =~ ^[0-9]+$ ]]; then
            if [[ "$pages_input" -gt 0 && "$pages_input" -le "$max_pages" ]]; then
                echo "$pages_input"
                return 0
            else
                print_error "Please enter a number between 1 and $max_pages"
            fi
        else
            print_error "Please enter a valid number"
        fi
    done
}

# Main menu function
show_menu() {
    echo
    echo "=========================================="
    echo "Hugepage Configuration Menu"
    echo "=========================================="
    echo
    echo "1. Check hugepage status"
    echo "2. Enable hugepages"
    echo "3. Disable hugepages"
    echo "4. Configure VM hugepages"
    echo "5. Exit"
    echo
}

# Main function
main() {
    echo "=========================================="
    echo "Hugepage Configuration Script for VFIO VMs"
    echo "=========================================="
    echo
    
    check_root
    
    show_hugepage_info
    
    # Check if libvirt is available
    if ! command -v virsh &>/dev/null; then
        print_error "libvirt (virsh) not found. Please install libvirt first"
        exit 1
    fi
    
    while true; do
        show_menu
        read -p "Select an option (1-5): " choice
        
        case $choice in
            1)
                check_hugepage_status
                ;;
            2)
                local pages=$(get_hugepage_count)
                enable_hugepages "$pages"
                ;;
            3)
                disable_hugepages
                ;;
            4)
                if ! list_vms; then
                    continue
                fi
                
                local vm_selection
                if ! vm_selection=$(select_vm); then
                    continue
                fi
                
                # Check current VM hugepage status silently
                check_vm_hugepages_silent "$vm_selection"
                local current_status=$?
                
                echo
                echo "=========================================="
                echo "VM Hugepage Configuration Options"
                echo "=========================================="
                echo
                if [[ $current_status -eq 0 ]]; then
                    echo "Current status: Hugepages ENABLED ✓"
                    echo
                    echo "1. Disable hugepages for this VM"
                    echo "2. Go back to main menu"
                    echo
                    read -p "Select an option (1-2): " vm_choice
                    
                    case $vm_choice in
                        1)
                            configure_vm_hugepages "$vm_selection" "disable"
                            ;;
                        2)
                            continue
                            ;;
                        *)
                            print_error "Invalid option. Please select 1-2."
                            ;;
                    esac
                else
                    echo "Current status: Hugepages DISABLED ✗"
                    echo
                    echo "1. Enable hugepages for this VM"
                    echo "2. Go back to main menu"
                    echo
                    read -p "Select an option (1-2): " vm_choice
                    
                    case $vm_choice in
                        1)
                            configure_vm_hugepages "$vm_selection" "enable"
                            ;;
                        2)
                            continue
                            ;;
                        *)
                            print_error "Invalid option. Please select 1-2."
                            ;;
                    esac
                fi
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
