#!/bin/bash

# Test script to verify partition logic
# This simulates the partition counting logic

echo "Testing EFI + Windows partition logic..."

# Simulate device path
device_path="/dev/nvme1n1"

echo "Device: $device_path"
echo "EFI partition: ${device_path}p1"
echo

# Simulate creating 3 Windows partitions
windows_partition_count=0

for ((i=1; i<=3; i++)); do
    windows_partition_count=$((windows_partition_count + 1))
    partition_number=$((windows_partition_count + 1))  # +1 because EFI is partition 1
    
    if [[ "$device_path" =~ nvme ]]; then
        partition_path="${device_path}p$partition_number"
    else
        partition_path="${device_path}$partition_number"
    fi
    
    echo "Windows partition $windows_partition_count: $partition_path"
done

echo
echo "Expected result:"
echo "EFI: ${device_path}p1"
echo "Windows1: ${device_path}p2"
echo "Windows2: ${device_path}p3" 
echo "Windows3: ${device_path}p4"
