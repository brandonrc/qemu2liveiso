#!/bin/bash

set -euo pipefail

# Variables
USB_NBD="/dev/nbd0"
USB_EFI_DIR="/mnt/virtual_usb_efi"
USB_OS_DIR="/mnt/virtual_usb_os"

# Determine if running on Ubuntu or RHEL
if [[ $(grep -Ei 'debian|ubuntu' /etc/os-release) ]]; then
    GRUB_CMD="grub-install"
elif [[ $(grep -Ei 'fedora|redhat' /etc/os-release) ]]; then
    GRUB_CMD="grub2-install"
else
    echo "Unsupported OS. Exiting..."
    exit 1
fi

FEDORA_ISO="$HOME/Downloads/Fedora.iso"
RHEL_QCOW2="$HOME/Downloads/rhel.qcow2"
RHEL_NBD="/dev/nbd1"
RHEL_MNT="/mnt/rhel"

# Logging function to display messages with timestamps
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

mount_fedora_images() {
    log "Mounting Fedora images"
    sudo mkdir -p /mnt/fedora /mnt/squash /mnt/rootfs
    sudo umount -l -f /mnt/fedora /mnt/squash /mnt/rootfs
    sudo mount -o loop $FEDORA_ISO /mnt/fedora
    sudo mount -o loop /mnt/fedora/LiveOS/squashfs.img /mnt/squash
    sudo mount -o loop /mnt/squash/LiveOS/rootfs.img /mnt/rootfs
}

# Check and load nbd module
load_nbd_module() {
    log "Loading nbd module"
    if ! lsmod | grep -q "^nbd "; then
        log "Loading nbd module..."
        sudo modprobe nbd max_part=16
    elif [[ "$(cat /sys/module/nbd/parameters/max_part)" != "16" ]]; then
        log "nbd is loaded, but not with the desired max_part parameter!"
    fi
}

# Cleanup function to ensure no stale mounts or nbd connections
cleanup() {
    log "Cleaning up"
    for device in $USB_NBD $RHEL_NBD; do
        if lsblk | grep -q ${device##*/}; then
            log "Cleaning up existing /dev/$device connection..."
            for partition in $(lsblk -o NAME | grep "^${device##*/}p"); do
                sudo umount -l /dev/$partition || true
            done
            sudo qemu-nbd --disconnect /dev/$device
        fi
    done
}

setup_USB_NBD() {
    log "Setting up USB NBD"
    sudo qemu-img create -f qcow2 virtual_usb.qcow2 5G
    sudo qemu-nbd --connect=$USB_NBD virtual_usb.qcow2
    sudo qemu-nbd --connect=$RHEL_NBD "$RHEL_QCOW2"

    # Partition the loop device
    log "Partitioning the loop device..."
    sudo parted -s $USB_NBD mklabel gpt
    sudo parted -s $USB_NBD mkpart primary fat32 1MiB 513MiB
    sudo parted $USB_NBD set 1 esp on
    sudo parted -s $USB_NBD mkpart primary 513MiB 515MiB
    sudo parted $USB_NBD set 2 bios_grub on
    sudo parted -s $USB_NBD mkpart primary ext4 515MiB 100%

    # Format the partitions
    log "Formatting the partitions..."
    sudo mkfs.vfat ${USB_NBD}p1
    sudo mkfs.ext4 ${USB_NBD}p3

    sudo e2label ${USB_NBD}p3 MY_LIVE_SYSTEM

    sudo mkdir -p $USB_EFI_DIR $USB_OS_DIR $RHEL_MNT
    sudo mount ${USB_NBD}p1 $USB_EFI_DIR
    sudo mount ${USB_NBD}p3 $USB_OS_DIR
    sudo mount ${RHEL_NBD}p2 $RHEL_MNT
}

install_grub() {
    log "Installing grub"
    sudo cp -r /mnt/fedora/EFI/* $USB_EFI_DIR
    sudo $GRUB_CMD --target=i386-pc --boot-directory=$USB_OS_DIR/boot $USB_NBD
}

create_grub_config() {
    log "Creating grub config"
    grub_cfg_path="$USB_OS_DIR/boot/grub/grub.cfg"
    sudo mkdir -p "$(dirname "$grub_cfg_path")"
    sudo cp /mnt/fedora/EFI/BOOT/grub.cfg $grub_cfg_path
}

copy_fedora_files() {
    log "Copying Fedora files..."
    sudo mkdir -p $USB_OS_DIR/images/pxeboot
    sudo cp -r /mnt/fedora/isolinux $USB_OS_DIR
    sudo rm -f $USB_OS_DIR/isolinux/{vmlinuz,initrd.img}
    
    VMLINUX=$(find $RHEL_MNT/boot/ -type f -name "vmlinuz*" ! -name "*rescue*" | sort -V | tail -n 1)
    INITRAMFS=$(find $RHEL_MNT/boot/ -type f -name "initramfs*" ! -name "*rescue*" ! -name "*boot*" | sort -V | tail -n 1)

    [[ -z "$VMLINUX" || -z "$INITRAMFS" ]] && { echo "VMLINUX and INITRAMFS are not defined"; exit 1; }

    sudo cp "$VMLINUX" $USB_OS_DIR/isolinux/vmlinuz
    sudo cp "$VMLINUX" $USB_OS_DIR/images/pxeboot/vmlinuz
    sudo cp "$INITRAMFS" $USB_OS_DIR/isolinux/initrd.img
    sudo cp "$INITRAMFS" $USB_OS_DIR/images/pxeboot/initrd
}

qcow2_to_squash() {
    log "Converting qcow2 to squashfs"
    local TMP_DIR
    TMP_DIR="/tmp/rhel-live-$(date '+%Y%m%d%H%M%S')"
    local MOUNT_POINT="$TMP_DIR/mnt"
    local ROOTFS_IMG="$TMP_DIR/LiveOS/rootfs.img"

    log "Creating temporary directory structure..."
    mkdir -p "$TMP_DIR/LiveOS" "$MOUNT_POINT"
    
    log "Creating ext4 image (rootfs.img)..."
    # Create a blank ext4 image. Adjust the size as necessary (here, 5G is used).
    dd if=/dev/zero of="$ROOTFS_IMG" bs=1M count=5120
    mkfs.ext4 "$ROOTFS_IMG"
    tune2fs -L "Anaconda" "$ROOTFS_IMG"
    
    log "Mounting the ext4 image and copying data..."
    mount -o loop "$ROOTFS_IMG" "$MOUNT_POINT"
    cp -a "$RHEL_MNT/"* "$MOUNT_POINT/"
    umount "$MOUNT_POINT"

    log "Creating squashfs.img from directory contents..."
    # This will create a squashfs image of the LiveOS directory and its contents
    mksquashfs "$TMP_DIR/LiveOS" "$TMP_DIR/squashfs.img" -b 131072

    log "Cleaning up temporary directory (keeping squashfs.img)..."
    mv "$TMP_DIR/squashfs.img" .
    rm -rf "$TMP_DIR"
}


final_cleanup() {
    log "Cleaning up..."
    sudo umount $USB_EFI_DIR
    sudo umount $USB_OS_DIR
    sudo qemu-nbd --disconnect $USB_NBD
    sudo modprobe -r nbd
    sudo umount -l -f /mnt/fedora /mnt/squash /mnt/rootfs
}

main() {
    mount_fedora_images
    load_nbd_module
    cleanup
    setup_USB_NBD
    install_grub
    create_grub_config
    copy_fedora_files
    final_cleanup
}

main
