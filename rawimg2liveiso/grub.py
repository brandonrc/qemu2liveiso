import os
import logging

logger = logging.getLogger(__name__)

def configure_grub(tmp_iso_dir: str):
    """
    Configures grub to boot the live image
    """
    grub_conf_dir = os.path.join(tmp_iso_dir, "EFI", "BOOT")
    os.makedirs(grub_conf_dir, exist_ok=True)

    grub_conf = os.path.join(grub_conf_dir, "grub.cfg")

    grub_config = """
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
    """

    try:
        with open(grub_conf, "w") as file:
            file.write(grub_config)
        logger.info(f"Grub configuration created at {grub_conf}")
    except Exception as e:
        logger.error(f"Failed to create grub configuration: {str(e)}")
        return False

    return True
