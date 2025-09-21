#!/bin/bash

# Quick fix script to install formatting tools
# Run with: sudo ./fix-ntfs-tools.sh

echo "Installing formatting tools..."

# Install ntfs-3g and dosfstools packages
sudo pacman -S --noconfirm ntfs-3g dosfstools

echo "Formatting tools installed!"
echo "You can now continue with the partitioning process."
