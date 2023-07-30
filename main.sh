#!/bin/bash

# /boot
#     /grub
#         grub.cfg
#     initrd.img
#     vmlinuz
# /LiveOS
#     rootfs.squashfs

#!/bin/bash

# Usage function to display script usage information
print_usage() {
    echo "Usage: $0 <tar_file_path> [output_dir_path]"
    echo "tar_file_path: The path to the .tar file to convert"
    echo "output_dir_path: Optional. The directory where the output .iso file will be stored"
}

# Check if tar_file_path argument is provided
if [ -z "$1" ]; then
    echo "Error: No tar_file_path provided"
    print_usage
    exit 1
fi

TAR_FILE_PATH=$1

# If the tar file does not exist, print an error and exit
if [ ! -f "$TAR_FILE_PATH" ]; then
    echo "Error: File not found: $TAR_FILE_PATH"
    exit 1
fi


MAIN_TMP_DIR=$(mktemp -d)
TMP_SQUASHFS_DIR=$(mktemp -d)

trap 'clean_up' EXIT

BOOT_PATH="$MAIN_TMP_DIR/boot"

# Get the absolute directory path
DIR_PATH=$(dirname $(readlink -f "$TAR_FILE_PATH"))

# If output_dir_path argument is provided, use it. Else use the directory of the tar file
ISO_OUTPUT_DIR=${2:-$DIR_PATH}

SQUASHFS_OUTPUT_PATH="$MAIN_TMP_DIR/LiveOS/rootfs.squashfs"

# initramfs Variables
OUTPUT_INITRAMFS_IMG="$BOOT_PATH/initramfs.img"
OUTPUT_VMLINUZ="$BOOT_PATH/vmlinuz"
DRACUT_DIR="/usr/lib/dracut/modules.d"
MODULE_NAME="99live"
MODULE_PATH="$DRACUT_DIR/$MODULE_NAME"
MODULE_SETUP_FILE="module-setup.sh"
LIVE_ROOT_SCRIPT="live-root.sh"

clean_up() {
    if [[ -d "$MAIN_TMP_DIR" ]]; then
        echo "Removing main directory"
        # sudo rm -rf "$MAIN_TMP_DIR"
        echo "Removing squashfs directory"
        # sudo rm -rf "$TMP_SQUASHFS_DIR"
    fi
}

create_iso() {
    sudo grub2-mkrescue -o $ISO_OUTPUT_DIR/live.iso $MAIN_TMP_DIR
    # Needs a package sudo dnf install genisoimage
    # mkisofs -o live.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -R -J -v -T $MAIN_TMP_DIR

}

# Function to create directories
create_directories() {
    sudo mkdir -p "$MAIN_TMP_DIR"/boot/grub
    sudo chmod 0777 -R "$MAIN_TMP_DIR"
    sudo mkdir -p "$MAIN_TMP_DIR"/LiveOS
    sudo chmod 0777 -R "$MAIN_TMP_DIR"
}

copy_vmlinuz() {
    echo "---------------COPY VMLINUZ ----------------"
    echo "VMLINUZ filename is located: vmlinuz-${kernel_version}"
    local vmlinuz_filename="vmlinuz-${kernel_version}"
    sudo cp -r /boot/"$vmlinuz_filename" "$OUTPUT_VMLINUZ"
}

create_grub_cfg() {
    cat << EOF | sudo tee "$MAIN_TMP_DIR/boot/grub/grub.cfg"
set timeout=10
set default=0

menuentry "My Live System" {
    set root=(hd0,1)
    linux /boot/vmlinuz \
        root=/dev/ram0 \
        rd.live.image \
        rd.luks=0 \
        rd.md=0 \
        rd.dm=0 \
        debug \
        console=tty0 \
        console=ttyS0,115200n8
    initrd /boot/initramfs.img
}
EOF
}

# Function to create module-setup.sh file
create_module_setup() {
    sudo mkdir -p "$TMP_SQUASHFS_DIR/$MODULE_PATH"
    cat << EOF | sudo tee "$TMP_SQUASHFS_DIR/$MODULE_PATH/$MODULE_SETUP_FILE"
#!/bin/bash

check() {
    return 0
}

depends() {
    echo rootfs-block
}

install() {
    inst_hook cmdline 30 "\$moddir/live-root.sh"
    inst /sbin/pivot_root
}
EOF
    sudo chmod +x "$TMP_SQUASHFS_DIR/$MODULE_PATH/$MODULE_SETUP_FILE"
}

# Function to create live-root.sh file
create_live_root_script() {
    cat << EOF | sudo tee "$TMP_SQUASHFS_DIR/$MODULE_PATH/$LIVE_ROOT_SCRIPT"
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
EOF
    sudo chmod +x "$TMP_SQUASHFS_DIR/$MODULE_PATH/$LIVE_ROOT_SCRIPT"
}

configure_dracut() {
    sudo mkdir -p "$TMP_SQUASHFS_DIR/etc/dracut.conf.d/"

    cat << EOF | sudo tee "$TMP_SQUASHFS_DIR/etc/dracut.conf.d/01-liveos.conf"
mdadmconf="no"
lvmconf="no"
squash_compress="xz"
add_dracutmodules+=" livenet dmsquash-live dmsquash-live-ntfs convertfs pollcdrom qemu qemu-net "
omit_dracutmodules+=" plymouth "
hostonly="no"
early_microcode="no"
EOF

}

export VERBOSE=true

# Function to create the initramfs
create_initramfs() {

    if [[ -z "$kernel_version" ]]; then
        echo "No kernel version specified, creating initramfs using current kernel"
        return 1
    fi

    echo "Creating initramfs"

    local initramfs_filename="initramfs-${kernel_version}.img"
    local latest_initramfs="$TMP_SQUASHFS_DIR/boot/$initramfs_filename"
    local backup_initramfs="$latest_initramfs.bak"

    # Backup the latest initramfs
    echo "Backing up latest initramfs"
    if [[ -f "$latest_initramfs" ]]; then
        echo "Copying $latest_initramfs to $backup_initramfs"
        sudo cp "$latest_initramfs" "$backup_initramfs"
    else
        echo "No initramfs found to backup"
    fi

    # CONFIGURATIONS



    echo "Kernel version specified as $kernel_version, creating initramfs"
    if [ "$VERBOSE" = true ]; then
        echo "-------------------------------------------------------"
        sudo dracut --force --verbose --sysroot "$TMP_SQUASHFS_DIR" --kver "$kernel_version" --include "$MODULE_PATH" "$OUTPUT_INITRAMFS_IMG"
    else
        echo "-------------------------------------------------------"
        sudo dracut --force --sysroot "$TMP_SQUASHFS_DIR" --kver "$kernel_version" --include "$MODULE_PATH" "$OUTPUT_INITRAMFS_IMG"
    fi

    dracut_status=$?

    echo "-------------------------------"
    echo "MODULE_PATH: $MODULE_PATH"
    echo "TMP_SQUASHFS_DIR: $TMP_SQUASHFS_DIR"
    echo "OUTPUT_INITRAMFS_IMG: $OUTPUT_INITRAMFS_IMG"
    echo "-------------------------------"

    # After dracut command
    if [ $dracut_status -ne 0 ]; then
        echo "Dracut command failed with exit status: $dracut_status"
        return 1
    elif [ ! -f "$OUTPUT_INITRAMFS_IMG" ]; then
        echo "Failed to create initramfs at: $OUTPUT_INITRAMFS_IMG"
        echo "Attempting to manually copy the file..."
        sudo cp "$TMP_SQUASHFS_DIR/boot/initramfs-${kernel_version}.img" "$OUTPUT_INITRAMFS_IMG"
        if [ $? -eq 0 ]; then
            echo "Initramfs manually copied successfully to: $OUTPUT_INITRAMFS_IMG"
        else
            echo "Manual copying failed as well."
            return 1
        fi
    else
        echo "Initramfs created successfully at: $OUTPUT_INITRAMFS_IMG"
        sudo chmod 644 "$OUTPUT_INITRAMFS_IMG"
    fi
}



extract_tar_xz() {
    # Check if the tar file exists
    if [ ! -f "$TAR_FILE_PATH" ]; then
        echo "File not found: $TAR_FILE_PATH"
        return 1
    fi

    # Extract the tar.xz file to the temporary directory
    sudo tar -xf "$TAR_FILE_PATH" -C "$TMP_SQUASHFS_DIR"

    export kernel_version=$(ls "$TMP_SQUASHFS_DIR/lib/modules/" | sort -V | tail -n 1)
}

create_squashfs_from_rootfs() {
    # Check if the directory exists
    if [ ! -d "$TMP_SQUASHFS_DIR/lib/modules/" ]; then
        echo "Directory $extracted_fs_root/lib/modules/ does not exist"
        return 1
    fi

    # Create the SquashFS filesystem
    sudo mksquashfs "$TMP_SQUASHFS_DIR" "$SQUASHFS_OUTPUT_PATH" -comp xz

    echo "SquashFS file system has been created as $SQUASHFS_OUTPUT_PATH"
}

install_packages() {
    # array of paths to mount and unmount
    paths_to_mount=("/proc" "/sys" "/dev")

    for path in "${paths_to_mount[@]}"; do
        sudo mount -o bind $path "$TMP_SQUASHFS_DIR$path"
        if [ $? -ne 0 ]; then
            echo "Failed to mount $path"
            return 1
        fi
    done

    # sudo dnf install epel-release epel-next-release --nogpgcheck -y
    sudo dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm -y
    if [ $? -ne 0 ]; then
        echo "Failed to install epel-release and epel-next-release"
        return 1
    fi

    sudo dnf update -y
    if [ $? -ne 0 ]; then
        echo "Failed to do a dnf update"
        return 1
    fi

    sudo yum --installroot=$TMP_SQUASHFS_DIR install -y --nogpgcheck \
    biosdevname \
    bluez \
    cifs-utils \
    device-mapper-multipath \
    dhcp-client \
    dracut* \
    fcoe-utils \
    gnupg2 \
    iscsi-initiator-utils \
    jq \
    kernel-core \
    kernel-modules \
    kernel-modules-extra \
    lvm2 \
    mdadm \
    memstrack \
    nbd \
    nfs-utils \
    ntfs-3g \
    nvme-cli \
    openssh-clients \
    pcsc-lite \
    rng-tools \
    systemd \
    tpm2-tss
    if [ $? -ne 0 ]; then
        echo "Failed to install packages"
        return 1
    fi

    # Unmount in reverse order
    for ((idx=${#paths_to_mount[@]}-1 ; idx>=0 ; idx--)) ; do
        sudo umount "$TMP_SQUASHFS_DIR${paths_to_mount[idx]}"
        if [ $? -ne 0 ]; then
            echo "Failed to unmount ${paths_to_mount[idx]}"
            return 1
        fi
    done
}


# Define an ordered list of functions to execute
func_order=( "create_directories"
             "extract_tar_xz"
             "install_packages"
             "create_grub_cfg"
             "create_module_setup"
             "create_live_root_script"
             "configure_dracut"
             "create_initramfs"
             "copy_vmlinuz"
             "create_squashfs_from_rootfs"
             "create_iso"
             "clean_up" )

# Define error messages
declare -A func_errors=( ["create_directories"]="Failed to create directories"
                         ["extract_tar_xz"]="Failed to extract tar file with rootfs"
                         ["install_packages"]="Failed to install packages"
                         ["create_squashfs_from_rootfs"]="Failed to create SquashFS"
                         ["create_grub_cfg"]="Failed to create GRUB config"
                         ["create_module_setup"]="Failed to setup module"
                         ["create_live_root_script"]="Failed to create live root script"
                         ["configure_dracut"]="Failed to setup dracut config file"
                         ["create_initramfs"]="Failed to create initramfs"
                         ["copy_vmlinuz"]="Failed to copy vmlinuz"
                         ["create_iso"]="Failed to create ISO"
                         ["clean_up"]="Failed to clean up" )

# Loop over each function in func_order array
for func in "${func_order[@]}"; do
    # Try to run the function
    $func
    # Capture the exit status
    exit_status=$?

    # If the function failed, print error message and exit
    if [[ $exit_status -ne 0 ]]; then
        echo "Error: ${func_errors[$func]}"
        exit $exit_status
    fi
done



