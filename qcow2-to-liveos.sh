#!/bin/bash


TMPSTORE=/tmp/store
ROOTIMG_DIR=/mnt/rootimg
ROOT_DIR=/mnt/myroot

mkdir -p $TMPSTORE
mkdir -p $ROOT_DIR
sudo rm -rf $TMPSTORE/*

if lsblk | grep -q nbd1; then
    echo "Cleaning up existing /dev/nbd1 connection..."
    sudo qemu-nbd --disconnect /dev/nbd1
fi

# Cleanup
# 
sudo umount -l /dev/nbd*
sudo qemu-nbd --disconnect /dev/nbd1
sudo qemu-nbd --disconnect /dev/nbd0

# Mounting the rootfs
sudo modprobe nbd max_part=16
sudo qemu-nbd --connect=/dev/nbd1 custom.qcow2
sudo mount /dev/nbd1p3 $ROOT_DIR
ROOTFS_DEVICE=/dev/nbd1


# Creating the squash FS
cd $TMPSTORE
dir_size=$(sudo du -sm $ROOT_DIR | awk '{print $1}')
img_size=$((dir_size + 200))
dd if=/dev/zero of=rootfs.img bs=1M count=$img_size
mkfs.ext4 rootfs.img
sudo e2label rootfs.img "Anaconda"


sudo mkdir -p $ROOTIMG_DIR
sudo mount -o loop rootfs.img $ROOTIMG_DIR
sudo cp -a $ROOT_DIR/* $ROOTIMG_DIR
sudo umount $ROOTIMG_DIR
mkdir -p LiveOS
mv rootfs.img LiveOS/
mksquashfs LiveOS custom_root.squashfs -comp xz


# Copying the vmlinuz and initramfs
cp $ROOT_DIR/boot/vmlinuz-* $TMPSTORE
cp $ROOT_DIR/boot/initramfs-*.img $TMPSTORE

sudo umount -l /dev/nbd*
sudo qemu-nbd --disconnect /dev/nbd1
sudo qemu-nbd --disconnect /dev/nbd0