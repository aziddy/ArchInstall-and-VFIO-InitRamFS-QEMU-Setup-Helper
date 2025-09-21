#!/bin/bash

# Test script to verify partition loop logic

echo "Testing partition loop logic..."

# Simulate different partition size inputs
test_cases=("50%" "100GB" "remaining" "100%")

for partition_size in "${test_cases[@]}"; do
    echo "Testing: '$partition_size'"
    
    if [[ "$partition_size" == "remaining" ]]; then
        end_size="100%"
    else
        end_size="${partition_size}"
    fi
    
    echo "  end_size: $end_size"
    
    if [[ "$partition_size" == "remaining" ]] || [[ "$partition_size" == "100%" ]]; then
        echo "  Result: BREAK (no more partitions)"
    else
        echo "  Result: CONTINUE (ask for next partition)"
    fi
    echo
done
