import os
import logging
from .squashfs import create_squashfs
from .grub import configure_grub
from .initramfs import create_initramfs

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def main():
    """
    Main function to orchestrate the creation of a Live Fedora ISO.
    """
    tmp_dir = "/tmp/live-image"
    squashfs_dir = os.path.join(tmp_dir, "squashfs")
    iso_dir = os.path.join(tmp_dir, "iso")

    os.makedirs(squashfs_dir, exist_ok=True)
    os.makedirs(iso_dir, exist_ok=True)

    # Step 1: Create the SquashFS image
    if not create_squashfs(squashfs_dir):
        logger.error("Failed to create SquashFS image")
        return

    # Step 2: Configure grub for booting the live image
    if not configure_grub(iso_dir):
        logger.error("Failed to configure grub")
        return

    # Step 3: Create the initramfs image
    if not create_initramfs(squashfs_dir):
        logger.error("Failed to create initramfs image")
        return

    logger.info("Live Fedora ISO creation successful")

if __name__ == "__main__":
    main()
