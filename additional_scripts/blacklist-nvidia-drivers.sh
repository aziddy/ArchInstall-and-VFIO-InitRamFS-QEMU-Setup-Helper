#!/bin/bash

# NVIDIA Driver Blacklist Management Script
# Based on "Prevent Crashing on Hard Workloads QEMU Windows VM.md" section 4
# This script manages NVIDIA driver blacklisting to prevent conflicts with VFIO passthrough

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

# Function to check for NVIDIA conflict messages in dmesg
check_nvidia_conflicts() {
    print_status "Checking for NVIDIA driver conflicts in system logs..."
    
    # Patterns to look for in dmesg
    local conflict_patterns=(
        "nvidia-nvlink: Unregistered Nvlink Core"
        "nvidia-nvlink: Nvlink Core is being initialized"
        "NVRM: GPU.*is already bound to vfio-pci"
        "NVRM: The NVIDIA probe routine was not called"
        "NVRM: This can occur when another driver was loaded"
        "NVRM: Try unloading the conflicting kernel module"
        "NVRM: No NVIDIA devices probed"
    )
    
    local conflicts_found=false
    local conflict_messages=()
    
    # Check recent dmesg for conflict patterns
    local recent_dmesg=$(dmesg | tail -500)
    
    for pattern in "${conflict_patterns[@]}"; do
        local matches=$(echo "$recent_dmesg" | grep -i "$pattern" || true)
        if [[ -n "$matches" ]]; then
            conflicts_found=true
            while IFS= read -r line; do
                [[ -n "$line" ]] && conflict_messages+=("$line")
            done <<< "$matches"
        fi
    done
    
    if [[ "$conflicts_found" == "true" ]]; then
        print_warning "NVIDIA driver conflicts detected in system logs!"
        echo
        print_error "Conflict messages found:"
        for msg in "${conflict_messages[@]}"; do
            echo "  $msg"
        done
        echo
        print_warning "These conflicts indicate that NVIDIA drivers are trying to bind to your GPU"
        print_warning "while VFIO-PCI has already claimed it. This can cause VM instability."
        echo
        return 0
    else
        print_success "No recent NVIDIA driver conflicts found in system logs"
        return 1
    fi
}

# Function to check current NVIDIA driver status
check_nvidia_driver_status() {
    print_status "Checking current NVIDIA driver status..."
    
    # Check if NVIDIA modules are loaded
    local loaded_modules=$(lsmod | grep -i nvidia || true)
    
    if [[ -n "$loaded_modules" ]]; then
        print_warning "NVIDIA modules currently loaded:"
        echo "$loaded_modules" | while read -r line; do
            echo "  $line"
        done
        echo
        return 0
    else
        print_success "No NVIDIA modules currently loaded"
        return 1
    fi
}

# Function to check current blacklist status
check_blacklist_status() {
    print_status "Checking current NVIDIA driver blacklist status..."
    
    local blacklist_files=(
        "/etc/modprobe.d/blacklist-nvidia.conf"
        "/etc/modprobe.d/vfio.conf"
    )
    
    local blacklisted_drivers=()
    local blacklist_found=false
    
    for file in "${blacklist_files[@]}"; do
        if [[ -f "$file" ]]; then
            local blacklisted=$(grep -E "^blacklist.*nvidia|^blacklist.*nouveau" "$file" 2>/dev/null || true)
            if [[ -n "$blacklisted" ]]; then
                blacklist_found=true
                print_success "Found blacklist configuration in: $file"
                echo "$blacklisted" | while read -r line; do
                    echo "  $line"
                done
                echo
            fi
        fi
    done
    
    if [[ "$blacklist_found" == "false" ]]; then
        print_warning "No NVIDIA driver blacklist configuration found"
        return 1
    fi
    
    return 0
}

# Function to check GPU binding status
check_gpu_binding() {
    print_status "Checking GPU binding status..."
    
    # Find NVIDIA GPUs
    local nvidia_gpus=$(lspci -nn | grep -i nvidia || true)
    
    if [[ -z "$nvidia_gpus" ]]; then
        print_warning "No NVIDIA GPUs detected in system"
        return 1
    fi
    
    print_status "NVIDIA GPUs found:"
    echo "$nvidia_gpus" | while read -r line; do
        echo "  $line"
    done
    echo
    
    # Check detailed binding information
    print_status "GPU driver binding details:"
    lspci -nnk | grep -A3 -B1 NVIDIA | while read -r line; do
        echo "  $line"
    done
    echo
    
    return 0
}

# Function to create NVIDIA blacklist configuration
create_blacklist_config() {
    local blacklist_file="/etc/modprobe.d/blacklist-nvidia.conf"
    local vfio_file="/etc/modprobe.d/vfio.conf"
    
    print_status "Creating NVIDIA driver blacklist configuration..."
    
    # Create blacklist-nvidia.conf only if it doesn't exist or is different
    if [[ ! -f "$blacklist_file" ]]; then
        cat > "$blacklist_file" << 'EOF'
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
blacklist nouveau
EOF
        print_success "Created: $blacklist_file"
    else
        print_warning "File already exists: $blacklist_file"
    fi
    
    # Update or create vfio.conf
    if [[ -f "$vfio_file" ]]; then
        # Backup existing vfio.conf
        local backup_file="${vfio_file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$vfio_file" "$backup_file"
        print_status "Created backup: $backup_file"
        
        # Check and add each blacklist entry individually
        local entries_added=false
        local blacklist_entries=("nvidia" "nvidia_drm" "nvidia_modeset" "nvidia_uvm" "nouveau")
        
        for entry in "${blacklist_entries[@]}"; do
            if ! grep -q "^blacklist $entry" "$vfio_file" 2>/dev/null; then
                echo "blacklist $entry" >> "$vfio_file"
                entries_added=true
                print_status "Added: blacklist $entry"
            fi
        done
        
        # Check and add softdep entries individually
        local softdep_entries=("nvidia" "nvidia_drm" "nouveau")
        
        for entry in "${softdep_entries[@]}"; do
            if ! grep -q "^softdep $entry pre: vfio-pci" "$vfio_file" 2>/dev/null; then
                echo "softdep $entry pre: vfio-pci" >> "$vfio_file"
                entries_added=true
                print_status "Added: softdep $entry pre: vfio-pci"
            fi
        done
        
        if [[ "$entries_added" == "true" ]]; then
            print_success "Updated existing vfio.conf with missing entries"
        else
            print_warning "All blacklist entries already exist in vfio.conf"
            rm "$backup_file"  # Remove backup since no changes were made
        fi
    else
        print_status "Creating new vfio.conf..."
        cat > "$vfio_file" << 'EOF'
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
blacklist nouveau
softdep nvidia pre: vfio-pci
softdep nvidia_drm pre: vfio-pci
softdep nouveau pre: vfio-pci
EOF
        print_success "Created: $vfio_file"
        print_warning "Note: You may need to add your GPU device IDs to vfio.conf manually"
    fi
}

# Function to remove NVIDIA blacklist configuration
remove_blacklist_config() {
    local blacklist_file="/etc/modprobe.d/blacklist-nvidia.conf"
    local vfio_file="/etc/modprobe.d/vfio.conf"
    
    print_status "Removing NVIDIA driver blacklist configuration..."
    
    # Remove blacklist-nvidia.conf
    if [[ -f "$blacklist_file" ]]; then
        rm "$blacklist_file"
        print_success "Removed: $blacklist_file"
    else
        print_warning "File not found: $blacklist_file"
    fi
    
    # Remove blacklist entries from vfio.conf
    if [[ -f "$vfio_file" ]]; then
        local backup_file="${vfio_file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$vfio_file" "$backup_file"
        print_status "Created backup: $backup_file"
        
        # Remove blacklist and softdep lines
        sed -i '/^blacklist nvidia/d' "$vfio_file"
        sed -i '/^blacklist nouveau/d' "$vfio_file"
        sed -i '/^softdep nvidia/d' "$vfio_file"
        sed -i '/^softdep nouveau/d' "$vfio_file"
        sed -i '/^# Prevent loading of conflicting drivers/d' "$vfio_file"
        sed -i '/^# Ensure VFIO loads before conflicting drivers/d' "$vfio_file"
        
        # Remove empty lines that might be left
        sed -i '/^$/N;/^\n$/d' "$vfio_file"
        
        print_success "Removed blacklist entries from vfio.conf"
    else
        print_warning "File not found: $vfio_file"
    fi
}

# Function to update system configuration
update_system_config() {
    print_status "Updating system configuration..."
    
    # Rebuild initramfs
    print_status "Rebuilding initramfs..."
    if mkinitcpio -P; then
        print_success "Initramfs rebuilt successfully"
    else
        print_error "Failed to rebuild initramfs"
        return 1
    fi
    
    # Update GRUB configuration
    print_status "Updating GRUB configuration..."
    if grub-mkconfig -o /boot/grub/grub.cfg; then
        print_success "GRUB configuration updated successfully"
    else
        print_error "Failed to update GRUB configuration"
        return 1
    fi
    
    print_warning "System configuration updated. Reboot required for changes to take effect."
}

# Function to show information about blacklisting
show_blacklist_info() {
    echo
    print_status "NVIDIA Driver Blacklisting Information:"
    echo
    echo "Why blacklist NVIDIA drivers on the host?"
    echo "  - Prevents conflicts with VFIO-PCI driver binding"
    echo "  - Stops failed probe attempts that can leave GPU in bad state"
    echo "  - Eliminates power management conflicts"
    echo "  - Improves GPU reset capabilities for VM usage"
    echo
    echo "What gets blacklisted:"
    echo "  - nvidia: Main NVIDIA driver"
    echo "  - nvidia_drm: Direct Rendering Manager component"
    echo "  - nvidia_modeset: Mode setting component"
    echo "  - nvidia_uvm: Unified Virtual Memory component"
    echo "  - nouveau: Open source NVIDIA driver"
    echo
    echo "Files modified:"
    echo "  - /etc/modprobe.d/blacklist-nvidia.conf (created)"
    echo "  - /etc/modprobe.d/vfio.conf (updated/created)"
    echo
}

# Function to get user choice
get_user_choice() {
    echo
    print_status "Available actions:"
    echo "  1. Blacklist NVIDIA drivers (recommended for VFIO setups)"
    echo "  2. Remove NVIDIA driver blacklist (restore normal operation)"
    echo "  3. Show current status only"
    echo "  4. Exit"
    echo
    
    while true; do
        read -p "Enter your choice (1-4): " choice
        case $choice in
            1)
                echo "blacklist"
                return 0
                ;;
            2)
                echo "unblacklist"
                return 0
                ;;
            3)
                echo "status"
                return 0
                ;;
            4)
                echo "exit"
                return 0
                ;;
            *)
                print_error "Invalid choice. Please enter 1, 2, 3, or 4."
                ;;
        esac
    done
}

# Function to verify changes after reboot
show_verification_commands() {
    echo
    print_status "After reboot, verify the changes with these commands:"
    echo
    echo "Check that no NVIDIA modules are loaded:"
    echo "  lsmod | grep nvidia"
    echo
    echo "Check GPU binding status:"
    echo "  lspci -nnk | grep -A3 -B1 NVIDIA"
    echo
    echo "Check for conflict messages (should be clean):"
    echo "  sudo dmesg | grep -i nvidia"
    echo
}

# Main function
main() {
    echo "=========================================="
    echo "NVIDIA Driver Blacklist Management Script"
    echo "=========================================="
    echo
    
    check_root
    
    # Always check for conflicts first
    local conflicts_detected=false
    if check_nvidia_conflicts; then
        conflicts_detected=true
    fi
    
    echo
    check_nvidia_driver_status || true
    echo
    set +e  # Temporarily disable exit on error
    check_blacklist_status
    local blacklist_exists=$?
    set -e  # Re-enable exit on error
    echo
    check_gpu_binding || true
    
    show_blacklist_info
    
    # Show warning if conflicts were detected
    if [[ "$conflicts_detected" == "true" ]]; then
        echo
        print_error "⚠️  NVIDIA DRIVER CONFLICTS DETECTED ⚠️"
        print_error "Your system logs show NVIDIA drivers conflicting with VFIO-PCI."
        print_error "This can cause VM crashes and instability during gaming."
        print_warning "Blacklisting NVIDIA drivers is strongly recommended."
        echo
    fi
    
    # Get user choice
    echo
    print_status "Available actions:"
    echo "  1. Blacklist NVIDIA drivers (recommended for VFIO setups)"
    echo "  2. Remove NVIDIA driver blacklist (restore normal operation)"
    echo "  3. Show current status only"
    echo "  4. Exit"
    echo
    
    local user_choice
    while true; do
        read -p "Enter your choice (1-4): " choice
        case $choice in
            1)
                user_choice="blacklist"
                break
                ;;
            2)
                user_choice="unblacklist"
                break
                ;;
            3)
                user_choice="status"
                break
                ;;
            4)
                user_choice="exit"
                break
                ;;
            *)
                print_error "Invalid choice. Please enter 1, 2, 3, or 4."
                ;;
        esac
    done
    
    case "$user_choice" in
        "blacklist")
            if [[ $blacklist_exists -eq 0 ]]; then
                print_warning "NVIDIA drivers appear to already be blacklisted."
                read -p "Do you want to recreate the blacklist configuration? (y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    create_blacklist_config
                    update_system_config
                    show_verification_commands
                else
                    print_status "No changes made."
                fi
            else
                create_blacklist_config
                update_system_config
                show_verification_commands
            fi
            ;;
        "unblacklist")
            if [[ $blacklist_exists -eq 0 ]]; then
                print_warning "This will remove NVIDIA driver blacklisting."
                print_warning "NVIDIA drivers will be able to load on the host again."
                read -p "Are you sure you want to continue? (y/N): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    remove_blacklist_config
                    update_system_config
                    print_warning "NVIDIA drivers are no longer blacklisted."
                    print_warning "They may bind to your GPU after reboot."
                else
                    print_status "No changes made."
                fi
            else
                print_warning "NVIDIA drivers don't appear to be blacklisted."
                print_status "No changes needed."
            fi
            ;;
        "status")
            print_status "Current status check completed. No changes made."
            ;;
        "exit")
            print_status "Exiting without making changes."
            exit 0
            ;;
    esac
    
    echo
    print_success "NVIDIA driver blacklist management completed!"
    
    if [[ "$user_choice" == "blacklist" ]] || [[ "$user_choice" == "unblacklist" ]]; then
        echo
        print_warning "IMPORTANT: Reboot your system for changes to take effect"
        print_status "After reboot, your VFIO passthrough setup should be more stable"
    fi
}

# Run main function
main "$@"
