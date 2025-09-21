#!/bin/bash

# Test script to verify GRUB regex patterns work correctly

echo "Testing GRUB regex patterns..."

# Test case 1: Normal GRUB line with VFIO parameters
echo "Test 1: Normal GRUB line with VFIO parameters"
echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt vfio-pci.ids=10de:2c02,10de:22e9"' > /tmp/test1
echo "Before:"
cat /tmp/test1
sed 's/vfio-pci\.ids=[^[:space:]\"]*/vfio-pci.ids=10de:2c02,10de:22e9/g' /tmp/test1
echo "After:"
cat /tmp/test1
echo

# Test case 2: GRUB line with multiple VFIO parameters (duplicated)
echo "Test 2: GRUB line with duplicated VFIO parameters"
echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt vfio-pci.ids=10de:2c02,10de:22e9 vfio-pci.ids=10de:2c02,10de:22e9"' > /tmp/test2
echo "Before:"
cat /tmp/test2
sed 's/vfio-pci\.ids=[^[:space:]\"]*//g' /tmp/test2
echo "After removal:"
cat /tmp/test2
echo

# Test case 3: GRUB line without VFIO parameters
echo "Test 3: GRUB line without VFIO parameters"
echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"' > /tmp/test3
echo "Before:"
cat /tmp/test3
sed 's/vfio-pci\.ids=[^[:space:]\"]*//g' /tmp/test3
echo "After removal:"
cat /tmp/test3
echo

# Cleanup
rm /tmp/test1 /tmp/test2 /tmp/test3

echo "All tests completed!"
