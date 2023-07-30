from utils import run_command
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def create_iso(iso_output_dir, main_tmp_dir):
    cmd = f"grub2-mkrescue -o {iso_output_dir}/live.iso {main_tmp_dir}"
    return run_command(cmd)
