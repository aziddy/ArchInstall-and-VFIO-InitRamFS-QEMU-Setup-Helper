#!/bin/bash

# Simple script to fix VFIO configuration
# Run with: sudo ./fix-vfio-simple.sh

echo "Fixing VFIO configuration..."

# Remove corrupted file
rm -f /etc/modprobe.d/vfio.conf

# Create proper VFIO configuration
cat > /etc/modprobe.d/vfio.conf << 'EOF'
options vfio-pci ids=10de:2c02,10de:22e9
softdep nvidia pre: vfio-pci
softdep nouveau pre: vfio-pci
EOF

echo "VFIO configuration fixed!"
echo "Contents of /etc/modprobe.d/vfio.conf:"
cat /etc/modprobe.d/vfio.conf
