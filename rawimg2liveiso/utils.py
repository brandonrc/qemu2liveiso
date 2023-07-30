import subprocess
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def run_command(command):
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
    stdout, stderr = process.communicate()
    return process.returncode, stdout, stderr

def mkdir(directory):
    os.makedirs(directory, exist_ok=True)

def create_temp_dir():
    return tempfile.mkdtemp()

def copy(src, dst):
    return run_command(f"cp {src} {dst}")

def extract_tar_xz(tar_file_path, extract_path):
    return run_command(f"tar -xf {tar_file_path} -C {extract_path}")
