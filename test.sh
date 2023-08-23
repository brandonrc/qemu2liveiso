#!/bin/bash

# Parameters
LIVE_ISO="/home/khan/work-area/Fedora-Workstation-Live-x86_64-28-1.1.iso"
MOUNT_POINT="/mnt/fedora-live"
NEW_DIR="/fedora"
NEW_SQUASHFS="/tmp/store/rootfs.img"
NEW_INITFS="/tmp/initrd.img"

# Check if root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Mount the live ISO
echo "Making directories"
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
cp -v /home/khan/squashfs.img $NEW_DIR/LiveOS/squashfs.img
cp -v $NEW_INITFS $NEW_DIR/images/pxeboot/initrd.img
cp -v $NEW_INITFS $NEW_DIR/isolinux/initrd.img
cp -v /boot/vmlinuz-4.18.0-477.10.1.el8_8.x86_64 $NEW_DIR/images/pxeboot/vmlinuz
cp -v /boot/vmlinuz-4.18.0-477.10.1.el8_8.x86_64 $NEW_DIR/isolinux/vmlinuz


# # GRUB2 files
# GRUB_FILES="$NEW_DIR/EFI/BOOT/BOOT.conf $NEW_DIR/EFI/BOOT/grub.cfg"

# # ISOLINUX files
# ISOLINUX_FILES="$NEW_DIR/isolinux/grub.conf $NEW_DIR/isolinux/isolinux.cfg"

# # Add serial console configuration to GRUB files
# for file in $GRUB_FILES; do
#     sed -i '1i serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1' "$file"
#     sed -i '2i terminal_input serial console' "$file"
#     sed -i '3i terminal_output serial console' "$file"

#     # Append console=ttyS0,115200n8 to each kernel command line and remove 'quiet'
#     sed -i "/linuxefi \/images\/pxeboot\/vmlinuz/ s/$/ console=ttyS0,115200n8/" "$file"
#     sed -i 's/ quiet//g' "$file"
# done

# # Modify ISOLINUX files
# for file in $ISOLINUX_FILES; do
#     sed -i 's/ quiet//g' "$file"
#     sed -i "/kernel / s/$/ console=ttyS0,115200n8/" "$file"
# done


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
    -V "Fedora-WS-Live-28-1-1" \
    .

# Add checksum to the ISO for bootloader validation
isomd5sum --implantmd5 custom-fedora-live.iso

popd

echo "Done. The custom ISO is located at $NEW_DIR/custom-fedora-live.iso"

