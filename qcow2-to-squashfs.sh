#!/bin/bash

set -euo pipefail

# Logging function to display messages with timestamps
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check and load nbd module
load_nbd_module() {
    if ! lsmod | grep -q "^nbd "; then
        log "Loading nbd module..."
        sudo modprobe nbd max_part=16
    else
        if [[ "$(cat /sys/module/nbd/parameters/max_part)" != "16" ]]; then
            log "nbd is loaded, but not with the desired max_part parameter!"
        fi
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

# Mount the necessary filesystems
mount_filesystems() {
    sudo mkdir -p $ROOT_DIR
    sudo mkdir -p $USB_EFI_DIR
    sudo mkdir -p $USB_OS_DIR
    sudo qemu-nbd --connect=$ROOTFS_NBD custom.qcow2
    sudo qemu-nbd --connect=$USB_NBD virtual_usb.qcow2
    sudo mount ${ROOTFS_NBD}p3 $ROOT_DIR
    sudo mount ${USB_NBD}p1 $USB_EFI_DIR
    sudo mount ${USB_NBD}p3 $USB_OS_DIR
}

# Create the squashfs root image and extract kernel/initramfs
process_image() {
    cd $USB_OS_DIR
    log "Creating squashfs root image..."
    sudo mksquashfs $ROOT_DIR custom_root.squashfs

    log "Extracting vmlinuz and initramfs..."
    sudo cp $ROOT_DIR/boot/vmlinuz-* $USB_OS_DIR/vmlinuz
    sudo cp $ROOT_DIR/boot/initramfs-*.img $USB_OS_DIR/initramfs.img
}

# Final cleanup
final_cleanup() {
    cd $CURRENT_DIR
    sudo umount -l $USB_EFI_DIR
    sudo umount -l $USB_OS_DIR
    sudo umount -l $ROOT_DIR
    sudo qemu-nbd --disconnect $USB_NBD
    sudo qemu-nbd --disconnect $ROOTFS_NBD
    sudo modprobe -r nbd
}

# Main script execution
main() {
    CURRENT_DIR=$(pwd)
    ROOT_DIR=/mnt/myroot
    ROOTFS_NBD=/dev/nbd1
    USB_NBD=/dev/nbd0
    USB_EFI_DIR=/mnt/virtual_usb_efi
    USB_OS_DIR=/mnt/virtual_usb_os

    load_nbd_module
    cleanup
    mount_filesystems
    process_image
    final_cleanup

    log "Script completed successfully!"
}

# Run the main function
main
