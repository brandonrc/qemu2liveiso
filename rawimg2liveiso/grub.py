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
    search --no-floppy --set=root -l 'Fedora-LiveOS'
    set default="0"
    set timeout=10

    menuentry 'Start Fedora LiveOS' {
        echo 'Loading kernel ...'
        linux /images/pxeboot/vmlinuz root=live:CDLABEL=Fedora-LiveOS rd.live.image quiet rhgb rd.luks=0 rd.md=0 rd.dm=0
        echo 'Loading initrd ...'
        initrd /images/pxeboot/initrd.img
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
