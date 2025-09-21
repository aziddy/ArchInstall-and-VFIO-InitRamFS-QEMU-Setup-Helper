#!/bin/bash

# Script to clean up duplicated VFIO parameters in GRUB
# Run with: sudo ./clean-grub-vfio.sh

echo "Cleaning up GRUB VFIO parameters..."

# Backup current GRUB config
cp /etc/default/grub /etc/default/grub.backup.$(date +%Y%m%d-%H%M%S)

# Show current GRUB_CMDLINE_LINUX_DEFAULT
echo "Current GRUB_CMDLINE_LINUX_DEFAULT:"
grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub

# Remove all vfio-pci.ids parameters (but preserve quotation marks)
sed -i 's/vfio-pci\.ids=[^[:space:]\"]*//g' /etc/default/grub

# Clean up any double spaces
sed -i 's/  */ /g' /etc/default/grub

# Ensure the GRUB_CMDLINE_LINUX_DEFAULT line ends with a quotation mark
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)$/GRUB_CMDLINE_LINUX_DEFAULT="\1"/' /etc/default/grub

# Show cleaned GRUB_CMDLINE_LINUX_DEFAULT
echo "Cleaned GRUB_CMDLINE_LINUX_DEFAULT:"
grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub

echo "GRUB VFIO parameters cleaned up!"
echo "You can now run the main script step 4 to add VFIO parameters properly."
