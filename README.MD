# ArchInstall-and-VFIO-InitRamFS-QEMU-Setup-Helper

An interactive bash script that automates the complete setup of QEMU on Arch Linux with Nvidia GPU passthrough for running Windows VMs. This script handles everything from package installation to VM configuration.

## Features

- 🚀 **Automated Setup**: Complete QEMU + VFIO configuration in one script
- 🎯 **Interactive Menu**: Step-by-step guided setup with explanations
- 🔧 **System Validation**: Built-in checks to ensure proper configuration
- 📋 **Comprehensive Logging**: Detailed logs for troubleshooting
- 🛡️ **Safety First**: Automatic backups before making changes
- 🖥️ **GPU Passthrough**: Full Nvidia GPU passthrough support
- 💾 **Storage Management**: Second SSD preparation for Windows VM

## Prerequisites

- Arch Linux (or Arch-based distribution)
- Root/sudo access
- NVIDIA GPU for passthrough
- Second SSD/HDD for Windows VM storage
- UEFI firmware (recommended)

## Quick Start

1. **Clone or download this repository**
   ```bash
   git clone https://github.com/yourusername/ArchInstall-and-VFIO-InitRamFS-QEMU-Setup-Helper.git
   cd ArchInstall-and-VFIO-InitRamFS-QEMU-Setup-Helper
   ```

2. **Make the script executable**
   ```bash
   chmod +x qemu-vfio-setup.sh
   ```

3. **Run the setup script**
   ```bash
   ./qemu-vfio-setup.sh
   ```

4. **Follow the interactive menu** - The script will guide you through each step

## What the Script Does

### 1. Package Installation
- Installs QEMU, virt-manager, libvirt, and all required packages
- Enables and starts libvirt service
- Adds user to libvirt group
- Validates virtualization support

### 2. IOMMU Configuration
- Automatically detects Intel or AMD CPU
- Configures GRUB with appropriate IOMMU parameters
- Creates backup of original GRUB configuration
- Updates GRUB bootloader

### 3. IOMMU Groups Analysis
- Creates and runs IOMMU groups checker script
- Displays all PCI devices and their IOMMU groups
- Helps identify GPU and audio device IDs

### 4. VFIO Configuration
- Automatically detects NVIDIA GPU device IDs
- Creates VFIO configuration files
- Updates GRUB with VFIO parameters
- Prevents host OS from claiming GPU

### 5. initramfs Configuration
- Modifies mkinitcpio.conf for VFIO modules
- Rebuilds initramfs with VFIO support
- Ensures VFIO loads before other drivers

### 6. Storage Preparation
- Lists available storage devices
- Safely prepares second SSD for Windows VM
- Provides guidance on device selection

### 7. VM Creation Guide
- Step-by-step virt-manager configuration
- GPU passthrough setup instructions
- VirtIO driver installation guidance
- UEFI and CPU configuration tips

## Menu Options

The script provides an interactive menu with the following options:

1. **Install Virtualization Packages** - Install all required software
2. **Configure IOMMU** - Set up IOMMU for GPU passthrough
3. **Check IOMMU Groups** - Analyze PCI device grouping
4. **Configure VFIO** - Set up VFIO for GPU binding
5. **Configure initramfs** - Modify initramfs for VFIO
6. **Prepare Second SSD** - Prepare storage for Windows VM
7. **Show VM Creation Guide** - Display virt-manager instructions
8. **Validate System** - Check configuration status
9. **Run Complete Setup** - Execute steps 1-6 automatically
0. **Exit** - Quit the script

## Important Notes

### Reboots Required
- After IOMMU configuration (step 2)
- After initramfs configuration (step 5)
- After complete setup (option 9)

### Safety Features
- Automatic backups before modifying system files
- Validation checks before proceeding
- Detailed logging for troubleshooting
- Confirmation prompts for destructive operations

### Troubleshooting
- Check the log file: `/tmp/qemu-vfio-setup.log`
- Run system validation (option 8) to check status
- Verify IOMMU groups after reboot
- Ensure all VFIO modules are loaded

## Manual Steps After Script

1. **Reboot your system** after running the complete setup
2. **Verify IOMMU groups** are working correctly
3. **Create Windows VM** using virt-manager with the provided guide
4. **Install VirtIO drivers** during Windows installation
5. **Test GPU passthrough** in your Windows VM

## File Structure

```
├── qemu-vfio-setup.sh          # Main interactive setup script
├── QEMU Setup Linux.md         # Detailed manual setup guide
└── README.MD                   # This file
```

## Logs and Backups

- **Log file**: `/tmp/qemu-vfio-setup.log`
- **Backups**: `/etc/backup-YYYYMMDD-HHMMSS/`
- **IOMMU checker**: `~/check_iommu.sh`

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve this script.

## License

This project is open source. Feel free to use and modify as needed.

## Support

If you encounter issues:
1. Check the log file for detailed error messages
2. Run the system validation option
3. Review the manual setup guide in `QEMU Setup Linux.md`
4. Ensure you've rebooted after configuration changes 



IOMMU GROUP 14
10de:2c02
10de:22e9