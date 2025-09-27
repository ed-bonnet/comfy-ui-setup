import os
import sys
import subprocess
import logging
from typing import Dict, List, Tuple, Optional

from .config import MINICONDA_CONDA

def setup_logging():
    """Configure logging to work with Gunicorn"""
    # Get gunicorn logger
    gunicorn_logger = logging.getLogger('gunicorn.error')
    
    # Create or get your app logger
    logger = logging.getLogger(__name__)
    
    if gunicorn_logger.handlers:
        # Running under Gunicorn - use its handlers
        logger.handlers = gunicorn_logger.handlers[:]
        logger.setLevel(gunicorn_logger.level)
    else:
        # Running standalone - configure basic logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            stream=sys.stdout
        )
    
    return logger
logger = setup_logging()


def run_cmd(args: List[str], timeout: int = 20, extra_env: Optional[Dict[str, str]] = None) -> Tuple[int, str, str]:
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    try:
        logger.debug(f"Executing command: {' '.join(args)}")
        proc = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=timeout, text=True)
        logger.debug(f"Command completed with return code: {proc.returncode}")
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except subprocess.TimeoutExpired as e:
        logger.error(f"Command timed out: {' '.join(args)}")
        return 124, (e.stdout or "").strip(), (e.stderr or f"Command timed out after {timeout}s").strip()
    except FileNotFoundError as e:
        logger.error(f"Command not found: {' '.join(args)}")
        return 127, "", f"{e}"


def conda_cmd(args: List[str], timeout: int = 30) -> Tuple[int, str, str]:
    # Ensure TOS is auto-accepted for non-interactive usage if needed
    extra_env = {"CONDA_PLUGINS_AUTO_ACCEPT_TOS": "yes"}
    cmd = [MINICONDA_CONDA] + args
    return run_cmd(cmd, timeout=timeout, extra_env=extra_env)
