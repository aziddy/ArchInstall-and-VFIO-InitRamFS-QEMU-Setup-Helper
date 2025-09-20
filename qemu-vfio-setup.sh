#!/bin/bash

# QEMU VFIO GPU Passthrough Setup Script for Arch Linux
# Interactive script to set up QEMU with Nvidia GPU passthrough for Windows VMs

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/qemu-vfio-setup.log"
BACKUP_DIR="/etc/backup-$(date +%Y%m%d-%H%M%S)"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
    log "INFO: $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log "WARNING: $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log "ERROR: $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Check if sudo is available
check_sudo() {
    if ! command -v sudo &> /dev/null; then
        print_error "sudo is not installed. Please install it first: pacman -S sudo"
        exit 1
    fi
}

# Check if we're on Arch Linux
check_arch() {
    if ! command -v pacman &> /dev/null; then
        print_error "This script is designed for Arch Linux. pacman package manager not found."
        exit 1
    fi
}

# Create backup directory
create_backup() {
    print_status "Creating backup directory: $BACKUP_DIR"
    sudo mkdir -p "$BACKUP_DIR"
}

# Function to install virtualization packages
install_packages() {
    print_header "Installing Virtualization Packages"
    
    print_status "Installing QEMU and related packages..."
    sudo pacman -S qemu-full virt-manager libvirt edk2-ovmf bridge-utils dnsmasq vde2 openbsd-netcat iptables-nft
    
    print_status "Enabling and starting libvirt service..."
    sudo systemctl enable --now libvirtd
    
    print_status "Adding user to libvirt group..."
    sudo usermod -a -G libvirt "$USER"
    
    print_status "Checking virtualization support..."
    if lscpu | grep -q Virtualization; then
        print_status "✓ Virtualization support detected"
    else
        print_warning "Virtualization support not detected in CPU. This may cause issues."
    fi
    
    if lsmod | grep -q kvm; then
        print_status "✓ KVM module loaded"
    else
        print_warning "KVM module not loaded. You may need to reboot after installation."
    fi
    
    print_status "Package installation completed!"
}

# Function to detect CPU vendor
detect_cpu_vendor() {
    if lscpu | grep -qi "intel"; then
        echo "intel"
    elif lscpu | grep -qi "amd"; then
        echo "amd"
    else
        echo "unknown"
    fi
}

# Function to Update GRUB to enable/configure IOMMU - Step 2
configure_iommu() {
    print_header "Update GRUB to enable/configure IOMMU"
    
    local cpu_vendor=$(detect_cpu_vendor)
    print_status "Detected CPU vendor: $cpu_vendor"
    
    # Create backup of grub config
    create_backup
    sudo cp /etc/default/grub "$BACKUP_DIR/grub.backup"
    
    print_status "Backing up current GRUB configuration..."
    
    # Read current GRUB config
    local grub_file="/etc/default/grub"
    local temp_file="/tmp/grub_temp"
    
    # Create the IOMMU parameters based on CPU vendor
    local iommu_params=""
    case $cpu_vendor in
        "intel")
            iommu_params="intel_iommu=on iommu=pt"
            ;;
        "amd")
            iommu_params="amd_iommu=on iommu=pt"
            ;;
        *)
            print_error "Unknown CPU vendor. Please configure IOMMU manually."
            return 1
            ;;
    esac
    
    print_status "Adding IOMMU parameters: $iommu_params"
    
    # Modify GRUB configuration
    sudo cp "$grub_file" "$temp_file"
    
    # Check if IOMMU is already configured
    if grep -q "iommu=" "$grub_file"; then
        print_warning "IOMMU parameters already found in GRUB config. Manual review recommended."
        echo "Current GRUB_CMDLINE_LINUX_DEFAULT:"
        grep "GRUB_CMDLINE_LINUX_DEFAULT" "$grub_file"
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Skipping IOMMU configuration."
            return 0
        fi
    fi
    
    # Add IOMMU parameters to GRUB_CMDLINE_LINUX_DEFAULT
    sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\".*\"/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet $iommu_params\"/" "$temp_file"
    
    # Update the actual grub file
    sudo mv "$temp_file" "$grub_file"
    
    print_status "Updating GRUB configuration..."
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    
    print_warning "IOMMU configuration completed. A reboot is required for changes to take effect."
    print_status "After reboot, run this script again and select 'Check IOMMU Groups' to verify the setup."
}

# Function to create IOMMU checker script
create_iommu_checker() {
    print_header "Creating IOMMU Groups Checker"
    
    local checker_script="$HOME/check_iommu.sh"
    
    cat > "$checker_script" << 'EOF'
#!/bin/bash
# IOMMU Groups Checker Script
# This script displays all IOMMU groups and their devices

shopt -s nullglob
for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V); do
    echo "IOMMU Group ${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ${d##*/})"
    done;
done;
EOF
    
    chmod +x "$checker_script"
    print_status "IOMMU checker script created at: $checker_script"
    
    # Run the checker
    print_status "Running IOMMU groups check..."
    "$checker_script"
    
    print_warning "Look for your NVIDIA GPU in the output above."
    print_warning "Note the [vendor:device] IDs (e.g., 10de:2783) for your GPU and its audio device."
}

# Function to get GPU device IDs
get_gpu_ids() {
    print_status "Identifying NVIDIA GPU device IDs..."
    
    local gpu_info=$(lspci -nnk | grep -i nvidia)
    if [[ -z "$gpu_info" ]]; then
        print_error "No NVIDIA GPU found. Please ensure your GPU is properly installed."
        return 1
    fi
    
    echo "Found NVIDIA GPU(s):"
    echo "$gpu_info"
    
    # Extract device IDs
    local device_ids=$(echo "$gpu_info" | grep -o '[0-9a-f][0-9a-f][0-9a-f][0-9a-f]:[0-9a-f][0-9a-f][0-9a-f][0-9a-f]' | tr '\n' ',' | sed 's/,$//')
    
    if [[ -n "$device_ids" ]]; then
        print_status "Extracted device IDs: $device_ids"
        echo "$device_ids"
    else
        print_error "Could not extract device IDs from GPU information."
        return 1
    fi
}

# Function to configure VFIO for GPU Passthrough - Step 4
configure_vfio() {
    print_header "Configuring VFIO for GPU Passthrough"
    
    # Get GPU device IDs
    local device_ids
    device_ids=$(get_gpu_ids)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    print_status "Configuring VFIO with device IDs: $device_ids"
    
    # Create VFIO configuration file
    print_status "Creating VFIO configuration file..."
    sudo tee /etc/modprobe.d/vfio.conf > /dev/null << EOF
options vfio-pci ids=$device_ids
softdep nvidia pre: vfio-pci
softdep nouveau pre: vfio-pci
EOF
    
    # Update GRUB to include VFIO parameters
    print_status "Updating GRUB configuration with VFIO parameters..."
    local grub_file="/etc/default/grub"
    local temp_file="/tmp/grub_vfio"
    
    sudo cp "$grub_file" "$temp_file"
    
    # Add VFIO parameters to existing GRUB_CMDLINE_LINUX_DEFAULT
    sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\".*\"/& vfio-pci.ids=$device_ids/" "$temp_file"
    
    sudo mv "$temp_file" "$grub_file"
    
    print_status "Updating GRUB configuration..."
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    
    print_status "VFIO configuration completed!"
}

# Function to configure initramfs
configure_initramfs() {
    print_header "Configuring initramfs for VFIO"
    
    # Create backup of mkinitcpio.conf
    create_backup
    sudo cp /etc/mkinitcpio.conf "$BACKUP_DIR/mkinitcpio.conf.backup"
    
    print_status "Backing up current mkinitcpio configuration..."
    
    # Modify mkinitcpio.conf
    print_status "Modifying mkinitcpio configuration..."
    local mkinitcpio_file="/etc/mkinitcpio.conf"
    local temp_file="/tmp/mkinitcpio_temp"
    
    sudo cp "$mkinitcpio_file" "$temp_file"
    
    # Update MODULES line
    sudo sed -i 's/^MODULES=.*/MODULES=(vfio_pci vfio vfio_iommu_type1)/' "$temp_file"
    
    # Ensure HOOKS line is correct (should already be fine)
    sudo sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/' "$temp_file"
    
    sudo mv "$temp_file" "$mkinitcpio_file"
    
    print_status "Rebuilding initramfs..."
    sudo mkinitcpio -P
    
    print_status "Updating GRUB configuration..."
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    
    print_warning "initramfs configuration completed. A reboot is required for changes to take effect."
}

# Function to prepare second SSD
prepare_second_ssd() {
    print_header "Preparing Second SSD for Windows VM"
    
    print_status "Available storage devices:"
    lsblk
    
    echo
    print_warning "Please identify your second SSD from the list above."
    read -p "Enter the device path (e.g., /dev/sdb, /dev/nvme1n1): " device_path
    
    if [[ ! -b "$device_path" ]]; then
        print_error "Device $device_path does not exist or is not a block device."
        return 1
    fi
    
    print_warning "This will wipe the device $device_path. All data will be lost!"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Unmounting device if mounted..."
        sudo umount "${device_path}"* 2>/dev/null || true
        
        print_status "Wiping device (first 100MB)..."
        sudo dd if=/dev/zero of="$device_path" bs=1M count=100 status=progress
        
        print_status "Device $device_path prepared for Windows VM."
        print_warning "Remember to use this device when creating your VM in virt-manager."
    else
        print_status "Skipping device preparation."
    fi
}

# Function to show virt-manager guidance
show_vm_creation_guide() {
    print_header "VM Creation Guide for virt-manager"
    
    cat << 'EOF'
To create your Windows VM with GPU passthrough:

1. Launch virt-manager:
   virt-manager

2. Create New Virtual Machine:
   - Local install media → Browse to Windows ISO
   - Memory: 8GB+ RAM recommended
   - CPUs: 4+ cores recommended

3. Storage Configuration:
   - Uncheck "Enable storage for this virtual machine"
   - After creation: Add Hardware → Storage
   - Device type: "Select or create custom storage"
   - Browse to your second SSD device (e.g., /dev/sdb)
   - Bus type: VirtIO (for best performance)

4. Before finishing: Check "Customize configuration before install"

5. Machine Configuration:
   - Firmware: Change from "BIOS" to "UEFI"
   - Select: UEFI x86_64: /usr/share/edk2-ovmf/x64/OVMF_CODE.fd

6. CPU Configuration:
   - Check "Manually set CPU topology"
   - Check "Copy host CPU configuration"

7. Add GPU Passthrough:
   - Add Hardware → PCI Host Device
   - Select your NVIDIA GPU (both GPU and audio device)

8. Install VirtIO Drivers:
   - Add Hardware → Storage (CDROM)
   - Select VirtIO drivers ISO from /usr/share/edk2-guest-tools/

9. During Windows installation:
   - Load VirtIO drivers from the CDROM
   - Browse to: viostor → w11 → amd64

EOF

    print_status "VirtIO drivers location:"
    if [[ -d "/usr/share/edk2-guest-tools/" ]]; then
        ls -la /usr/share/edk2-guest-tools/
    else
        print_warning "VirtIO drivers not found. Install with: sudo pacman -S edk2-ovmf-guest"
    fi
}

# Function to validate system
validate_system() {
    print_header "System Validation"
    
    local errors=0
    
    # Check if running on Arch
    if ! command -v pacman &> /dev/null; then
        print_error "Not running on Arch Linux"
        ((errors++))
    fi
    
    # Check if libvirt is running
    if ! systemctl is-active --quiet libvirtd; then
        print_error "libvirt service is not running"
        ((errors++))
    else
        print_status "✓ libvirt service is running"
    fi
    
    # Check if user is in libvirt group
    if ! groups | grep -q libvirt; then
        print_warning "User not in libvirt group. You may need to log out and back in."
    else
        print_status "✓ User is in libvirt group"
    fi
    
    # Check IOMMU support
    if ! dmesg | grep -q "IOMMU enabled"; then
        print_warning "IOMMU may not be enabled. Check if you've rebooted after configuration."
    else
        print_status "✓ IOMMU appears to be enabled"
    fi
    
    # Check VFIO modules
    if ! lsmod | grep -q vfio; then
        print_warning "VFIO modules not loaded. This is normal if you haven't rebooted yet."
    else
        print_status "✓ VFIO modules loaded"
    fi
    
    if [[ $errors -eq 0 ]]; then
        print_status "System validation passed!"
    else
        print_error "System validation found $errors error(s). Please address them before proceeding."
    fi
}

# Function to show main menu
show_menu() {
    clear
    print_header "QEMU VFIO GPU Passthrough Setup"
    echo
    echo "This script will help you set up QEMU with Nvidia GPU passthrough for Windows VMs."
    echo
    echo "1) Install Virtualization Packages"
    echo "2) Update GRUB to enable/configure IOMMU"
    echo "3) Check IOMMU Groups (Manually Identify IOMMU Group"
    echo "   with your GPU and GPU Audio Device IDs)"
    echo "4) Configure VFIO for GPU Passthrough (Auto Finds"
    echo "   GPU and GPU Audio Device IDs if IOMMU is enabled)"
    echo "5) Configure initramfs (Lets VIFO claim devices before other OS drivers)"
    print_warning "[Make sure your Monitor is plugged into your iGPU]"
    echo "6) Prepare Other SSD (Setting up Another Physical"
    echo "   Drive for Windows VM Storage) [Unmount & Wipe]"
    echo "7) Show VM Creation Guide (virt-manager)"
    echo "8) Validate System"
    echo "9) Run Complete Setup (Steps 1-6)"
    echo "0) Exit"
    echo
}

# Main function
main() {
    # Initial checks
    check_root
    check_sudo
    check_arch
    
    print_status "Starting QEMU VFIO Setup Script"
    print_status "Log file: $LOG_FILE"
    
    while true; do
        show_menu
        read -p "Select an option (0-9): " choice
        
        case $choice in
            1)
                install_packages
                ;;
            2)
                configure_iommu
                ;;
            3)
                create_iommu_checker
                ;;
            4)
                configure_vfio
                ;;
            5)
                configure_initramfs
                ;;
            6)
                prepare_second_ssd
                ;;
            7)
                show_vm_creation_guide
                ;;
            8)
                validate_system
                ;;
            9)
                print_header "Running Complete Setup"
                install_packages
                configure_iommu
                create_iommu_checker
                configure_vfio
                configure_initramfs
                prepare_second_ssd
                print_status "Complete setup finished! Please reboot and then run validation."
                ;;
            0)
                print_status "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 0-9."
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Run main function
main "$@"
