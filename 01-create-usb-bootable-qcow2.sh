#!/bin/bash

LOOP_DEVICE=/dev/nbd0
USB_EFI_DIR=/mnt/virtual_usb_efi
USB_OS_DIR=/mnt/virtual_usb_os

if ! lsmod | grep -q "^nbd "; then
    # Load the module if it's not loaded
    sudo modprobe nbd max_part=16
else
    # Check if it was loaded with the desired parameter
    if [[ "$(cat /sys/module/nbd/parameters/max_part)" != "16" ]]; then
        echo "nbd is loaded, but not with the desired max_part parameter!"
    fi
fi

sudo qemu-img create -f qcow2 virtual_usb.qcow2 5G

if lsblk | grep -q nbd0; then
    echo "Cleaning up existing $LOOP_DEVICE connection..."
    sudo qemu-nbd --disconnect $LOOP_DEVICE
fi

sudo qemu-nbd --connect=$LOOP_DEVICE virtual_usb.qcow2


# Make the partitions

sudo parted -s $LOOP_DEVICE mklabel gpt

# Create an EFI System Partition
sudo parted -s $LOOP_DEVICE mkpart primary fat32 1MiB 513MiB
sudo parted $LOOP_DEVICE set 1 esp on

# Create a BIOS Boot Partition
sudo parted -s $LOOP_DEVICE mkpart primary 513MiB 515MiB
sudo parted $LOOP_DEVICE set 2 bios_grub on

# Create the main partition
sudo parted -s $LOOP_DEVICE mkpart primary ext4 515MiB 100%


# Format the partitions
sudo mkfs.vfat ${LOOP_DEVICE}p1
sudo mkfs.ext4 ${LOOP_DEVICE}p3

sudo mkdir -p $USB_EFI_DIR
sudo mkdir -p $USB_OS_DIR
sudo mount ${LOOP_DEVICE}p1 $USB_EFI_DIR
sudo mount ${LOOP_DEVICE}p3 $USB_OS_DIR


# Determine if we are using grub-install or grub2-install
GRUB_CMD=""
if command -v grub2-install &> /dev/null; then
    GRUB_CMD="grub2-install"
    echo "Cuurently we do not support grub2-install because of redhat developers."
    exit 1
elif command -v grub-install &> /dev/null; then
    GRUB_CMD="grub-install"
else
    echo "Neither grub2-install nor grub-install found. Please install GRUB for your system."
    exit 1
fi

# Install GRUB
sudo $GRUB_CMD --target=x86_64-efi --no-uefi-secure-boot --efi-directory=$USB_EFI_DIR --boot-directory=$USB_OS_DIR/boot --removable --modules="part_gpt part_msdos"
sudo $GRUB_CMD --target=i386-pc --boot-directory=$USB_OS_DIR/boot $LOOP_DEVICE

# Clean up 

sudo umount $USB_EFI_DIR
sudo umount $USB_OS_DIR
sudo qemu-nbd --disconnect $LOOP_DEVICE
sudo modprobe -r nbd