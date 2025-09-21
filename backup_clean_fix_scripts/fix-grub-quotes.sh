#!/bin/bash

# Quick fix script to restore missing quotation marks in GRUB
# Run with: sudo ./fix-grub-quotes.sh

echo "Fixing missing quotation marks in GRUB configuration..."

# Backup current GRUB config
cp /etc/default/grub /etc/default/grub.backup.$(date +%Y%m%d-%H%M%S)

# Show current GRUB_CMDLINE_LINUX_DEFAULT
echo "Current GRUB_CMDLINE_LINUX_DEFAULT:"
grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub

# Fix missing quotation marks
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)$/GRUB_CMDLINE_LINUX_DEFAULT="\1"/' /etc/default/grub

# Show fixed GRUB_CMDLINE_LINUX_DEFAULT
echo "Fixed GRUB_CMDLINE_LINUX_DEFAULT:"
grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub

echo "GRUB quotation marks fixed!"
