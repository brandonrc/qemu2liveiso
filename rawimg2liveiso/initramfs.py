import os
import subprocess
import logging

logger = logging.getLogger(__name__)

def create_initramfs(tmp_squashfs_dir: str):
    """
    Creates an initramfs image for the live system
    """
    image_dir = os.path.join(tmp_squashfs_dir, "usr", "lib", "dracut", "images")
    os.makedirs(image_dir, exist_ok=True)

    initramfs_img = os.path.join(image_dir, "initramfs.img")

    dracut_cmd = [
        "dracut",
        "--no-hostonly",
        "--add", "livenet dmsquash-live dmsquash-live-ntfs convertfs pollcdrom",
        "--omit", "plymouth",
        "--no-early-microcode",
        "--no-mdadmconf",
        "--no-lvmconf",
        initramfs_img
    ]

    dracut_cmd = [
        "sudo",
        "dracut",
        "--force",
        "--verbose", 
        "--sysroot", 
        tmp_squashfs_dir,
        "--kver", 
        "$kernel_version",
        "--include", 
        "$MODULE_PATH",
        initramfs_img
"
    ]

    try:
        subprocess.run(dracut_cmd, check=True)
        logger.info(f"Initramfs image created at {initramfs_img}")
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to create initramfs image: {str(e)}")
        return False

    return True
