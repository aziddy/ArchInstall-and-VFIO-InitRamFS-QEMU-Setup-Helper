#!/bin/bash

# VFIO Reset Issues Fix Script
# Based on "Prevent Crashing on Hard Workloads QEMU Windows VM.md" section 2
# This script adds VFIO reset parameters to GRUB configuration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to check if required parameters exist in GRUB_CMDLINE_LINUX_DEFAULT
check_required_params() {
    local grub_file="/etc/default/grub"
    
    if [[ ! -f "$grub_file" ]]; then
        print_error "GRUB configuration file not found: $grub_file"
        exit 1
    fi
    
    # Source the grub file to get GRUB_CMDLINE_LINUX_DEFAULT
    source "$grub_file"
    
    # Check for required parameters
    local required_params=("quiet" "iommu=pt" "vfio-pci.ids=")
    local missing_params=()
    
    # Check for IOMMU parameter (either Intel or AMD)
    local has_iommu=false
    if [[ "$GRUB_CMDLINE_LINUX_DEFAULT" == *"intel_iommu=on"* ]] || [[ "$GRUB_CMDLINE_LINUX_DEFAULT" == *"amd_iommu=on"* ]]; then
        has_iommu=true
    fi
    
    # Check basic required parameters
    for param in "${required_params[@]}"; do
        if [[ "$GRUB_CMDLINE_LINUX_DEFAULT" != *"$param"* ]]; then
            missing_params+=("$param")
        fi
    done
    
    # Add IOMMU check if missing
    if [[ "$has_iommu" == "false" ]]; then
        missing_params+=("intel_iommu=on or amd_iommu=on")
    fi
    
    if [[ ${#missing_params[@]} -gt 0 ]]; then
        print_error "Required parameters are missing from GRUB_CMDLINE_LINUX_DEFAULT:"
        for param in "${missing_params[@]}"; do
            echo "  - $param"
        done
        print_error "Please ensure these parameters are present before running this script."
        print_error "Current GRUB_CMDLINE_LINUX_DEFAULT: $GRUB_CMDLINE_LINUX_DEFAULT"
        exit 1
    fi
    
    print_success "All required parameters found in GRUB configuration (IOMMU support detected)"
}

# Function to check if VFIO reset parameters already exist
check_existing_vfio_params() {
    local grub_file="/etc/default/grub"
    source "$grub_file"
    
    local vfio_params=("vfio_iommu_type1.allow_unsafe_interrupts=1" "kvm.ignore_msrs=1")
    local existing_params=()
    
    for param in "${vfio_params[@]}"; do
        if [[ "$GRUB_CMDLINE_LINUX_DEFAULT" == *"$param"* ]]; then
            existing_params+=("$param")
        fi
    done
    
    if [[ ${#existing_params[@]} -gt 0 ]]; then
        print_warning "Some VFIO reset parameters already exist:"
        for param in "${existing_params[@]}"; do
            echo "  - $param"
        done
        print_warning "These parameters will not be added again to prevent duplicates."
    fi
    
    return ${#existing_params[@]}
}

# Function to add VFIO reset parameters
add_vfio_reset_params() {
    local grub_file="/etc/default/grub"
    local backup_file="${grub_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup
    cp "$grub_file" "$backup_file"
    print_status "Created backup: $backup_file"
    
    # Source the grub file to get current GRUB_CMDLINE_LINUX_DEFAULT
    source "$grub_file"
    
    local new_cmdline="$GRUB_CMDLINE_LINUX_DEFAULT"
    local params_added=false
    
    # Add vfio_iommu_type1.allow_unsafe_interrupts=1 if not present
    if [[ "$new_cmdline" != *"vfio_iommu_type1.allow_unsafe_interrupts=1"* ]]; then
        new_cmdline="$new_cmdline vfio_iommu_type1.allow_unsafe_interrupts=1"
        params_added=true
        print_status "Added: vfio_iommu_type1.allow_unsafe_interrupts=1"
    fi
    
    # Add kvm.ignore_msrs=1 if not present
    if [[ "$new_cmdline" != *"kvm.ignore_msrs=1"* ]]; then
        new_cmdline="$new_cmdline kvm.ignore_msrs=1"
        params_added=true
        print_status "Added: kvm.ignore_msrs=1"
    fi
    
    if [[ "$params_added" == "true" ]]; then
        # Update the GRUB_CMDLINE_LINUX_DEFAULT line
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\"|" "$grub_file"
        
        print_success "Updated GRUB_CMDLINE_LINUX_DEFAULT with VFIO reset parameters"
        print_status "New GRUB_CMDLINE_LINUX_DEFAULT: $new_cmdline"
        
        # Generate new GRUB configuration
        print_status "Generating new GRUB configuration..."
        if grub-mkconfig -o /boot/grub/grub.cfg; then
            print_success "GRUB configuration updated successfully"
            print_warning "Please reboot your system for changes to take effect"
        else
            print_error "Failed to generate GRUB configuration"
            print_error "Restoring backup..."
            cp "$backup_file" "$grub_file"
            exit 1
        fi
    else
        print_warning "No new parameters were added (all VFIO reset parameters already present)"
        rm "$backup_file"  # Remove backup since no changes were made
    fi
}

# Function to display information about the parameters
show_parameter_info() {
    echo
    print_status "VFIO Reset Parameters Information:"
    echo
    echo "vfio_iommu_type1.allow_unsafe_interrupts=1:"
    echo "  - Tells VFIO driver to handle interrupts in an 'unsafe' way"
    echo "  - Many GPUs don't fully support interrupt remapping"
    echo "  - Allows direct access without proxy for intense video games"
    echo "  - Prevents GPU driver crashes from blocked interrupts"
    echo
    echo "kvm.ignore_msrs=1:"
    echo "  - Tells KVM Hypervisor to ignore Model-Specific Registers (MSRs)"
    echo "  - Prevents games from thinking CPU is broken when accessing MSRs"
    echo "  - Allows games to continue normally when accessing CPU performance MSRs"
    echo
}

# Main function
main() {
    echo "=========================================="
    echo "VFIO Reset Issues Fix Script (Step 2 from .md doc)"
    echo "=========================================="
    echo
    
    check_root
    check_required_params
    
    local existing_count
    check_existing_vfio_params
    existing_count=$?
    
    show_parameter_info
    
    if [[ $existing_count -eq 2 ]]; then
        print_warning "All VFIO reset parameters are already present in GRUB configuration"
        print_warning "No changes needed. Exiting."
        exit 0
    fi
    
    print_status "Proceeding to add missing VFIO reset parameters..."
    add_vfio_reset_params
    
    echo
    print_success "VFIO reset issues fix completed successfully!"
    echo
    print_warning "IMPORTANT: Reboot your system for the changes to take effect"
    print_status "After reboot, your VM should be more stable during intensive workloads"
}

# Run main function
main "$@"
