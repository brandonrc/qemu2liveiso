#!/bin/bash

if lsblk | grep -q nbd1; then
    echo "Cleaning up existing /dev/nbd1 connection..."
    sudo qemu-nbd --disconnect /dev/nbd1
fi

sudo modprobe nbd max_part=16
sudo qemu-nbd --connect=/dev/nbd1 custom.qcow2
sudo mount /dev/nbd1p3 /mnt/myroot
ROOTFS_DEVICE=/dev/nbd1
