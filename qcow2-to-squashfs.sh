#!/bin/bash

set -euo pipefail

# VARIABLES
CURRENT_DIR=$(pwd)
ROOT_DIR=/mnt/myroot
ROOTFS_NBD=/dev/nbd1
USB_NBD=/dev/nbd0
USB_EFI_DIR=/mnt/virtual_usb_efi
USB_OS_DIR=/mnt/virtual_usb_os

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
        if lsblk | grep -qw "^$device"; then
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
    
    # DEBUGGING TESTING - Need clean file every run
    cp virtual_usb.qcow2.clean virtual_usb.qcow2
    
    sudo qemu-nbd --connect=$USB_NBD virtual_usb.qcow2
    sudo mount ${ROOTFS_NBD}p3 $ROOT_DIR
    sudo mount ${USB_NBD}p1 $USB_EFI_DIR
    sudo mount ${USB_NBD}p3 $USB_OS_DIR
}

# Create the squashfs root image and extract kernel/initramfs
process_image() {
    cd $USB_OS_DIR
    log "Creating squashfs root image..."
    sudo mksquashfs $ROOT_DIR myroot.squashfs

    log "Extracting vmlinuz and initramfs..."
    sudo cp $ROOT_DIR/boot/vmlinuz-* $USB_OS_DIR/vmlinuz
    sudo cp $ROOT_DIR/boot/initramfs-*.img $USB_OS_DIR/initramfs.img
}

update_initramfs() {
    sudo mount --bind /proc $ROOT_DIR/proc
    sudo mount --bind /sys $ROOT_DIR/sys
    sudo mount --bind /dev $ROOT_DIR/dev
    sudo mount --bind /run $ROOT_DIR/run
    sudo mount --bind /etc/pki $ROOT_DIR/etc/pki
    sudo mount --bind /etc/yum.repos.d $ROOT_DIR/etc/yum.repos.d
    sudo touch "$ROOT_DIR/etc/resolv.conf"
    sudo mount --bind /etc/resolv.conf $ROOT_DIR/etc/resolv.conf


    sudo chroot $ROOT_DIR /bin/bash <<-EOL
    yum install dracut-live --nogpgcheck -y 
    dracut --add 'dmsquash-live' \
           --force \
           --verbose \
           --no-hostonly \
           --nomdadmconf \
           --omit-drivers "md_mod raid1 raid456 raid10" \
           /boot/initramfs-$(uname -r).img $(uname -r)
EOL
}


# Final cleanup
final_cleanup() {
    local last_exit_code=$?
    cd $CURRENT_DIR
    # First, unmount the virtual file systems and bind mounts if they're mounted.
    for fs in proc sys dev run; do
        if mount | grep -q "$ROOT_DIR/$fs"; then
            sudo umount -l "$ROOT_DIR/$fs"
        fi
    done

    if mount | grep -q "$ROOT_DIR/etc/yum.repos.d"; then
        sudo umount -l "$ROOT_DIR/etc/yum.repos.d"
    fi

    if mount | grep -q "$ROOT_DIR/etc/pki"; then
        sudo umount -l "$ROOT_DIR/etc/pki"
    fi

    if mount | grep -q "$ROOT_DIR/etc/resolv.conf"; then
        sudo umount -l "$ROOT_DIR/etc/resolv.conf"
    fi


    # Now, check and unmount the main ROOT_DIR
    if mount | grep -q "$ROOT_DIR"; then
        sudo umount -l "$ROOT_DIR"
    fi

    # For the other directories, you can just use umount -l to attempt the unmount
    # If you want to suppress any potential errors, redirect stderr to /dev/null
    sudo umount -l "$USB_EFI_DIR" 2>/dev/null || true
    sudo umount -l "$USB_OS_DIR" 2>/dev/null || true

    sudo qemu-nbd --disconnect $USB_NBD
    sudo qemu-nbd --disconnect $ROOTFS_NBD
    sudo modprobe -r nbd

    if [ $last_exit_code -eq 0 ]; then
        log "Script completed successfully!"
    else
        log "Script failed to complete successfully!"
    fi

    exit $last_exit_code
}

trap final_cleanup EXIT

# Main script execution
main() {
    load_nbd_module
    cleanup
    mount_filesystems
    process_image
    update_initramfs
    final_cleanup
}

# Run the main function
main
