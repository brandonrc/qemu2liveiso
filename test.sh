#!/bin/bash

# Parameters
LIVE_ISO="/home/khan/work-area/Fedora-Workstation-Live-x86_64-28-1.1.iso"
MOUNT_POINT="/mnt/fedora-live"
NEW_DIR="/fedora"
NEW_SQUASHFS="/tmp/store/squashfs.img"

# Check if root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Mount the live ISO
mkdir -p $MOUNT_POINT
mkdir -p $NEW_DIR
rm -rf $NEW_DIR/*
sudo mount -l $MOUNT_POINT
mount -o loop $LIVE_ISO $MOUNT_POINT

# Copy the contents to a new directory
cp -a $MOUNT_POINT/* $NEW_DIR/

# Unmount the live ISO
umount $MOUNT_POINT
rmdir $MOUNT_POINT

# Replace the squashfs file in the LiveOS directory of the new directory
cp $NEW_SQUASHFS $NEW_DIR/LiveOS/squashfs.img

# Modify the isolinux.cfg for BIOS boot
sed -i '/menu label ^Install Fedora/,+4d' $NEW_DIR/isolinux/isolinux.cfg
sed -i 's|linux /images/pxeboot/vmlinuz|linux /images/pxeboot/vmlinuz console=ttyS0,115200|' $NEW_DIR/isolinux/isolinux.cfg

# Recreate the bootable ISO
pushd $NEW_DIR
genisoimage \
    -o custom-fedora-live.iso \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -J -R \
    -V "Custom Fedora Live" \
    .

# Add checksum to the ISO for bootloader validation
isomd5sum --implantmd5 custom-fedora-live.iso

popd

echo "Done. The custom ISO is located at $NEW_DIR/custom-fedora-live.iso"

