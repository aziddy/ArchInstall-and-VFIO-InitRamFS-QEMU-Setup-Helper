#!/bin/bash

# Quick fix script to show correct partition paths
# Run: ./fix-partition-paths.sh

echo "Partition Path Reference:"
echo "========================="
echo
echo "For SATA/SCSI drives (e.g., /dev/sdb):"
echo "  Partitions: /dev/sdb1, /dev/sdb2, /dev/sdb3, etc."
echo
echo "For NVMe drives (e.g., /dev/nvme1n1):"
echo "  Partitions: /dev/nvme1n1p1, /dev/nvme1n1p2, /dev/nvme1n1p3, etc."
echo
echo "Current available partitions:"
lsblk | grep -E "(sd|nvme)" | grep -v "loop"
echo
echo "If you see partitions without the 'p' prefix on NVMe drives,"
echo "the partitioning may have failed. You may need to restart step 6."
