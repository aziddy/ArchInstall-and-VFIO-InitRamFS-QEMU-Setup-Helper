#!/bin/bash

# Quick fix script to add VFIO parameters to GRUB
# Run with: sudo ./fix-grub-vfio.sh

echo "Fixing GRUB configuration with VFIO parameters..."

# Backup current GRUB config
cp /etc/default/grub /etc/default/grub.backup.$(date +%Y%m%d-%H%M%S)

# Remove any existing VFIO parameters first (but preserve quotation marks)
sed -i 's/vfio-pci\.ids=[^[:space:]\"]*//g' /etc/default/grub
sed -i 's/  */ /g' /etc/default/grub

# Ensure the GRUB_CMDLINE_LINUX_DEFAULT line ends with a quotation mark
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)$/GRUB_CMDLINE_LINUX_DEFAULT="\1"/' /etc/default/grub

# Add VFIO parameters to GRUB_CMDLINE_LINUX_DEFAULT
sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 vfio-pci.ids=10de:2c02,10de:22e9\"|" /etc/default/grub

echo "GRUB configuration updated:"
grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub

echo "Updating GRUB configuration..."
grub-mkconfig -o /boot/grub/grub.cfg

echo "GRUB VFIO configuration fixed!"
