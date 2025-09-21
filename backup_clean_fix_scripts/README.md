# Backup, Clean, and Fix Scripts

This folder contains utility scripts for troubleshooting and fixing QEMU VFIO setup issues.

## Scripts Overview

### Fix Scripts
- **`fix-grub-vfio.sh`** - Complete GRUB VFIO fix with cleanup and proper quotation marks
- **`fix-grub-quotes.sh`** - Quick fix for missing quotation marks in GRUB configuration
- **`fix-vfio-simple.sh`** - Simple VFIO configuration fix with hardcoded device IDs
- **`fix-ntfs-tools.sh`** - Install formatting tools (NTFS and FAT32) for partitioning

### Clean Scripts
- **`clean-grub-vfio.sh`** - Remove all VFIO parameters from GRUB configuration

### Test Scripts
- **`test-grub-regex.sh`** - Test GRUB regex patterns for VFIO parameter handling

## Usage

### Quick Fixes
```bash
# Fix missing quotation marks in GRUB
sudo ./fix-grub-quotes.sh

# Complete GRUB VFIO fix
sudo ./fix-grub-vfio.sh

# Simple VFIO configuration fix
sudo ./fix-vfio-simple.sh

# Install formatting tools (NTFS and FAT32)
sudo ./fix-ntfs-tools.sh
```

### Cleanup
```bash
# Remove all VFIO parameters from GRUB
sudo ./clean-grub-vfio.sh
```

### Testing
```bash
# Test GRUB regex patterns
./test-grub-regex.sh
```

## When to Use

- **fix-grub-quotes.sh**: When GRUB_CMDLINE_LINUX_DEFAULT is missing closing quotation mark
- **fix-grub-vfio.sh**: When you need to completely reset and fix GRUB VFIO configuration
- **fix-vfio-simple.sh**: When you need a quick VFIO fix with known device IDs
- **fix-ntfs-tools.sh**: When mkfs.ntfs or mkfs.fat commands are not found during partitioning
- **clean-grub-vfio.sh**: When you want to remove all VFIO parameters and start fresh
- **test-grub-regex.sh**: When you want to verify regex patterns work correctly

## Notes

- All scripts create backups before making changes
- Scripts are designed for RTX 5080 (10de:2c02, 10de:22e9) - modify device IDs as needed
- Use the main `qemu-vfio-setup.sh` script for normal setup process
- These scripts are for troubleshooting and manual fixes only

