#!/bin/bash

CURRENT_DIR=$(pwd)

if ! lsmod | grep -q "^nbd "; then
    # Load the module if it's not loaded
    sudo modprobe nbd max_part=16
else
    # Check if it was loaded with the desired parameter
    if [[ "$(cat /sys/module/nbd/parameters/max_part)" != "16" ]]; then
        echo "nbd is loaded, but not with the desired max_part parameter!"
    fi
fi

for device in nbd0 nbd1; do
    if lsblk | grep -q $device; then
        echo "Cleaning up existing /dev/$device connection..."
        
        # Lazy unmount all partitions of this nbd device
        for partition in $(lsblk -o NAME | grep "^${device}p"); do
            sudo umount -l /dev/$partition || true
        done

        # Disconnect the nbd device
        sudo qemu-nbd --disconnect /dev/$device
    fi
done


ROOT_DIR=/mnt/myroot
ROOTFS_NBD=/dev/nbd1
USB_NBD=/dev/nbd0
USB_EFI_DIR=/mnt/virtual_usb_efi
USB_OS_DIR=/mnt/virtual_usb_os

sudo mkdir -p $ROOT_DIR
sudo mkdir -p $USB_EFI_DIR
sudo mkdir -p $USB_OS_DIR
sudo qemu-nbd --connect=$ROOTFS_NBD custom.qcow2
sudo qemu-nbd --connect=$USB_NBD virtual_usb.qcow2
sudo mount ${ROOTFS_NBD}p3 $ROOT_DIR
sudo mount ${USB_NBD}p1 $USB_EFI_DIR
sudo mount ${USB_NBD}p3 $USB_OS_DIR

# Making the squashfs root image
cd $USB_OS_DIR
sudo mksquashfs $ROOT_DIR custom_root.squashfs

# Extracting the vmlinuz and initramfs
sudo cp $ROOT_DIR/boot/vmlinuz-* $USB_OS_DIR/vmlinuz
sudo cp $ROOT_DIR/boot/initramfs-*.img $USB_OS_DIR/initramfs.img


# Clean up 
cd CURRENT_DIR
sudo umount -l $USB_EFI_DIR
sudo umount -l $USB_OS_DIR
sudo umount -l $ROOT_DIR
sudo qemu-nbd --disconnect $USB_NBD
sudo qemu-nbd --disconnect $ROOTFS_NBD
sudo modprobe -r nbd