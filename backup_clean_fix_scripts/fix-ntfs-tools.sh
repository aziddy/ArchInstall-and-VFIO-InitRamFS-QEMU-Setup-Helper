#!/bin/bash

# Quick fix script to install NTFS formatting tools
# Run with: sudo ./fix-ntfs-tools.sh

echo "Installing NTFS formatting tools..."

# Install ntfs-3g package
sudo pacman -S --noconfirm ntfs-3g

echo "NTFS formatting tools installed!"
echo "You can now continue with the partitioning process."
