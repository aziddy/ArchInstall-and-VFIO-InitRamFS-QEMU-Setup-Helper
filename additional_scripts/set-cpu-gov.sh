#!/bin/bash

# Interactive CPU governor setting script
# This script shows current CPU governor settings and allows the user to choose between performance and powersave modes

echo "=== CPU Governor Management Script ==="
echo

# Show current CPU governor settings
echo "Current CPU governor settings:"
echo "================================"
cpupower frequency-info
echo

# Get current governor for all cores
current_governor=$(cpupower frequency-info | grep "The governor" | head -1 | awk '{print $3}' | tr -d '"')

if [ -n "$current_governor" ]; then
    echo "Current governor: $current_governor"
else
    echo "Could not determine current governor"
fi

echo
echo "Available governors:"
echo "- performance: Maximum performance, higher power consumption"
echo "- powersave: Lower power consumption, reduced performance"
echo

# Ask user for choice
while true; do
    echo "Which governor would you like to set?"
    echo "1) performance"
    echo "2) powersave"
    echo "3) exit (no changes)"
    echo
    read -p "Enter your choice (1-3): " choice
    
    case $choice in
        1)
            selected_governor="performance"
            break
            ;;
        2)
            selected_governor="powersave"
            break
            ;;
        3)
            echo "Exiting without making changes."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter 1, 2, or 3."
            echo
            ;;
    esac
done

echo
echo "Setting CPU governor to $selected_governor mode..."

# Set CPU governor
sudo cpupower frequency-set -g $selected_governor

if [ $? -eq 0 ]; then
    echo "Successfully set CPU governor to $selected_governor mode"
    echo
    echo "Updated CPU frequency settings:"
    echo "================================"
    cpupower frequency-info
else
    echo "Failed to set CPU governor to $selected_governor mode"
    exit 1
fi
