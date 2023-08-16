# Creating a Bootable Image from a Custom QCOW2

## Prerequisites

- Ensure you have `qemu-utils`, `grub2`, and `squashfs-tools` installed.
- Start with a pre-configured `qcow2` image named `custom.qcow2`.

### PACKAGES
```
sudo yum install \
    libguestfs-tools-c \
    grub2-efi-x64-modules
```

## 1. Creating the Root FS by Mounting the QCOW2 Image

<!-- ```bash
sudo mkdir -p /mnt/myroot
sudo guestmount -a custom.qcow2 -m /dev/sda3 /mnt/myroot
``` -->

```bash
if lsblk | grep -q nbd1; then
    echo "Cleaning up existing /dev/nbd1 connection..."
    sudo qemu-nbd --disconnect /dev/nbd1
fi

sudo modprobe nbd max_part=16
sudo qemu-nbd --connect=/dev/nbd1 custom.qcow2
sudo mount /dev/nbd1p3 /mnt/myroot
ROOTFS_DEVICE=/dev/nbd1
```

## 2. Creating a SquashFS Image

Navigate to the directory where you want to store your SquashFS image:

```bash
export TMPSTORE=/tmp/store
mkdir -p $TMPSTORE
cd $TMPSTORE
dir_size=$(sudo du -sm /mnt/myroot | awk '{print $1}')
img_size=$((dir_size + 200))
dd if=/dev/zero of=rootfs.img bs=1M count=$img_size
mkfs.ext4 rootfs.img

sudo mkdir -p /mnt/rootimg
sudo mount -o loop rootfs.img /mnt/rootimg
sudo cp -a /mnt/myroot* /mnt/rootimg
sudo umount /mnt/rootimg
mkdir -p LiveOS
mv rootfs.img LiveOS/
mksquashfs LiveOS custom_root.squashfs -comp xz
```


create_squashfs_from_rootfs() {
    # Check if the directory exists
    if [ ! -d "$TMP_SQUASHFS_DIR/lib/modules/" ]; then
        echo "Directory $TMP_SQUASHFS_DIR/lib/modules/ does not exist"
        return 1
    fi

    # Calculate the size of the directory and create the rootfs image
    dir_size=$(sudo du -sm "$TMP_SQUASHFS_DIR" | awk '{print $1}')
    img_size=$((dir_size + 200))
    dd if=/dev/zero of=rootfs.img bs=1M count=$img_size
    mkfs.ext4 rootfs.img

    # Mount the image and copy contents
    sudo mount -o loop rootfs.img /mnt
    sudo cp -a $TMP_SQUASHFS_DIR/* /mnt/
    sudo umount /mnt

    # Move rootfs.img into LiveOS directory
    mkdir -p LiveOS
    mv rootfs.img LiveOS/

    # Create the SquashFS filesystem
    sudo mksquashfs LiveOS "$SQUASHFS_OUTPUT_PATH" -comp xz

    echo "SquashFS file system has been created as $SQUASHFS_OUTPUT_PATH"
}


## 3. Extracting Kernel and Initramfs

These will be located in `/mnt/myroot/boot`. Look for files named `vmlinuz-*` and `initramfs-*.img`.

```bash
export TMPSTORE=/tmp/store
mkdir -p $TMPSTORE
cp /mnt/myroot/boot/vmlinuz-* $TMPSTORE
cp /mnt/myroot/boot/initramfs-*.img $TMPSTORE
```




## 4. Create usb drive image


### 1. Create the QCOW2 Image:

```bash
qemu-img create -f qcow2 virtual_usb.qcow2 5G
```

### 2. Setup Partitions & File Systems on the Image:

Firstly, map the image to a loopback device:

```bash
sudo qemu-nbd --disconnect /dev/nbd0
sudo modprobe nbd max_part=16
sudo qemu-nbd --connect=/dev/nbd0 virtual_usb.qcow2
LOOP_DEVICE=/dev/nbd0
```

Script example:
```
if lsblk | grep -q nbd0; then
    echo "Cleaning up existing /dev/nbd0 connection..."
    sudo qemu-nbd --disconnect /dev/nbd0
fi

sudo modprobe nbd max_part=16
sudo qemu-nbd --connect=/dev/nbd0 virtual_usb.qcow2
LOOP_DEVICE=/dev/nbd0

```

Now, use `parted` to set up partitions automatically:

```bash
sudo parted -s $LOOP_DEVICE mklabel gpt
sudo parted -s $LOOP_DEVICE mkpart primary fat32 1MiB 513MiB
sudo parted -s $LOOP_DEVICE set 1 esp on
sudo parted -s $LOOP_DEVICE mkpart primary ext4 513MiB 100%
```

Format the partitions:

```bash
sudo mkfs.vfat ${LOOP_DEVICE}p1
sudo mkfs.ext4 ${LOOP_DEVICE}p2
```

### 3. Mounting and Copying Data:

Mount the partitions:

```bash
sudo mkdir -p /mnt/virtual_usb_efi
sudo mkdir -p /mnt/virtual_usb_os
sudo mount ${LOOP_DEVICE}p1 /mnt/virtual_usb_efi
sudo mount ${LOOP_DEVICE}p2 /mnt/virtual_usb_os
```

Now you can copy your data, kernel, initramfs, and other necessary files into `/mnt/virtual_usb_os`.

### 4. Installing GRUB:

For both UEFI and BIOS boot:

```bash
sudo grub2-install --target=x86_64-efi --no-uefi-secure-boot --efi-directory=/mnt/virtual_usb_efi --boot-directory=/mnt/virtual_usb_os/boot --removable --modules="part_gpt part_msdos"


sudo grub2-install --target=i386-pc --boot-directory=/mnt/virtual_usb_os/boot $LOOP_DEVICE
```

Ensure you have the GRUB configuration set up correctly in `/mnt/virtual_usb_os/boot/grub/grub.cfg`.

### 5. Cleanup:

Unmount the partitions and detach the loopback device:

```bash
sudo umount /mnt/virtual_usb_efi
sudo umount /mnt/virtual_usb_os
sudo qemu-nbd --disconnect /dev/nbd0
sudo modprobe -r nbd
```

Now, `virtual_usb.qcow2` should be ready to boot using QEMU/KVM.

















<!-- ## 4. Creating a Bootable QCOW2 (or ISO)

- For a QCOW2 image:

```bash
qemu-img create -f qcow2 virtual_usb.qcow2 5G
```

- If you wish to create an ISO (after completing the bootloader installation):

```bash
genisoimage -o output.iso /path/to/your/virtual_usb/contents
```

## 4.5. Partitioning USB virtual drive -->


## 5. Installing GRUB2 (for both UEFI and BIOS)

- Mount the new `qcow2` image:

```bash
mkdir -p /mnt/virtual_usb
guestmount -a virtual_usb.qcow2 -m /dev/sda1 /mnt/virtual_usb
```

- Copy the `vmlinuz`, `initramfs`, and `custom_root.squashfs` to it:

```bash
export TMPSTORE=/tmp/store
mkdir -p $TMPSTORE
cp /path/to/store/vmlinuz-* /mnt/virtual_usb/
cp /path/to/store/initramfs-*.img /mnt/virtual_usb/
cp /path/to/store/custom_root.squashfs /mnt/virtual_usb/
```

- Install GRUB2:

For BIOS:

```bash
grub2-install --target=i386-pc --boot-directory=/mnt/virtual_usb/boot /path/to/virtual_usb.qcow2
```

For UEFI:

```bash
grub2-install --target=x86_64-efi --efi-directory=/mnt/virtual_usb/EFI --boot-directory=/mnt/virtual_usb/boot /path/to/virtual_usb.qcow2
```

- Create a GRUB config file at `/mnt/virtual_usb/boot/grub/grub.cfg`:

```bash
menuentry 'Custom Boot' {
   set root=(hd0,1)
   linux /vmlinuz root=/dev/sda1 rootfstype=squashfs rootflags=loop real_root=/custom_root.squashfs
   initrd /initramfs
}
```

## 5.5. Set label for usb device partition
```
sudo e2label /dev/sdx3 MY_LIVE_SYSTEM
```

## 6. Booting from the Virtual USB

Run:

```bash
qemu-kvm -hda virtual_usb.qcow2 -m 2048
```

## 7. Transferring to Physical USB (Optional)

If you've chosen the QCOW2 path and wish to transfer to a physical USB:

```bash
dd if=virtual_usb.qcow2 of=/dev/sdX bs=4M status=progress
```

**Caution:** Replace `/dev/sdX` with your USB drive's device path. Ensure you pick the correct device to avoid data loss.


#### EXAMPLE GRUB
```

set timeout=10
set default=0

menuentry 'My Custom RHEL8' {
  search --no-floppy --set=root --label MY_LIVE_SYSTEM
  linux /boot/vmlinuz rootfstype=squashfs rootflags=loop real_root=/boot/myroot.squashfs
  initrd /boot/initramfs
}
```