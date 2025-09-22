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
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
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

# Function to install virtualization packages - Step 1
install_packages() {
    print_header "Installing Virtualization Packages"
    
    print_status "Installing QEMU and related packages..."
    sudo pacman -S qemu-full virt-manager libvirt edk2-ovmf bridge-utils dnsmasq vde2 openbsd-netcat iptables-nft ntfs-3g dosfstools
    
    print_status "Enabling and starting libvirt service..."
    sudo systemctl enable --now libvirtd
    
    print_status "Adding user to libvirt group..."
    sudo usermod -a -G libvirt "$USER"
    
    # Install Looking Glass client
    print_status "Installing Looking Glass client..."
    if command -v yay &> /dev/null; then
        print_status "Installing Looking Glass from AUR using yay..."
        yay -S looking-glass
    else
        print_warning "yay not found. Please install Looking Glass manually:"
        echo "git clone https://aur.archlinux.org/yay.git"
        echo "cd yay && makepkg -si"
        echo "yay -S looking-glass"
    fi
    
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

# Function to get GPU device IDs (silent version for command substitution)
get_gpu_ids_silent() {
    local gpu_info=$(lspci -nnk | grep -i nvidia)
    if [[ -z "$gpu_info" ]]; then
        return 1
    fi
    
    # Extract device IDs (only the main PCI device IDs, not subsystem IDs)
    # Look for the pattern [vendor:device] in the main device lines, not subsystem lines
    local device_ids=$(echo "$gpu_info" | grep -E 'VGA compatible controller|Audio device' | grep -o '\[[0-9a-f][0-9a-f][0-9a-f][0-9a-f]:[0-9a-f][0-9a-f][0-9a-f][0-9a-f]\]' | sed 's/\[//g; s/\]//g' | tr '\n' ',' | sed 's/,$//')
    
    if [[ -n "$device_ids" ]]; then
        echo "$device_ids"
    else
        return 1
    fi
}

# Function to get GPU device IDs (with user output)
get_gpu_ids() {
    print_status "Identifying NVIDIA GPU device IDs..."
    
    local gpu_info=$(lspci -nnk | grep -i nvidia)
    if [[ -z "$gpu_info" ]]; then
        print_error "No NVIDIA GPU found. Please ensure your GPU is properly installed."
        return 1
    fi
    
    # Display GPU info for user reference
    echo "Found NVIDIA GPU(s):" >&2
    echo "$gpu_info" >&2
    
    # Get device IDs using silent function
    local device_ids=$(get_gpu_ids_silent)
    if [[ $? -ne 0 ]]; then
        print_error "Could not extract device IDs from GPU information."
        return 1
    fi
    
    print_status "Extracted device IDs: $device_ids"
    echo "$device_ids"
}

# Function to configure VFIO for GPU Passthrough - Step 4
configure_vfio() {
    print_header "Configuring VFIO for GPU Passthrough"
    
    # Clean up any corrupted VFIO configuration file
    if [[ -f /etc/modprobe.d/vfio.conf ]]; then
        print_status "Cleaning up existing VFIO configuration file..."
        sudo rm -f /etc/modprobe.d/vfio.conf
    fi
    
    # Get GPU device IDs using silent function
    local device_ids
    device_ids=$(get_gpu_ids_silent)
    if [[ $? -ne 0 ]]; then
        print_error "Could not extract device IDs from GPU information."
        return 1
    fi
    
    print_status "Configuring VFIO with device IDs: $device_ids"
    
    # Validate device IDs format
    if [[ ! "$device_ids" =~ ^[0-9a-f]{4}:[0-9a-f]{4}(,[0-9a-f]{4}:[0-9a-f]{4})*$ ]]; then
        print_error "Invalid device IDs format: $device_ids"
        return 1
    fi
    
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
    
    # Check if VFIO parameters are already present
    if grep -q "vfio-pci.ids" "$temp_file"; then
        print_warning "VFIO parameters already present in GRUB configuration"
        print_status "Updating VFIO device IDs..."
        # Replace existing VFIO parameters with new ones (more specific pattern)
        sudo sed -i "s|vfio-pci\.ids=[^[:space:]\"]*|vfio-pci.ids=$device_ids|g" "$temp_file"
    else
        print_status "Adding VFIO parameters to GRUB configuration..."
        # Add VFIO parameters to existing GRUB_CMDLINE_LINUX_DEFAULT
        if ! sudo sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 vfio-pci.ids=$device_ids\"|" "$temp_file"; then
            print_error "Failed to update GRUB configuration with VFIO parameters"
            rm -f "$temp_file"
            return 1
        fi
    fi
    
    # Apply the changes
    sudo mv "$temp_file" "$grub_file"
    
    print_status "Updating GRUB configuration..."
    if sudo grub-mkconfig -o /boot/grub/grub.cfg; then
        print_status "GRUB configuration updated successfully"
    else
        print_error "Failed to update GRUB configuration"
        return 1
    fi
    
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

# Function to prepare second SSD with partitioning options
prepare_second_ssd() {
    print_header "Preparing Second SSD for VM Storage"
    
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
        
        # Ask about partitioning
        echo
        print_status "Partitioning options:"
        echo "1) Use entire drive for single VM (recommended for beginners)"
        echo "2) Create multiple partitions for different VMs"
        echo "3) Create EFI + multiple Windows partitions (recommended for multiple Windows VMs)"
        echo "4) Skip partitioning (use raw device)"
        
        read -p "Select partitioning option (1-4): " partition_choice
        
        case $partition_choice in
            1)
                create_single_partition "$device_path"
                ;;
            2)
                create_multiple_partitions "$device_path"
                ;;
            3)
                create_efi_windows_partitions "$device_path"
                ;;
            4)
                print_status "Skipping partitioning. Using raw device."
                print_warning "Remember to use this raw device when creating your VM in virt-manager."
                ;;
            *)
                print_warning "Invalid choice. Skipping partitioning."
                ;;
        esac
        
        print_status "Device $device_path preparation completed!"
    else
        print_status "Skipping device preparation."
    fi
}

# Function to check and install required formatting tools
check_formatting_tools() {
    local missing_tools=()
    
    if ! command -v mkfs.ntfs &> /dev/null; then
        missing_tools+=("ntfs-3g")
    fi
    
    if ! command -v mkfs.fat &> /dev/null; then
        missing_tools+=("dosfstools")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_status "Installing missing formatting tools: ${missing_tools[*]}..."
        sudo pacman -S --noconfirm "${missing_tools[@]}"
    fi
}

# Function to create a single partition
create_single_partition() {
    local device_path="$1"
    local partition_path
    
    # Determine correct partition path based on device type
    if [[ "$device_path" =~ nvme ]]; then
        partition_path="${device_path}p1"
    else
        partition_path="${device_path}1"
    fi
    
    print_status "Creating single partition on $device_path..."
    
    # Check and install formatting tools
    check_formatting_tools
    
    # Create GPT partition table
    sudo parted "$device_path" mklabel gpt
    
    # Create single partition using entire disk
    sudo parted "$device_path" mkpart primary 0% 100%
    
    # Format with NTFS for Windows compatibility
    print_status "Formatting partition with NTFS..."
    if command -v mkfs.ntfs &> /dev/null; then
        sudo mkfs.ntfs -f -L "WindowsVM" "$partition_path"
    else
        print_error "mkfs.ntfs not found. Installing ntfs-3g..."
        sudo pacman -S --noconfirm ntfs-3g
        sudo mkfs.ntfs -f -L "WindowsVM" "$partition_path"
    fi
    
    print_status "Single partition created: $partition_path"
    print_warning "Use $partition_path when creating your VM in virt-manager."
}

# Function to create multiple partitions
create_multiple_partitions() {
    local device_path="$1"
    
    print_status "Creating multiple partitions on $device_path..."
    
    # Check and install formatting tools
    check_formatting_tools
    
    # Get device size
    local device_size=$(sudo parted "$device_path" print | grep "Disk $device_path" | awk '{print $3}')
    print_status "Device size: $device_size"
    
    # Create GPT partition table
    sudo parted "$device_path" mklabel gpt
    
    echo
    print_status "Partition setup:"
    echo "You can create up to 4 partitions for different VMs."
    echo "Each partition will be formatted with NTFS for Windows compatibility."
    
    local partition_count=0
    local current_start="0%"
    
    while [[ $partition_count -lt 4 ]]; do
        echo
        read -p "Create partition $((partition_count + 1))? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            partition_count=$((partition_count + 1))
            local partition_path
            
            # Determine correct partition path based on device type
            if [[ "$device_path" =~ nvme ]]; then
                partition_path="${device_path}p$partition_count"
            else
                partition_path="${device_path}$partition_count"
            fi
            
            echo "Partition $partition_count:"
            read -p "  Size (e.g., 100GB, 50%, or remaining): " partition_size
            
            if [[ "$partition_size" == "remaining" ]] || [[ "$partition_size" == *"%" ]]; then
                local end_size="100%"
            else
                # Convert to percentage if it's a size
                local end_size="${partition_size}"
            fi
            
            # Create partition
            sudo parted "$device_path" mkpart primary "$current_start" "$end_size"
            
            # Format with NTFS
            print_status "Formatting partition $partition_count with NTFS..."
            if command -v mkfs.ntfs &> /dev/null; then
                sudo mkfs.ntfs -f -L "VM$partition_count" "$partition_path"
            else
                print_error "mkfs.ntfs not found. Installing ntfs-3g..."
                sudo pacman -S --noconfirm ntfs-3g
                sudo mkfs.ntfs -f -L "VM$partition_count" "$partition_path"
            fi
            
            print_status "Partition $partition_count created: $partition_path"
            
            # Update start for next partition
            if [[ "$end_size" != "100%" ]]; then
                current_start="$end_size"
            else
                break
            fi
        else
            break
        fi
    done
    
    if [[ $partition_count -eq 0 ]]; then
        print_warning "No partitions created. Using raw device."
    else
        print_status "Created $partition_count partition(s) on $device_path"
        
        # Show correct partition paths based on device type
        if [[ "$device_path" =~ nvme ]]; then
            print_warning "Use the specific partition (e.g., ${device_path}p1, ${device_path}p2) when creating VMs in virt-manager."
        else
            print_warning "Use the specific partition (e.g., ${device_path}1, ${device_path}2) when creating VMs in virt-manager."
        fi
    fi
}

# Function to create EFI + multiple Windows partitions
create_efi_windows_partitions() {
    local device_path="$1"
    
    print_status "Creating EFI System Partition + multiple Windows partitions..."
    
    # Check and install formatting tools
    check_formatting_tools
    
    # Get device size
    local device_size=$(sudo parted "$device_path" print | grep "Disk $device_path" | awk '{print $3}')
    print_status "Device size: $device_size"
    
    # Create GPT partition table
    sudo parted "$device_path" mklabel gpt
    
    echo
    print_status "EFI + Windows Partition Setup:"
    echo "This will create:"
    echo "1. EFI System Partition (500MB, FAT32) - Required for UEFI booting"
    echo "2. Multiple Windows partitions (NTFS) - For different Windows installations"
    echo
    
    # Create EFI System Partition (500MB)
    print_status "Creating EFI System Partition (500MB)..."
    sudo parted "$device_path" mkpart primary fat32 0% 500MB
    sudo parted "$device_path" set 1 esp on
    
    # Determine EFI partition path
    local efi_partition_path
    if [[ "$device_path" =~ nvme ]]; then
        efi_partition_path="${device_path}p1"
    else
        efi_partition_path="${device_path}1"
    fi
    
    # Format EFI partition as FAT32
    print_status "Formatting EFI partition as FAT32..."
    sudo mkfs.fat -F32 -n "EFI" "$efi_partition_path"
    
    print_status "EFI System Partition created: $efi_partition_path"
    
    # Create Windows partitions
    echo
    print_status "Now creating Windows partitions..."
    echo "You can create up to 3 Windows partitions (partitions 2-4)."
    echo "Each partition will be formatted with NTFS for Windows compatibility."
    
    local windows_partition_count=0  # Count of Windows partitions created
    local current_start="500MB"
    
    while [[ $windows_partition_count -lt 3 ]]; do
        echo
        read -p "Create Windows partition $((windows_partition_count + 1))? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            windows_partition_count=$((windows_partition_count + 1))
            local partition_number=$((windows_partition_count + 1))  # +1 because EFI is partition 1
            local partition_path
            
            # Determine correct partition path based on device type
            if [[ "$device_path" =~ nvme ]]; then
                partition_path="${device_path}p$partition_number"
            else
                partition_path="${device_path}$partition_number"
            fi
            
            echo "Windows partition $windows_partition_count:"
            read -p "  Size (e.g., 100GB, 50%, or remaining): " partition_size
            
            if [[ "$partition_size" == "remaining" ]]; then
                local end_size="100%"
            else
                local end_size="${partition_size}"
            fi
            
            # Create Windows partition
            sudo parted "$device_path" mkpart primary ntfs "$current_start" "$end_size"
            
            # Format with NTFS
            print_status "Formatting Windows partition $windows_partition_count with NTFS..."
            if command -v mkfs.ntfs &> /dev/null; then
                sudo mkfs.ntfs -f -L "Windows$windows_partition_count" "$partition_path"
            else
                print_error "mkfs.ntfs not found. Installing ntfs-3g..."
                sudo pacman -S --noconfirm ntfs-3g
                sudo mkfs.ntfs -f -L "Windows$windows_partition_count" "$partition_path"
            fi
            
            print_status "Windows partition $windows_partition_count created: $partition_path"
            
            # Update start for next partition
            if [[ "$partition_size" == "remaining" ]] || [[ "$partition_size" == "100%" ]]; then
                break
            else
                current_start="$end_size"
            fi
        else
            break
        fi
    done
    
    # Show summary
    echo
    print_status "Partition layout created:"
    print_status "EFI System Partition: $efi_partition_path (500MB, FAT32)"
    
    if [[ $windows_partition_count -gt 0 ]]; then
        print_status "Windows partitions:"
        for ((i=1; i<=windows_partition_count; i++)); do
            local partition_number=$((i + 1))  # +1 because EFI is partition 1
            if [[ "$device_path" =~ nvme ]]; then
                echo "  Windows$i: ${device_path}p$partition_number"
            else
                echo "  Windows$i: ${device_path}$partition_number"
            fi
        done
    fi
    
    print_warning "Use the specific Windows partition when creating VMs in virt-manager."
    print_warning "The EFI partition will be automatically used for UEFI booting."
}

# Function to show current partition layout
show_partition_layout() {
    print_header "Current Partition Layout"
    
    print_status "Running parted -l to show partition tables..."
    echo
    sudo parted -l
    echo
    
    print_status "Running lsblk -l to show block devices..."
    echo
    lsblk -l
    echo
    
    print_status "Partition layout displayed above."
    print_warning "Use this information to identify drives and partitions for VM setup."
}

# Function to show virt-manager guidance - step 7
show_vm_creation_guide() {
    print_header "VM Creation Guide for virt-manager"
    
    cat << 'EOF'
To create your Windows VM with GPU passthrough:

NOTE: If you created multiple partitions in step 6, you can create multiple VMs
using different partitions (e.g., /dev/sdb1 for Windows, /dev/sdb2 for Linux, etc.)

If you used option 3 (EFI + Windows partitions), you have:
- EFI System Partition (500MB, FAT32) - Required for UEFI booting
- Multiple Windows partitions (NTFS) - For different Windows installations

1. Launch virt-manager:
   virt-manager

2. Create New Virtual Machine:
   - Local install media → Browse to Windows ISO
   - Memory: 8GB+ RAM recommended
   - CPUs: 4+ cores recommended

3. Before finishing: Check "Customize configuration before install"

4. Storage Configuration:
   - Uncheck "Enable storage for this virtual machine"
   - After creation: Add Hardware → Storage
   - Device type: "Select or create custom storage"
   - Browse to your storage device:
     * Single partition: /dev/sdb1 (SATA) or /dev/nvme1n1p1 (NVMe)
     * Multiple partitions: /dev/sdb1, /dev/sdb2 (SATA) or /dev/nvme1n1p1, /dev/nvme1n1p2 (NVMe)
     * EFI + Windows: /dev/sdb2, /dev/sdb3 (SATA) or /dev/nvme1n1p2, /dev/nvme1n1p3 (NVMe)
       Note: Use Windows partitions (2,3,4...), EFI partition (1) is handled automatically
     * Raw device: /dev/sdb or /dev/nvme1n1 (if no partitioning)
   - Bus type: VirtIO (for best performance)

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
   - Select VirtIO drivers ISO from /var/lib/libvirt/images/virtio-win.iso

9. Hit "Begin Installation" in the top right corner

10. Install VirtIO Drivers during Windows installation:
   - Select "Custom" Install
   - Hit "Load Driver"
   - Hit "Browse"
   - Find your virtual drive/usb
   - Browse to: viostor/w11/amd64
   - You will be brought back to "Where do you want to install Windows?" Screen After

11. During Windows Installation Screens Following After:
    - If you want to avoid Signing in to Microsoft Account
        - Disconnect from the internet on the Microsoft Sign in screen
        - You will get a local sign-in option instead
EOF

    print_status "VirtIO drivers location:"
    if [[ -d "/usr/share/edk2-guest-tools/" ]]; then
        ls -la /usr/share/edk2-guest-tools/
    else
        print_warning "VirtIO drivers not found. Install with: sudo pacman -S edk2-ovmf-guest"
    fi
}

# Function to validate system - Step 8
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
    if [[ -d "/sys/kernel/iommu_groups" ]] && [[ "$(ls -A /sys/kernel/iommu_groups 2>/dev/null)" ]]; then
        local iommu_group_count=$(ls /sys/kernel/iommu_groups | wc -l)
        print_status "✓ IOMMU is enabled (found $iommu_group_count IOMMU groups)"
    else
        print_warning "IOMMU may not be enabled. Check if you've rebooted after configuration."
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

# Function to configure Looking Glass for VM
configure_looking_glass() {
    print_header "Configure Looking Glass for VM"
    
    print_status "Looking Glass allows you to view your VM's dGPU output on your Linux host"
    print_status "without needing a physical monitor connected to the dGPU."
    echo
    
    # Check if libvirtd is running
    if ! systemctl is-active --quiet libvirtd; then
        print_error "libvirt service is not running. Please start it first."
        return 1
    fi
    
    # Show available VMs
    print_status "Available VMs:"
    sudo virsh list --all
    
    echo
    read -p "Enter your VM name (e.g., win11): " vm_name
    
    if [[ -z "$vm_name" ]]; then
        print_error "VM name cannot be empty"
        return 1
    fi
    
    # Check if VM exists
    if ! sudo virsh list --all | grep -q "$vm_name"; then
        print_error "VM '$vm_name' not found. Please check the name and try again."
        return 1
    fi
    
    print_status "Configuring VM '$vm_name' for Looking Glass..."
    
    # Check if IVSHMEM device already exists
    print_status "Checking for existing IVSHMEM device..."
    if sudo virsh dumpxml "$vm_name" | grep -q "looking-glass"; then
        print_warning "IVSHMEM device already exists in VM configuration"
        echo "Current IVSHMEM configuration:"
        sudo virsh dumpxml "$vm_name" | grep -A 3 -B 1 "looking-glass" | sed 's/^/  /'
        echo
        read -p "Do you want to remove the existing device and add a new one? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Removing existing IVSHMEM device..."
            if sudo virt-xml "$vm_name" --remove-device --shmem name=looking-glass; then
                print_status "✓ Existing IVSHMEM device removed"
            else
                print_error "Failed to remove existing IVSHMEM device"
                return 1
            fi
        else
            print_status "Keeping existing IVSHMEM device. Skipping device configuration."
            # Still need to ensure shared memory file and service are set up
        fi
    fi
    
    # Add IVSHMEM device to VM (only if it doesn't exist or was removed)
    if ! sudo virsh dumpxml "$vm_name" | grep -q "looking-glass"; then
        print_status "Adding IVSHMEM device to VM..."
        if sudo virt-xml "$vm_name" --add-device --shmem name=looking-glass,model.type=ivshmem-plain,size=128,size.unit=M; then
            print_status "✓ IVSHMEM device added successfully"
        else
            print_error "Failed to add IVSHMEM device to VM"
            return 1
        fi
    else
        print_status "✓ IVSHMEM device already configured"
    fi
    
    # Create shared memory file
    print_status "Creating shared memory file..."
    sudo touch /dev/shm/looking-glass
    sudo chown "$USER:users" /dev/shm/looking-glass
    sudo chmod 660 /dev/shm/looking-glass
    
    # Create systemd service for shared memory
    print_status "Creating systemd service for shared memory..."
    sudo tee /etc/systemd/system/looking-glass-shm.service > /dev/null << EOF
[Unit]
Description=Create Looking Glass shared memory
After=dev-shm.mount

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'touch /dev/shm/looking-glass && chown $USER:users /dev/shm/looking-glass && chmod 660 /dev/shm/looking-glass'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable the service
    print_status "Enabling looking-glass-shm service..."
    sudo systemctl enable looking-glass-shm.service
    
    # Start the service
    print_status "Starting looking-glass-shm service..."
    sudo systemctl start looking-glass-shm.service
    
    # Verify service status
    if systemctl is-active --quiet looking-glass-shm.service; then
        print_status "✓ looking-glass-shm service is active"
    else
        print_warning "looking-glass-shm service may not be running properly"
    fi
    
    # Verify shared memory file
    if [[ -f "/dev/shm/looking-glass" ]]; then
        print_status "✓ Shared memory file created successfully"
        ls -la /dev/shm/looking-glass
    else
        print_error "Shared memory file was not created"
        return 1
    fi
    
    echo
    print_status "Looking Glass configuration completed!"
    echo
    print_status "Next steps:"
    echo "1. Start your VM using virt-manager"
    echo "2. Download and install Looking Glass Host on Windows from:"
    echo "   https://looking-glass.io/downloads"
    echo "3. Install the IVSHMEM driver in Windows Device Manager"
    echo "4. Launch Looking Glass client on Linux: looking-glass-client"
    echo
    print_warning "Note: The shared memory file will be recreated automatically on each boot"
    print_warning "Make sure your monitor is connected to your iGPU before starting the VM"
}

# Function to clean up duplicate IVSHMEM devices
cleanup_duplicate_ivshmem() {
    print_header "Clean Up Duplicate IVSHMEM Devices"
    
    # Check if libvirtd is running
    if ! systemctl is-active --quiet libvirtd; then
        print_error "libvirt service is not running. Please start it first."
        return 1
    fi
    
    # Show available VMs
    print_status "Available VMs:"
    sudo virsh list --all
    
    echo
    read -p "Enter your VM name to clean up (e.g., win11): " vm_name
    
    if [[ -z "$vm_name" ]]; then
        print_error "VM name cannot be empty"
        return 1
    fi
    
    # Check if VM exists
    if ! sudo virsh list --all | grep -q "$vm_name"; then
        print_error "VM '$vm_name' not found. Please check the name and try again."
        return 1
    fi
    
    # Count IVSHMEM devices
    local ivshmem_count=$(sudo virsh dumpxml "$vm_name" | grep -c "looking-glass")
    
    if [[ $ivshmem_count -eq 0 ]]; then
        print_status "No IVSHMEM devices found for VM '$vm_name'"
        return 0
    elif [[ $ivshmem_count -eq 1 ]]; then
        print_status "Only one IVSHMEM device found. No cleanup needed."
        return 0
    else
        print_warning "Found $ivshmem_count IVSHMEM devices (duplicates detected)"
        echo "Current IVSHMEM devices:"
        sudo virsh dumpxml "$vm_name" | grep -A 3 -B 1 "looking-glass" | sed 's/^/  /'
        echo
        
        print_warning "This will remove ALL IVSHMEM devices and add a single clean one."
        read -p "Do you want to proceed? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Removing all IVSHMEM devices..."
            
            # Remove all IVSHMEM devices
            while sudo virsh dumpxml "$vm_name" | grep -q "looking-glass"; do
                if sudo virt-xml "$vm_name" --remove-device --shmem name=looking-glass; then
                    print_status "✓ Removed IVSHMEM device"
                else
                    print_error "Failed to remove IVSHMEM device"
                    return 1
                fi
            done
            
            # Add a single clean IVSHMEM device
            print_status "Adding clean IVSHMEM device..."
            if sudo virt-xml "$vm_name" --add-device --shmem name=looking-glass,model.type=ivshmem-plain,size=128,size.unit=M; then
                print_status "✓ Clean IVSHMEM device added successfully"
            else
                print_error "Failed to add clean IVSHMEM device"
                return 1
            fi
            
            print_status "Cleanup completed! VM now has a single IVSHMEM device."
        else
            print_status "Cleanup cancelled."
        fi
    fi
}

# Function to validate Looking Glass configuration
validate_looking_glass() {
    print_header "Validate Looking Glass Configuration"
    
    local errors=0
    local warnings=0
    
    # Check if libvirtd is running
    if ! systemctl is-active --quiet libvirtd; then
        print_error "libvirt service is not running"
        ((errors++))
    else
        print_status "✓ libvirt service is running"
    fi
    
    # Show available VMs
    print_status "Available VMs:"
    sudo virsh list --all
    
    echo
    read -p "Enter your VM name to validate (e.g., win11): " vm_name
    
    if [[ -z "$vm_name" ]]; then
        print_error "VM name cannot be empty"
        return 1
    fi
    
    # Check if VM exists
    if ! sudo virsh list --all | grep -q "$vm_name"; then
        print_error "VM '$vm_name' not found. Please check the name and try again."
        return 1
    fi
    
    print_status "Validating Looking Glass configuration for VM: $vm_name"
    echo
    
    # Check VM XML for IVSHMEM device
    print_status "Checking VM XML for IVSHMEM device..."
    local ivshmem_count=$(sudo virsh dumpxml "$vm_name" | grep -c "looking-glass")
    
    if [[ $ivshmem_count -eq 0 ]]; then
        print_error "✗ IVSHMEM device not found in VM XML"
        print_warning "Run step 8 to configure Looking Glass for this VM"
        ((errors++))
    elif [[ $ivshmem_count -eq 1 ]]; then
        print_status "✓ IVSHMEM device found in VM XML"
        
        # Show the IVSHMEM configuration
        echo "IVSHMEM Configuration:"
        sudo virsh dumpxml "$vm_name" | grep -A 3 -B 1 "looking-glass" | sed 's/^/  /'
    else
        print_error "✗ Multiple IVSHMEM devices found ($ivshmem_count devices)"
        print_warning "This can cause conflicts. Run step 8C to clean up duplicates"
        echo "Current IVSHMEM devices:"
        sudo virsh dumpxml "$vm_name" | grep -A 3 -B 1 "looking-glass" | sed 's/^/  /'
        ((errors++))
    fi
    
    # Check looking-glass-shm service status
    print_status "Checking looking-glass-shm service..."
    if systemctl is-enabled looking-glass-shm.service &>/dev/null; then
        print_status "✓ looking-glass-shm service is enabled"
    else
        print_error "✗ looking-glass-shm service is not enabled"
        print_warning "Run step 8 to configure Looking Glass for this VM"
        ((errors++))
    fi
    
    if systemctl is-active looking-glass-shm.service &>/dev/null; then
        print_status "✓ looking-glass-shm service is running"
    else
        print_warning "⚠ looking-glass-shm service is not running"
        print_status "Attempting to start the service..."
        if sudo systemctl start looking-glass-shm.service; then
            print_status "✓ Service started successfully"
        else
            print_error "✗ Failed to start the service"
            ((errors++))
        fi
    fi
    
    # Check shared memory file
    print_status "Checking shared memory file..."
    if [[ -f "/dev/shm/looking-glass" ]]; then
        print_status "✓ Shared memory file exists"
        echo "File details:"
        ls -la /dev/shm/looking-glass | sed 's/^/  /'
        
        # Check file permissions
        local file_owner=$(stat -c '%U:%G' /dev/shm/looking-glass)
        local file_perms=$(stat -c '%a' /dev/shm/looking-glass)
        
        if [[ "$file_owner" == "$USER:users" ]]; then
            print_status "✓ File ownership is correct: $file_owner"
        else
            print_warning "⚠ File ownership is incorrect: $file_owner (expected: $USER:users)"
            ((warnings++))
        fi
        
        if [[ "$file_perms" == "660" ]]; then
            print_status "✓ File permissions are correct: $file_perms"
        else
            print_warning "⚠ File permissions are incorrect: $file_perms (expected: 660)"
            ((warnings++))
        fi
    else
        print_error "✗ Shared memory file does not exist"
        print_warning "Run step 8 to configure Looking Glass for this VM"
        ((errors++))
    fi
    
    # Check if Looking Glass client is installed
    print_status "Checking Looking Glass client installation..."
    if command -v looking-glass-client &> /dev/null; then
        print_status "✓ Looking Glass client is installed"
    else
        print_warning "⚠ Looking Glass client not found"
        print_warning "Run step 1 to install Looking Glass"
        ((warnings++))
    fi
    
    # Summary
    echo
    print_status "Validation Summary:"
    if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
        print_status "✓ All Looking Glass components are properly configured!"
        echo
        print_status "You can now:"
        echo "1. Start your VM using virt-manager"
        echo "2. Install Looking Glass Host on Windows from: https://looking-glass.io/downloads"
        echo "3. Launch Looking Glass client: looking-glass-client"
    elif [[ $errors -eq 0 ]]; then
        print_warning "Looking Glass is configured but has $warnings warning(s). Check the details above."
    else
        print_error "Looking Glass configuration has $errors error(s) and $warnings warning(s)."
        print_warning "Please address the errors before using Looking Glass."
    fi
}

# Function to show main menu
show_menu() {
    clear
    print_header "QEMU VFIO GPU Passthrough Setup"
    echo
    echo "This script will help you set up QEMU with Nvidia GPU passthrough for Windows VMs."
    echo
    echo "1) Install Virtualization Packages (includes Looking Glass)"
    echo "2) Update GRUB to enable/configure IOMMU"
    print_warning "[Must Reboot for GRUB changes to take effect]"
    echo "3) Check IOMMU Groups (Manually Identify IOMMU Group"
    echo "   with your GPU and GPU Audio Device IDs)"
    echo "4) Configure VFIO for GPU Passthrough (Auto Finds"
    echo "   GPU and GPU Audio Device IDs if IOMMU is enabled)"
    echo "5) Configure initramfs (Lets VIFO claim devices before other OS drivers)"
    print_warning "[Must Reboot- Make sure your Monitor is plugged into your iGPU]"
    echo "6) Prepare Other SSD (Setting up Another Physical"
    echo "   Drive for VM Storage) [Unmount, Wipe & Partition]"
    echo "   Options: Single, Multiple, EFI+Windows, or Raw"
    echo "6C) Show Current Partition Layout (parted -l & lsblk -l)"
    echo "7) Show VM Creation Guide (virt-manager)"
    echo "8) Configure Looking Glass for VM (View VM dGPU output on Linux host)"
    echo "8C) Clean Up Duplicate IVSHMEM Devices"
    echo "9) Validate Looking Glass Configuration (Check VM XML, service, shared memory)"
    echo "10) Validate System"
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
        read -p "Select an option (0-10, 6C, 8C): " choice
        
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
            6C|6c)
                show_partition_layout
                ;;
            7)
                show_vm_creation_guide
                ;;
            8)
                configure_looking_glass
                ;;
            8C|8c)
                cleanup_duplicate_ivshmem
                ;;
            9)
                validate_looking_glass
                ;;
            10)
                validate_system
                ;;
            0)
                print_status "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 0-10, 6C, or 8C."
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Run main function
main "$@"
