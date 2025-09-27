import logging
import os
import re
from typing import Dict, List

try:
    from dotenv import load_dotenv, dotenv_values
except Exception:
    # The app still runs without python-dotenv, but .env reading will be limited
    load_dotenv = None
    dotenv_values = None

from .config import ENV_PATH, MASK_SECRETS

# Set up logging
logger = logging.getLogger(__name__)


def _parse_env_file(env_path: str = ENV_PATH) -> Dict[str, str]:
    kv: Dict[str, str] = {}
    try:
        logger.debug(f"Parsing env file: {env_path}")
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if not line or line.lstrip().startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                kv[k.strip()] = v.strip()
        logger.debug(f"Found {len(kv)} key-value pairs in env file")
    except FileNotFoundError:
        logger.debug(f"Env file not found: {env_path}")
        pass
    except Exception as e:
        logger.error(f"Error parsing env file {env_path}: {str(e)}")
    return kv


def _needs_quotes(val: str) -> bool:
    # Quote if contains spaces or characters outside this safe set
    # Allowed unquoted: A-Za-z0-9 _ . - / :
    return not re.fullmatch(r"[A-Za-z0-9_\.\-/:]*", val or "")


def _serialize_val(val: str) -> str:
    if val is None:
        val = ""
    if _needs_quotes(val):
        # Escape backslashes and quotes inside a quoted value
        esc = val.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{esc}"'
    return val


def get_env_file() -> Dict:
    """API-ready function for reading the .env file"""
    logger.debug("Getting env file")
    # Best-effort parse .env, fall back to .env.example if missing
    kv = _parse_env_file(ENV_PATH)
    example_path = ENV_PATH.replace(".env", ".env.example")
    if not kv and os.path.exists(example_path):
        logger.debug("Falling back to .env.example")
        kv = _parse_env_file(example_path)

    if dotenv_values and kv:
        try:
            # Override with dotenv if available
            env_kv = dict(dotenv_values(ENV_PATH) or {})
            kv.update(env_kv)
            logger.debug("Updated with dotenv values")
        except Exception as e:
            logger.error(f"Error loading dotenv values: {str(e)}")

    masked = {}
    for k, v in kv.items():
        if not MASK_SECRETS:
            masked[k] = v
            continue
        if k.upper() in ("ACTION_TOKEN", "SECRET_KEY", "PASSWORD", "TOKEN", "API_KEY", "AUTH_TOKEN"):
            masked[k] = "••••••••"
        else:
            masked[k] = v
    logger.debug(f"Returning {len(masked)} env values")
    return {"path": ENV_PATH, "values": masked, "masked": MASK_SECRETS}


def update_env_file(updates: Dict[str, str]) -> Dict:
    """API-ready function for updating the .env file"""
    logger.debug(f"Updating env file with {len(updates)} updates")
    # Whitelist keys to prevent dangerous edits
    editable_keys = {
        "PORT",
        "BIND_HOST",
        "SERVICES",
        "MASK_SECRETS",
        "ACTION_TOKEN",
        "SECRET_KEY",
        "MINICONDA_CONDA",
        "COMFYUI_DASHBOARD_DIR",
        "models_location",
    }

    # Normalize boolean-like values
    def norm_bool_str(v: str) -> str:
        return "true" if str(v).strip().lower() in ("1", "true", "yes", "on") else "false"

    # Load current values
    current = _parse_env_file()
    restart_sensitive = {"PORT", "BIND_HOST"}
    restart_required = False

    # Prepare new content lines
    # Read original lines to preserve comments/order where possible
    lines: List[str] = []
    example_path = ENV_PATH.replace(".env", ".env.example")
    if os.path.exists(ENV_PATH):
        try:
            with open(ENV_PATH, "r", encoding="utf-8") as f:
                lines = f.read().splitlines()
        except Exception:
            lines = []
    elif os.path.exists(example_path):
        try:
            with open(example_path, "r", encoding="utf-8") as f:
                lines = f.read().splitlines()
            # Ensure file will be created on write
        except Exception:
            lines = []
    else:
        lines = []

    # Build index of existing keys
    key_index: Dict[str, int] = {}
    for idx, line in enumerate(lines):
        if not line or line.lstrip().startswith("#") or "=" not in line:
            continue
        k, _ = line.split("=", 1)
        key_index[k.strip()] = idx

    applied: List[str] = []
    for raw_k, raw_v in updates.items():
        k = str(raw_k).strip()
        if k not in editable_keys:
            logger.debug(f"Skipping non-editable key: {k}")
            continue

        v = "" if raw_v is None else str(raw_v)

        # Special handling for MASK_SECRETS (boolean)
        if k == "MASK_SECRETS":
            v = norm_bool_str(v)

        # If client left masked placeholders (e.g., "••••••••") unchanged for secrets,
        # skip updating to avoid overwriting with literal bullets.
        if k in {"ACTION_TOKEN", "SECRET_KEY"} and v.strip() in ("", "••••••••"):
            logger.debug(f"Skipping masked key: {k}")
            continue

        # Detect restart requirement only if value changes
        old_v = current.get(k)
        if old_v is None:
            # also consider environment variable loaded via python-dotenv on process start
            old_v = os.getenv(k)
        if k in restart_sensitive and (old_v or "") != v:
            restart_required = True
            logger.debug(f"Restart required due to change in {k}")

        new_line = f"{k}={_serialize_val(v)}"
        if k in key_index:
            lines[key_index[k]] = new_line
        else:
            lines.append(new_line)
        applied.append(k)

    # If nothing to apply but file didn't exist, create minimal from example or empty
    if not applied:
        if not os.path.exists(ENV_PATH) and os.path.exists(example_path):
            try:
                with open(example_path, "r", encoding="utf-8") as f:
                    content = f.read().rstrip() + "\n"
                with open(ENV_PATH, "w", encoding="utf-8") as f:
                    f.write(content)
                applied = list(_parse_env_file(ENV_PATH).keys())
            except Exception as e:
                logger.error(f"Failed to init from example: {e}")
                return {"ok": False, "error": f"Failed to init from example: {e}"}
        if not applied:
            logger.debug("No updates applied")
            return {"ok": True, "updated": [], "restart_required": False, "path": ENV_PATH}

    # Write back
    tmp_path = ENV_PATH + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines).rstrip() + "\n")
    os.replace(tmp_path, ENV_PATH)
    logger.debug(f"Env file updated successfully, {len(applied)} keys applied")

    return {"ok": True, "updated": applied, "restart_required": restart_required, "path": ENV_PATH}
