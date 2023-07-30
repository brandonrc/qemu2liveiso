import os
import logging

logger = logging.getLogger(__name__)

def configure_dracut(tmp_squashfs_dir: str):
    """
    Configures dracut to include the live root module
    """
    dracut_conf_dir = os.path.join(tmp_squashfs_dir, "etc", "dracut.conf.d")
    os.makedirs(dracut_conf_dir, exist_ok=True)

    dracut_conf = os.path.join(dracut_conf_dir, "01-liveos.conf")

    dracut_config = """
    mdadmconf="no"
    lvmconf="no"
    squash_compress="xz"
    add_dracutmodules+=" livenet dmsquash-live dmsquash-live-ntfs convertfs pollcdrom qemu qemu-net "
    omit_dracutmodules+=" plymouth "
    hostonly="no"
    early_microcode="no"
    """

    try:
        with open(dracut_conf, "w") as file:
            file.write(dracut_config)
        logger.info(f"Dracut configuration created at {dracut_conf}")
    except Exception as e:
        logger.error(f"Failed to create dracut configuration: {str(e)}")
        return False

    return True
