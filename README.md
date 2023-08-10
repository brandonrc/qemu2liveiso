# Creating a Bootable Image from a Custom QCOW2

## Prerequisites

- Ensure you have `qemu-utils`, `grub2`, and `squashfs-tools` installed.
- Start with a pre-configured `qcow2` image named `custom.qcow2`.

### PACKAGES

#### For RedHat/CentOS:

1. **qemu-utils**: Part of the QEMU software package.
2. **grub2**: Provides GRUB boot loader.
3. **squashfs-tools**: For SquashFS file systems.
4. **libguestfs-tools-c**: Provides tools for accessing and modifying guest disk images.
5. **grub2-efi-x64-modules**: GRUB2 modules for UEFI for x64 machines.

To install them:

```bash
sudo yum install qemu-img grub2 squashfs-tools libguestfs-tools-c grub2-efi-x64-modules
```

#### For Ubuntu:

1. **qemu-utils**: QEMU image management utilities.
2. **grub-efi-amd64-bin**: GRUB EFI for AMD64 architectures.
3. **grub-pc-bin**: General GRUB tools and modules.
4. **squashfs-tools**: Tools for SquashFS file systems.
5. **libguestfs-tools**: Tools for accessing and modifying guest disk images.

To install them:

```bash
sudo apt-get update
sudo apt-get install qemu-utils grub-efi-amd64-bin grub-pc-bin squashfs-tools libguestfs-tools
```




## 1. Creating the Root FS by Mounting the QCOW2 Image

#### Setup
```

```


```bash
sudo modprobe nbd max_part=16
export ROOT_DIR=/mnt/myroot
export USB_NBD=/dev/nbd1
export TMPSTORE=/tmp/store


sudo mkdir -p $ROOT_DIR
sudo mkdir -p $TMPSTORE
sudo qemu-nbd --disconnect $USB_NBD
sudo qemu-nbd --connect=$USB_NBD custom.qcow2
sudo mount "$USB_NBD"p3 $ROOT_DIR

# Making the squashfs root image
cd $ROOT_DIR
sudo mksquashfs /mnt/myroot custom_root.squashfs

# Extracting the vmlinuz and initramfs
sudo cp $ROOT_DIR/boot/vmlinuz-* $TMPSTORE
sudo cp $ROOT_DIR/boot/initramfs-*.img $TMPSTORE

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
#!/bin/bash
sudo parted -s $LOOP_DEVICE mklabel gpt

# Create an EFI System Partition
sudo parted -s $LOOP_DEVICE mkpart primary fat32 1MiB 513MiB
sudo parted $LOOP_DEVICE set 1 esp on

# Create a BIOS Boot Partition
sudo parted -s $LOOP_DEVICE mkpart primary 513MiB 515MiB
sudo parted $LOOP_DEVICE set 2 bios_grub on

# Create the main partition
sudo parted -s $LOOP_DEVICE mkpart primary ext4 515MiB 100%
```

<!-- Format the partitions:

```bash
sudo mkfs.vfat ${LOOP_DEVICE}p1
sudo mkfs.ext4 ${LOOP_DEVICE}p2
``` -->

### 3. Mounting and Copying Data:

Mount the partitions:

```bash
mkdir -p /mnt/virtual_usb_efi
mkdir -p /mnt/virtual_usb_os
sudo mount ${LOOP_DEVICE}p1 /mnt/virtual_usb_efi
sudo mount ${LOOP_DEVICE}p3 /mnt/virtual_usb_os
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

