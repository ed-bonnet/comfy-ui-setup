import logging
from typing import Dict, List, Tuple

from .command_utils import run_cmd
from .config import SERVICES

# Set up logging
logger = logging.getLogger(__name__)


def parse_services_config() -> List[Dict[str, str]]:
    entries = []
    raw = SERVICES.strip()
    if not raw:
        return entries
    for item in raw.split(","):
        item = item.strip()
        if not item:
            continue
        # Allow "user:name" or "system:name". Default to "user" if scope omitted.
        scope = "user"
        name = item
        if ":" in item:
            scope, name = item.split(":", 1)
            scope = scope.strip() or "user"
            name = name.strip()
        entries.append({"scope": scope, "name": name})
    return entries


def systemctl_cmd(scope: str, args: List[str], timeout: int = 15) -> Tuple[int, str, str]:
    base = ["systemctl"]
    if scope == "user":
        base.append("--user")
    return run_cmd(base + args, timeout=timeout)


def service_status(scope: str, name: str) -> Dict[str, str]:
    rc, out, err = systemctl_cmd(scope, ["is-active", name])
    status = out if rc == 0 else (out or err or "unknown")
    return {"scope": scope, "name": name, "status": status}


def get_services() -> Dict:
    """API-ready function for listing services"""
    logger.debug("Getting services")
    items = parse_services_config()
    logger.debug(f"Found {len(items)} services in config")
    result = [service_status(it["scope"], it["name"]) for it in items]
    logger.debug(f"Returning status for {len(result)} services")
    return {"services": result}


def control_service(scope: str, name: str, action: str) -> Dict:
    """API-ready function for controlling services"""
    logger.debug(f"Controlling service: {scope}/{name} with action: {action}")
    if scope not in ("user", "system"):
        logger.error(f"Invalid scope: {scope}")
        return {"ok": False, "error": "Invalid scope"}
    if action not in ("start", "stop", "restart"):
        logger.error(f"Invalid action: {action}")
        return {"ok": False, "error": "Invalid action"}

    rc, out, err = systemctl_cmd(scope, [action, name], timeout=30)
    ok = rc == 0
    status = service_status(scope, name)
    logger.debug(f"Service control result: ok={ok}, returncode={rc}")
    return {
        "ok": ok, 
        "returncode": rc, 
        "stdout": out[-4000:], 
        "stderr": err[-4000:], 
        "status": status
    }
