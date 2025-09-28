#!/bin/bash

# CPU Pinning VM XML + GRUB Configuration Script for AMD 7800X3D (6 Cores + 6 Threads, SMT ON)
# Based on "Prevent Crashing on Hard Workloads QEMU Windows VM.md" section 5 - Option 5.B
# This script configures both VM XML and GRUB parameters for CPU pinning on AMD 7800X3D with SMT/Hyperthreading enabled

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# CPU pinning parameters for 7800X3D (6 cores + 6 threads, SMT ON)
CPU_PINNING_PARAMS="isolcpus=2-7,10-15 nohz_full=2-7,10-15 rcu_nocbs=2-7,10-15"

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

# Function to check if SMT/Hyperthreading is enabled
check_smt_enabled() {
    print_status "Checking if SMT/Hyperthreading is enabled..."
    
    # Check if SMT is enabled in the system
    local smt_status=$(cat /sys/devices/system/cpu/smt/active 2>/dev/null || echo "unknown")
    local cpu_cores=$(nproc)
    local cpu_threads=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
    local cpu_sockets=$(lscpu | grep "^Socket(s):" | awk '{print $2}')
    local cores_per_socket=$(lscpu | grep "^Core(s) per socket:" | awk '{print $4}')
    
    print_status "System CPU information:"
    print_status "  - SMT Status: $smt_status"
    print_status "  - Total CPU threads: $cpu_threads"
    print_status "  - CPU sockets: $cpu_sockets"
    print_status "  - Cores per socket: $cores_per_socket"
    
    # Calculate expected threads for 7800X3D (6 cores, SMT enabled = 12 threads)
    local expected_threads=$((cores_per_socket * 2))
    
    if [[ "$cpu_threads" -ge 12 && "$expected_threads" -eq 12 ]]; then
        print_success "✓ SMT/Hyperthreading appears to be enabled (12 threads detected)"
        return 0
    elif [[ "$cpu_threads" -eq 6 ]]; then
        print_error "✗ SMT/Hyperthreading is disabled (only 6 threads detected)"
        print_error "This script requires SMT to be enabled for 7800X3D"
        print_error "Please enable SMT in your UEFI/BIOS settings and reboot"
        return 1
    else
        print_warning "⚠ Unexpected CPU thread count: $cpu_threads"
        print_warning "Expected 12 threads for 7800X3D with SMT enabled"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0
        else
            return 1
        fi
    fi
}

# Function to show CPU pinning information
show_cpu_pinning_info() {
    echo
    print_status "CPU Pinning Information for AMD 7800X3D (6 Cores + 6 Threads, SMT ON):"
    echo
    echo "What is CPU Pinning with SMT?"
    echo "  - Assigns specific CPU cores AND threads exclusively to your VM"
    echo "  - Prevents host system processes from interrupting VM execution"
    echo "  - Improves VM performance and reduces latency for gaming"
    echo "  - Uses both physical cores and their hyperthreaded siblings"
    echo
    echo "Configuration for 7800X3D (6 cores + 6 threads, SMT ON):"
    echo "  - Cores 0-1: Host OS + QEMU emulator (threads 0,1,8,9)"
    echo "  - Cores 2-7: VM vCPUs (12 vCPUs total using threads 2-7,10-15)"
    echo
    echo "VM XML Configuration:"
    echo "  - 12 vCPUs total (6 physical cores × 2 threads)"
    echo "  - vCPU 0-1: Physical Core 2 (threads 2,10)"
    echo "  - vCPU 2-3: Physical Core 3 (threads 3,11)"
    echo "  - vCPU 4-5: Physical Core 4 (threads 4,12)"
    echo "  - vCPU 6-7: Physical Core 5 (threads 5,13)"
    echo "  - vCPU 8-9: Physical Core 6 (threads 6,14)"
    echo "  - vCPU 10-11: Physical Core 7 (threads 7,15)"
    echo
    echo "GRUB Parameters being added:"
    echo "  - isolcpus=2-7,10-15: Removes cores 2-7 and threads 10-15 from Linux kernel scheduler"
    echo "  - nohz_full=2-7,10-15: Disables periodic timer ticks on cores 2-7 and threads 10-15"
    echo "  - rcu_nocbs=2-7,10-15: Moves RCU callback processing off cores 2-7 and threads 10-15"
    echo
    echo "Benefits:"
    echo "  - Eliminates 1000+ interruptions per second on VM cores"
    echo "  - Reduces CPU cache pollution"
    echo "  - Improves gaming performance and reduces jitter"
    echo "  - Prevents VM crashes during intensive workloads"
    echo "  - Better utilization of hyperthreaded cores"
    echo
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
    
    if echo "$current_params" | grep -q "isolcpus=2-7,10-15"; then
        isolcpus_present=true
        print_success "✓ isolcpus=2-7,10-15 is present"
    else
        print_warning "✗ isolcpus=2-7,10-15 is missing"
    fi
    
    if echo "$current_params" | grep -q "nohz_full=2-7,10-15"; then
        nohz_full_present=true
        print_success "✓ nohz_full=2-7,10-15 is present"
    else
        print_warning "✗ nohz_full=2-7,10-15 is missing"
    fi
    
    if echo "$current_params" | grep -q "rcu_nocbs=2-7,10-15"; then
        rcu_nocbs_present=true
        print_success "✓ rcu_nocbs=2-7,10-15 is present"
    else
        print_warning "✗ rcu_nocbs=2-7,10-15 is missing"
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
    
    if ! echo "$current_params" | grep -q "isolcpus=2-7,10-15"; then
        new_params="$new_params isolcpus=2-7,10-15"
    fi
    
    if ! echo "$current_params" | grep -q "nohz_full=2-7,10-15"; then
        new_params="$new_params nohz_full=2-7,10-15"
    fi
    
    if ! echo "$current_params" | grep -q "rcu_nocbs=2-7,10-15"; then
        new_params="$new_params rcu_nocbs=2-7,10-15"
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

# Function to check if VM has CPU pinning configured
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
    
    # Check if any CPU pinning exists
    if echo "$xml_config" | grep -q '<cputune>' && echo "$xml_config" | grep -q '<vcpupin'; then
        return 0  # CPU pinning exists
    else
        return 1  # No CPU pinning
    fi
}

# Function to show current CPU pinning status for a VM
show_vm_cpu_pinning_status() {
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
    
    print_status "CPU Pinning Status for VM: $vm_name"
    echo "----------------------------------------"
    
    # Check if CPU pinning exists
    if echo "$xml_config" | grep -q '<cputune>' && echo "$xml_config" | grep -q '<vcpupin'; then
        print_success "✓ CPU pinning is CONFIGURED"
        echo
        
        # Extract and show current CPU pinning configuration
        print_status "Current CPU pinning configuration:"
        echo "$xml_config" | grep -A 20 '<cputune>' | grep -E '<vcpupin|<emulatorpin' | while read -r line; do
            echo "  $line"
        done
        echo
        
        # Check if it matches 7800X3D 6-core + 6-thread configuration
        if echo "$xml_config" | grep -q 'cpuset="2"' || echo "$xml_config" | grep -q "cpuset='2'"; then
            if echo "$xml_config" | grep -q 'cpuset="15"' || echo "$xml_config" | grep -q "cpuset='15'"; then
                print_status "✓ Configuration matches 7800X3D 6-core + 6-thread setup (cores 2-7, threads 10-15)"
            else
                print_warning "⚠ Configuration uses cores 2+ but may not be complete 7800X3D SMT setup"
            fi
        else
            print_warning "⚠ Configuration exists but doesn't match 7800X3D 6-core + 6-thread setup"
        fi
    else
        print_warning "✗ CPU pinning is NOT CONFIGURED"
        echo
        print_status "No CPU pinning found in VM configuration"
    fi
    
    echo
    return 0
}

# Function to configure VM CPU pinning for 7800X3D (6 cores + 6 threads, SMT ON)
configure_vm_cpu_pinning() {
    local vm_name="$1"
    # Clean up VM name (remove any extra quotes or whitespace)
    vm_name=$(echo "$vm_name" | tr -d '\n\r"' | xargs)
    local backup_file="/tmp/${vm_name}_cpu_pinning_backup_$(date +%Y%m%d_%H%M%S).xml"
    
    print_status "Configuring VM '$vm_name' with CPU pinning for 7800X3D (6 cores + 6 threads, SMT ON)..."
    
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
    
    print_status "Modifying XML configuration for 7800X3D CPU pinning with SMT..."
    
    # Remove existing CPU pinning configuration if it exists
    if [[ "$cpu_pinning_exists" == true ]]; then
        print_status "Removing existing CPU pinning configuration..."
        # Use perl to remove the entire cputune section
        perl -i -0pe 's|<cputune>.*?</cputune>||gs' "$temp_xml"
    fi
    
    # Update vcpu configuration
    if [[ "$vcpu_exists" == true ]]; then
        print_status "Updating vCPU configuration to 12 cores (6 physical + 6 threads)..."
        # Replace existing vcpu line with new configuration
        sed -i 's|<vcpu[^>]*>[^<]*</vcpu>|<vcpu placement="static">12</vcpu>|g' "$temp_xml"
    else
        print_status "Adding vCPU configuration..."
        # Add vcpu configuration after the first <domain> tag
        sed -i 's|<domain[^>]*>|<domain type="kvm">\n  <vcpu placement="static">12</vcpu>|g' "$temp_xml"
    fi
    
    # Add CPU pinning configuration
    print_status "Adding CPU pinning configuration with SMT..."
    
    # Find a good place to insert the cputune section (after vcpu, before memory)
    if grep -q '<memory' "$temp_xml"; then
        # Insert before memory tag
        sed -i 's|<memory|<cputune>\n    <!-- Pin guest vCPUs to physical cores 2-7 (both threads of each core) -->\n    <vcpupin vcpu="0" cpuset="2"/>   <!-- Core 2, Thread 1 -->\n    <vcpupin vcpu="1" cpuset="10"/>  <!-- Core 2, Thread 2 -->\n    <vcpupin vcpu="2" cpuset="3"/>   <!-- Core 3, Thread 1 -->\n    <vcpupin vcpu="3" cpuset="11"/>  <!-- Core 3, Thread 2 -->\n    <vcpupin vcpu="4" cpuset="4"/>   <!-- Core 4, Thread 1 -->\n    <vcpupin vcpu="5" cpuset="12"/>  <!-- Core 4, Thread 2 -->\n    <vcpupin vcpu="6" cpuset="5"/>   <!-- Core 5, Thread 1 -->\n    <vcpupin vcpu="7" cpuset="13"/>  <!-- Core 5, Thread 2 -->\n    <vcpupin vcpu="8" cpuset="6"/>   <!-- Core 6, Thread 1 -->\n    <vcpupin vcpu="9" cpuset="14"/>  <!-- Core 6, Thread 2 -->\n    <vcpupin vcpu="10" cpuset="7"/>  <!-- Core 7, Thread 1 -->\n    <vcpupin vcpu="11" cpuset="15"/> <!-- Core 7, Thread 2 -->\n    \n    <!-- Pin QEMU emulator threads to physical cores 0-1 -->\n    <emulatorpin cpuset="0-1,8-9"/>\n  </cputune>\n\n  <memory|g' "$temp_xml"
    else
        # Fallback: add after vcpu
        sed -i 's|</vcpu>|</vcpu>\n  <cputune>\n    <!-- Pin guest vCPUs to physical cores 2-7 (both threads of each core) -->\n    <vcpupin vcpu="0" cpuset="2"/>   <!-- Core 2, Thread 1 -->\n    <vcpupin vcpu="1" cpuset="10"/>  <!-- Core 2, Thread 2 -->\n    <vcpupin vcpu="2" cpuset="3"/>   <!-- Core 3, Thread 1 -->\n    <vcpupin vcpu="3" cpuset="11"/>  <!-- Core 3, Thread 2 -->\n    <vcpupin vcpu="4" cpuset="4"/>   <!-- Core 4, Thread 1 -->\n    <vcpupin vcpu="5" cpuset="12"/>  <!-- Core 4, Thread 2 -->\n    <vcpupin vcpu="6" cpuset="5"/>   <!-- Core 5, Thread 1 -->\n    <vcpupin vcpu="7" cpuset="13"/>  <!-- Core 5, Thread 2 -->\n    <vcpupin vcpu="8" cpuset="6"/>   <!-- Core 6, Thread 1 -->\n    <vcpupin vcpu="9" cpuset="14"/>  <!-- Core 6, Thread 2 -->\n    <vcpupin vcpu="10" cpuset="7"/>  <!-- Core 7, Thread 1 -->\n    <vcpupin vcpu="11" cpuset="15"/> <!-- Core 7, Thread 2 -->\n    \n    <!-- Pin QEMU emulator threads to physical cores 0-1 -->\n    <emulatorpin cpuset="0-1,8-9"/>\n  </cputune>|g' "$temp_xml"
    fi
    
    # Show the modified CPU configuration for verification
    print_status "Modified CPU configuration:"
    grep -A 20 -B 2 '<vcpu\|<cputune>' "$temp_xml" || true
    
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
        
        # Check for cputune section and vcpupin entries (check for core 2 and thread 15 to verify range)
        # Handle both single and double quotes in cpuset attributes
        if echo "$verify_xml" | grep -q '<cputune>' && echo "$verify_xml" | grep -q '<vcpupin' && (echo "$verify_xml" | grep -q 'cpuset="2"' || echo "$verify_xml" | grep -q "cpuset='2'") && (echo "$verify_xml" | grep -q 'cpuset="15"' || echo "$verify_xml" | grep -q "cpuset='15'"); then
            print_success "✓ Verification successful: CPU pinning is now configured"
            print_status "CPU Layout with SMT:"
            print_status "  - Physical Core 0: Threads 0,8   → Host OS + QEMU emulator"
            print_status "  - Physical Core 1: Threads 1,9   → Host OS + QEMU emulator"
            print_status "  - Physical Core 2: Threads 2,10  → VM vCPUs 0,1"
            print_status "  - Physical Core 3: Threads 3,11  → VM vCPUs 2,3"
            print_status "  - Physical Core 4: Threads 4,12  → VM vCPUs 4,5"
            print_status "  - Physical Core 5: Threads 5,13  → VM vCPUs 6,7"
            print_status "  - Physical Core 6: Threads 6,14  → VM vCPUs 8,9"
            print_status "  - Physical Core 7: Threads 7,15  → VM vCPUs 10,11"
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

# Function to remove CPU pinning from VM
remove_vm_cpu_pinning() {
    local vm_name="$1"
    # Clean up VM name (remove any extra quotes or whitespace)
    vm_name=$(echo "$vm_name" | tr -d '\n\r"' | xargs)
    local backup_file="/tmp/${vm_name}_cpu_pinning_removal_backup_$(date +%Y%m%d_%H%M%S).xml"
    
    print_status "Removing CPU pinning from VM '$vm_name'..."
    
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
        print_warning "CPU pinning removal will be applied after VM shutdown"
    fi
    
    # Remove CPU pinning by editing the XML directly
    local temp_xml="/tmp/${vm_name}_cpu_pinning_removal_temp.xml"
    
    # Get current XML configuration
    if ! virsh dumpxml "$vm_name" > "$temp_xml"; then
        print_error "Failed to get VM XML configuration for '$vm_name'"
        return 1
    fi
    
    # Check if CPU pinning exists
    if ! grep -q '<cputune>' "$temp_xml"; then
        print_warning "VM '$vm_name' has no CPU pinning to remove"
        rm -f "$temp_xml"
        return 0
    fi
    
    print_status "Removing CPU pinning configuration from XML..."
    
    # Remove the entire cputune section
    perl -i -0pe 's|<cputune>.*?</cputune>||gs' "$temp_xml"
    
    # Show the modified configuration for verification
    print_status "Modified configuration (CPU pinning removed):"
    grep -A 5 -B 2 '<vcpu\|<memory>' "$temp_xml" || true
    
    # Apply the modified configuration
    if virsh define "$temp_xml"; then
        print_success "Successfully removed CPU pinning from VM '$vm_name'"
        
        # Verify the changes were actually applied
        print_status "Verifying CPU pinning removal..."
        local verify_xml=$(virsh dumpxml "$vm_name" 2>/dev/null || true)
        
        if [[ -z "$verify_xml" ]]; then
            print_error "Failed to get VM configuration for verification"
            print_error "VM may not be defined in libvirt. Please define it first with:"
            print_error "  sudo virsh define /etc/libvirt/qemu/$vm_name.xml"
            return 1
        fi
        
        # Check that cputune section is gone
        if ! echo "$verify_xml" | grep -q '<cputune>'; then
            print_success "✓ Verification successful: CPU pinning has been removed"
        else
            print_error "✗ Verification failed: CPU pinning still present"
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
        print_error "Failed to remove CPU pinning from VM '$vm_name'"
        print_error "Restoring backup configuration..."
        virsh define "$backup_file" &>/dev/null || true
        rm -f "$temp_xml"
        return 1
    fi
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

# Function to show action menu for a VM
show_vm_action_menu() {
    local vm_name="$1"
    
    # Display menu to user (to stdout)
    echo >&2
    print_status "What would you like to do with VM: $vm_name" >&2
    echo "1. Show current CPU pinning status" >&2
    echo "2. Add CPU pinning (7800X3D 6-core + 6-thread setup)" >&2
    echo "3. Remove CPU pinning" >&2
    echo "4. Skip this VM" >&2
    echo >&2
    read -p "Enter your choice (1-4): " choice
    
    case $choice in
        1)
            show_vm_cpu_pinning_status "$vm_name" >&2
            echo "status_only"  # Return special value to indicate no changes
            return 0
            ;;
        2)
            if check_vm_cpu_pinning "$vm_name"; then
                print_warning "VM '$vm_name' already has CPU pinning configured" >&2
                print_warning "Use option 3 to remove existing pinning first, or option 1 to see current status" >&2
                echo "no_change"
                return 1
            else
                if configure_vm_cpu_pinning "$vm_name"; then
                    echo "added"
                    return 0
                else
                    echo "failed"
                    return 1
                fi
            fi
            ;;
        3)
            if check_vm_cpu_pinning "$vm_name"; then
                if remove_vm_cpu_pinning "$vm_name"; then
                    echo "removed"
                    return 0
                else
                    echo "failed"
                    return 1
                fi
            else
                print_warning "VM '$vm_name' has no CPU pinning to remove" >&2
                echo "no_change"
                return 1
            fi
            ;;
        4)
            print_status "Skipping VM '$vm_name'" >&2
            echo "skipped"
            return 0
            ;;
        *)
            print_error "Invalid choice. Please enter 1, 2, 3, or 4" >&2
            echo "invalid"
            return 1
            ;;
    esac
}

# Function to show main menu
show_main_menu() {
    echo
    echo "CPU Pinning VM XML + GRUB Configuration Menu"
    echo "============================================="
    echo "1. Check SMT/Hyperthreading status"
    echo "2. Check current GRUB configuration"
    echo "3. Add CPU pinning parameters to GRUB"
    echo "4. Configure VM CPU pinning"
    echo "5. Show CPU pinning information"
    echo "6. Exit"
    echo
}

# Main function
main() {
    echo "=========================================="
    echo "CPU Pinning VM XML + GRUB Script for AMD 7800X3D"
    echo "6 Cores + 6 Threads (SMT Enabled)"
    echo "=========================================="
    echo
    
    check_root
    
    # Check if SMT is enabled first
    if ! check_smt_enabled; then
        exit 1
    fi
    
    # Check if libvirt is available
    if ! command -v virsh &>/dev/null; then
        print_error "libvirt (virsh) not found. Please install libvirt first"
        exit 1
    fi
    
    while true; do
        show_main_menu
        read -p "Select an option (1-6): " choice
        
        case $choice in
            1)
                echo
                check_smt_enabled
                ;;
            2)
                echo
                check_grub_config
                ;;
            3)
                echo
                if check_grub_config; then
                    print_warning "CPU pinning parameters are already configured in GRUB!"
                    print_warning "No changes needed."
                else
                    add_cpu_pinning_params
                fi
                ;;
            4)
                echo
                # List available VMs first
                if ! list_vms; then
                    print_error "No VMs found. Please create a VM first."
                    continue
                fi
                
                # Select VM(s) to configure
                local vm_selection
                if ! vm_selection=$(select_vm); then
                    continue
                fi
                
                local changes_made=false
                
                if [[ "$vm_selection" == "all" ]]; then
                    # Process all VMs with interactive menu
                    local vms=$(virsh list --all --name | grep -v "^$")
                    local processed_count=0
                    local configured_count=0
                    local removed_count=0
                    local skipped_count=0
                    local status_only_count=0
                    local failed_count=0
                    
                    echo "$vms" | while read -r vm; do
                        if [[ -n "$vm" ]]; then
                            echo
                            print_status "Processing VM: $vm"
                            
                            # Show current status first
                            show_vm_cpu_pinning_status "$vm"
                            
                            # Show action menu and capture result
                            local action_result
                            action_result=$(show_vm_action_menu "$vm")
                            local menu_exit_code=$?
                            
                            ((processed_count++))
                            
                            case "$action_result" in
                                "added")
                                    ((configured_count++))
                                    changes_made=true
                                    ;;
                                "removed")
                                    ((removed_count++))
                                    changes_made=true
                                    ;;
                                "status_only")
                                    ((status_only_count++))
                                    ;;
                                "skipped")
                                    ((skipped_count++))
                                    ;;
                                "no_change")
                                    # No change needed or possible
                                    ;;
                                "failed"|"invalid")
                                    ((failed_count++))
                                    ;;
                            esac
                        fi
                    done
                    
                    echo
                    print_status "Configuration summary:"
                    print_status "  - VMs processed: $processed_count"
                    print_status "  - CPU pinning added: $configured_count"
                    print_status "  - CPU pinning removed: $removed_count"
                    print_status "  - Status only viewed: $status_only_count"
                    print_status "  - VMs skipped: $skipped_count"
                    if [[ $failed_count -gt 0 ]]; then
                        print_status "  - Operations failed: $failed_count"
                    fi
                    
                else
                    # Process single VM with interactive menu
                    echo
                    print_status "Processing VM: $vm_selection"
                    
                    # Show current status first
                    show_vm_cpu_pinning_status "$vm_selection"
                    
                    # Show action menu and capture result
                    local action_result
                    action_result=$(show_vm_action_menu "$vm_selection")
                    local menu_exit_code=$?
                    
                    case "$action_result" in
                        "added"|"removed")
                            changes_made=true
                            ;;
                        "status_only"|"skipped"|"no_change")
                            # No changes made
                            ;;
                        "failed"|"invalid")
                            print_error "Failed to process VM '$vm_selection'"
                            continue
                            ;;
                    esac
                fi
                
                # Only show success message and additional info if changes were actually made
                if [[ "$changes_made" == true ]]; then
                    echo
                    print_success "CPU pinning management completed!"
                    echo
                    print_status "Changes have been applied to the selected VM(s)"
                    print_status "Restart your VMs for the changes to take effect"
                    echo
                    print_status "7800X3D 6-Core + 6-Thread CPU Layout (when CPU pinning is enabled):"
                    print_status "  - Physical Core 0: Threads 0,8   → Host OS + QEMU emulator"
                    print_status "  - Physical Core 1: Threads 1,9   → Host OS + QEMU emulator"
                    print_status "  - Physical Core 2: Threads 2,10  → VM vCPUs 0,1"
                    print_status "  - Physical Core 3: Threads 3,11  → VM vCPUs 2,3"
                    print_status "  - Physical Core 4: Threads 4,12  → VM vCPUs 4,5"
                    print_status "  - Physical Core 5: Threads 5,13  → VM vCPUs 6,7"
                    print_status "  - Physical Core 6: Threads 6,14  → VM vCPUs 8,9"
                    print_status "  - Physical Core 7: Threads 7,15  → VM vCPUs 10,11"
                    echo
                    print_status "Benefits of CPU pinning with SMT:"
                    print_status "  - Prevents VM crashes during intensive workloads"
                    print_status "  - Reduces CPU context switching overhead"
                    print_status "  - Improves VM responsiveness and stability"
                    print_status "  - Better performance isolation from host system"
                    print_status "  - Better utilization of hyperthreaded cores"
                else
                    echo
                    print_status "No changes were made to any VMs"
                    print_status "Use the menu options to add or remove CPU pinning as needed"
                fi
                ;;
            5)
                show_cpu_pinning_info
                ;;
            6)
                print_status "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-6."
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Run main function
main "$@"
