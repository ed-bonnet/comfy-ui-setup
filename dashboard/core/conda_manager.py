import subprocess
import os
import json
import sys
import logging
from typing import List, Dict

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

def get_conda_envs() -> Dict:
    """Get all conda environments"""
    logger.debug("Getting conda environments")
    try:
        result = subprocess.run(
            ["conda", "env", "list", "--json"],
            capture_output=True,
            text=True,
            check=True
        )
        data = json.loads(result.stdout)

        envs = []
        for path in data.get("envs", []):
            name = os.path.basename(path)
            if name.startswith("comfyui-instance-"):
                envs.append(name)
            # name = os.path.basename(prefix)
            # healthy = os.path.exists(os.path.join(prefix, "bin", "python"))
            # envs.append({"name": name, "prefix": prefix, "healthy": healthy})
        logger.debug(f"Found {len(envs)} conda environments: {envs}")
        return {"ok": True, "envs": envs}
    except Exception as e:
        logger.error(f"Error getting conda environments: {str(e)}")
        return {"ok": False, "error": str(e)}

def get_available_python_versions(min_version: str = "3.11") -> List[str]:
    """Get available Python versions from Conda that are >= min_version"""
    logger.debug(f"Getting available Python versions (min: {min_version})")
    try:
        # Get all available packages
        result = subprocess.run(
            ["conda", "search", "--json", "--platform", "linux-64", "python"],
            capture_output=True,
            text=True,
            check=True
        )
        data = json.loads(result.stdout)

        # Check if "python" key exists in the data
        if "python" not in data:
            logger.debug("No python key found in conda search results")
            return []

        logger.debug(f"Found {len(data['python'])} python packages")
        # Filter and extract versions
        versions = []
        for pkg in data["python"]:
            version = pkg["version"]
            # Properly compare version strings
            if _version_greater_equal(version, min_version):
                versions.append(version)

        # Remove duplicates and sort
        versions = sorted(list(set(versions)), reverse=True, key=_version_key)
        logger.debug(f"Returning {len(versions)} Python versions >= {min_version}")
        return versions
    except Exception as e:
        logger.error(f"Error getting Python versions: {str(e)}")
        return []

def _version_key(version: str) -> List[int]:
    """Convert version string to list of integers for sorting"""
    return [int(x) for x in version.split('.')]

def _version_greater_equal(version: str, min_version: str) -> bool:
    """Compare version strings properly"""
    version_parts = [int(x) for x in version.split('.')]
    min_version_parts = [int(x) for x in min_version.split('.')]
    
    # Pad shorter version with zeros
    while len(version_parts) < len(min_version_parts):
        version_parts.append(0)
    while len(min_version_parts) < len(version_parts):
        min_version_parts.append(0)
    
    # Compare each part
    for v, m in zip(version_parts, min_version_parts):
        if v > m:
            return True
        if v < m:
            return False
    return True  # Equal versions

def conda_envs() -> List[Dict]:
    """Helper function to get conda environments"""
    result = get_conda_envs()
    return result.get("envs", []) if result.get("ok") else []

def create_conda_env(name: str, python_version: str) -> Dict:
    """Create a new conda environment"""
    try:
        logger.info(f"Creating conda environment: {name} with Python {python_version}")
        result = subprocess.run(
            ["conda", "create", "-n", name, f"python={python_version}", "-y"],
            capture_output=True,
            text=True,
            check=True
        )

        logger.debug("STDOUT:", result.stdout)
        logger.debug("STDERR:", result.stderr)
        logger.debug("Return code:", result.returncode)
        return {"ok": True, "message": f"Environment {name} created successfully"}
    except subprocess.CalledProcessError as e:
        logger.error("Command failed:")
        logger.error("STDOUT:", e.stdout)
        logger.error("STDERR:", e.stderr)
        logger.error("Return code:", e.returncode)
        return {"ok": False, "error": f"Failed !! to create environment: {str(e)}"}
    except Exception as e:
        logger.error("JSON parsing failed:", e)
        logger.error("Raw stdout:", repr(result.stdout))
