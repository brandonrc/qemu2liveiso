#!/bin/bash

set -euo pipefail

# Variables
LOOP_DEVICE="/dev/nbd0"
USB_EFI_DIR="/mnt/virtual_usb_efi"
USB_OS_DIR="/mnt/virtual_usb_os"
GRUB_CMD=""

# Logging function to display messages with timestamps
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check and load nbd module
load_nbd_module() {
    if ! lsmod | grep -q "^nbd "; then
        log "Loading nbd module..."
        sudo modprobe nbd max_part=16
    elif [[ "$(cat /sys/module/nbd/parameters/max_part)" != "16" ]]; then
        log "nbd is loaded, but not with the desired max_part parameter!"
    fi
}

# Cleanup function to ensure no stale mounts or nbd connections
cleanup() {
    for device in nbd0 nbd1; do
        if lsblk | grep -q $device; then
            log "Cleaning up existing /dev/$device connection..."
            for partition in $(lsblk -o NAME | grep "^${device}p"); do
                sudo umount -l /dev/$partition || true
            done
            sudo qemu-nbd --disconnect /dev/$device
        fi
    done
}

# Create and set up the loop device
setup_loop_device() {
    sudo qemu-img create -f qcow2 virtual_usb.qcow2 5G
    sudo qemu-nbd --connect=$LOOP_DEVICE virtual_usb.qcow2

    # Partition the loop device
    log "Partitioning the loop device..."
    sudo parted -s $LOOP_DEVICE mklabel gpt
    sudo parted -s $LOOP_DEVICE mkpart primary fat32 1MiB 513MiB
    sudo parted $LOOP_DEVICE set 1 esp on
    sudo parted -s $LOOP_DEVICE mkpart primary 513MiB 515MiB
    sudo parted $LOOP_DEVICE set 2 bios_grub on
    sudo parted -s $LOOP_DEVICE mkpart primary ext4 515MiB 100%

    # Format the partitions
    log "Formatting the partitions..."
    sudo mkfs.vfat ${LOOP_DEVICE}p1
    sudo mkfs.ext4 ${LOOP_DEVICE}p3

    sudo mkdir -p $USB_EFI_DIR
    sudo mkdir -p $USB_OS_DIR
    sudo mount ${LOOP_DEVICE}p1 $USB_EFI_DIR
    sudo mount ${LOOP_DEVICE}p3 $USB_OS_DIR
}

# Determine the grub command to use and install GRUB
install_grub() {
    if command -v grub2-install &> /dev/null; then
        GRUB_CMD="grub2-install"
        log "Currently, we do not support grub2-install due to Red Hat developers."
        exit 1
    elif command -v grub-install &> /dev/null; then
        GRUB_CMD="grub-install"
    else
        log "Neither grub2-install nor grub-install found. Please install GRUB for your system."
        exit 1
    fi

    log "Installing GRUB..."
    sudo $GRUB_CMD --target=x86_64-efi --no-uefi-secure-boot --efi-directory=$USB_EFI_DIR --boot-directory=$USB_OS_DIR/boot --removable --modules="part_gpt part_msdos"
    sudo $GRUB_CMD --target=i386-pc --boot-directory=$USB_OS_DIR/boot $LOOP_DEVICE
}

# Final cleanup steps
final_cleanup() {
    log "Cleaning up..."
    sudo umount $USB_EFI_DIR
    sudo umount $USB_OS_DIR
    sudo qemu-nbd --disconnect $LOOP_DEVICE
    sudo modprobe -r nbd
}

# Main function to coordinate script execution
main() {
    load_nbd_module
    cleanup
    setup_loop_device
    install_grub
    final_cleanup

    log "Script completed successfully!"
}

# Run the main function
main