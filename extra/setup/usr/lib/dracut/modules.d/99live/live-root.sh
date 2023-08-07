#!/bin/bash

# Print some debugging information
echo "Starting live-root.sh script..."
ls -la /sysroot

# Mount the SquashFS image
mount -r -t squashfs -o loop /LiveOS/rootfs.squashfs /sysroot

# Create a tmpfs to overlay the SquashFS image
mount -t tmpfs -o size=100% none /sysroot/tmp

# Create the overlay filesystem
mount -t overlay overlay -o lowerdir=/sysroot,upperdir=/sysroot/tmp,workdir=/sysroot/work /sysroot

# Pivot to the new root filesystem
pivot_root /sysroot /sysroot/initrd

# Start the regular boot process
exec /sbin/init
