import os
import json
import shlex
import subprocess
import re
from typing import Dict, List, Tuple, Optional

from flask import Flask, render_template, jsonify, request, abort

try:
    from dotenv import load_dotenv, dotenv_values
except Exception:
    # The app still runs without python-dotenv, but .env reading will be limited
    load_dotenv = None
    dotenv_values = None

# Resolve base app directory (expected WorkingDirectory in systemd unit)
BASE_DIR = os.path.abspath(os.getenv("COMFYUI_DASHBOARD_DIR", os.getcwd()))
ENV_PATH = os.path.join(BASE_DIR, ".env")

# Load .env if python-dotenv is available
if load_dotenv:
    load_dotenv(dotenv_path=ENV_PATH, override=False)

# Basic config
MASK_SECRETS = os.getenv("MASK_SECRETS", "true").lower() in ("1", "true", "yes", "on")
ACTION_TOKEN = None  # Disabled
SECRET_KEY = os.getenv("SECRET_KEY", "change-me-in-.env")

# Services to monitor/control: "user:comfyui.service,user:comfyui-dashboard.service"
SERVICES = os.getenv("SERVICES", "")

# Prefer explicit Miniconda path, fallback to PATH
MINICONDA_CONDA = os.path.expanduser(os.getenv("MINICONDA_CONDA", "~/miniconda3/bin/conda"))
if not os.path.isfile(MINICONDA_CONDA):
    MINICONDA_CONDA = "conda"

app = Flask(__name__, template_folder=os.path.join(BASE_DIR, "templates"), static_folder=os.path.join(BASE_DIR, "static"))
app.secret_key = SECRET_KEY


def run_cmd(args: List[str], timeout: int = 20, extra_env: Optional[Dict[str, str]] = None) -> Tuple[int, str, str]:
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    try:
        proc = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=timeout, text=True)
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except subprocess.TimeoutExpired as e:
        return 124, (e.stdout or "").strip(), (e.stderr or f"Command timed out after {timeout}s").strip()
    except FileNotFoundError as e:
        return 127, "", f"{e}"


def conda_cmd(args: List[str], timeout: int = 30) -> Tuple[int, str, str]:
    # Ensure TOS is auto-accepted for non-interactive usage if needed
    extra_env = {"CONDA_PLUGINS_AUTO_ACCEPT_TOS": "yes"}
    cmd = [MINICONDA_CONDA] + args
    return run_cmd(cmd, timeout=timeout, extra_env=extra_env)


def name_from_prefix(prefix: str) -> str:
    # Typical env prefix: ~/miniconda3/envs/<name>
    # Base env is usually ~/miniconda3 (no /envs/<name>)
    parts = prefix.rstrip("/").split("/")
    if "envs" in parts:
        idx = parts.index("envs")
        if idx + 1 < len(parts):
            return parts[idx + 1]
    # Fallback to last segment or 'base'
    return "base" if prefix.endswith(("miniconda3", "anaconda3")) else parts[-1]


def conda_envs() -> List[Dict[str, str]]:
    rc, out, err = conda_cmd(["env", "list", "--json"])
    envs: List[Dict[str, str]] = []
    if rc == 0:
        try:
            data = json.loads(out)
            for p in data.get("envs", []):
                envs.append({"name": name_from_prefix(p), "prefix": p})
        except Exception:
            # Fallback to text parsing if JSON parsing fails
            pass

    if not envs:
        # Fallback: parse plain text `conda env list`
        rc2, out2, _ = conda_cmd(["env", "list"])
        if rc2 == 0:
            for line in out2.splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                # Format: <name> *? <prefix>
                parts = line.split()
                if len(parts) >= 2:
                    # If second token is '*', then prefix is last token
                    if parts[1] == "*":
                        envs.append({"name": parts[0], "prefix": parts[-1]})
                    else:
                        envs.append({"name": parts[0], "prefix": parts[-1]})

    # Attach health probe (python -V)
    for e in envs:
        e["healthy"] = env_health(e["name"])
    return envs


def env_health(env_name: str) -> bool:
    rc, out, err = conda_cmd(["run", "-n", env_name, "python", "-V"], timeout=8)
    return rc == 0 and out.startswith("Python")


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


# Token protection removed for simplicity
def require_token():
    pass  # No check; allow all


@app.get("/")
def index():
    return render_template("index.html")


@app.get("/api/conda/envs")
def api_conda_envs():
    envs = conda_envs()
    return jsonify({"envs": envs})


@app.post("/api/conda/envs")
def api_create_conda_env():
    # require_token()  # Removed
    try:
        body = request.get_json(force=True)
    except Exception:
        body = {}
    name = (body.get("name") or "").strip()
    pyver = (body.get("python") or "3.11").strip()
    extra = body.get("packages", [])

    if not name or any(c in name for c in " /\\:"):
        return jsonify({"ok": False, "error": "Invalid environment name"}), 400

    args = ["create", "-n", name, f"python={pyver}", "-y"]
    if isinstance(extra, list) and extra:
        args.extend(extra)

    rc, out, err = conda_cmd(args, timeout=600)  # allow time for install
    ok = rc == 0
    return jsonify({"ok": ok, "returncode": rc, "stdout": out[-4000:], "stderr": err[-4000:]}), (200 if ok else 500)


@app.get("/api/services")
def api_services():
    items = parse_services_config()
    result = [service_status(it["scope"], it["name"]) for it in items]
    return jsonify({"services": result})


@app.post("/api/services/<scope>/<name>/<action>")
def api_service_action(scope: str, name: str, action: str):
    # require_token()  # Removed
    scope = scope.lower()
    if scope not in ("user", "system"):
        return jsonify({"ok": False, "error": "Invalid scope"}), 400
    if action not in ("start", "stop", "restart"):
        return jsonify({"ok": False, "error": "Invalid action"}), 400

    rc, out, err = systemctl_cmd(scope, [action, name], timeout=30)
    ok = rc == 0
    status = service_status(scope, name)
    return jsonify({"ok": ok, "returncode": rc, "stdout": out[-4000:], "stderr": err[-4000:], "status": status}), (200 if ok else 500)


@app.get("/api/envfile")
def api_envfile():
    # Best-effort parse .env, fall back to .env.example if missing
    kv = _parse_env_file(ENV_PATH)
    example_path = ENV_PATH.replace(".env", ".env.example")
    if not kv and os.path.exists(example_path):
        kv = _parse_env_file(example_path)

    if dotenv_values and kv:
        try:
            # Override with dotenv if available
            env_kv = dict(dotenv_values(ENV_PATH) or {})
            kv.update(env_kv)
        except Exception:
            pass

    masked = {}
    for k, v in kv.items():
        if not MASK_SECRETS:
            masked[k] = v
            continue
        if k.upper() in ("ACTION_TOKEN", "SECRET_KEY", "PASSWORD", "TOKEN", "API_KEY", "AUTH_TOKEN"):
            masked[k] = "••••••••"
        else:
            masked[k] = v
    return jsonify({"path": ENV_PATH, "values": masked, "masked": MASK_SECRETS})


def _parse_env_file(env_path: str = ENV_PATH) -> Dict[str, str]:
    kv: Dict[str, str] = {}
    try:
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if not line or line.lstrip().startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                kv[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
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


@app.post("/api/envfile")
def api_envfile_update():
    """
    Update selected keys in the .env file.
    Request JSON: { "updates": { "KEY": "VALUE", ... } }
    """
    # require_token()  # Removed
    try:
        body = request.get_json(force=True)
    except Exception:
        body = {}
    updates: Dict[str, str] = body.get("updates") or {}
    if not isinstance(updates, dict):
        return jsonify({"ok": False, "error": "Invalid payload"}), 400

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
            continue

        v = "" if raw_v is None else str(raw_v)

        # Special handling for MASK_SECRETS (boolean)
        if k == "MASK_SECRETS":
            v = norm_bool_str(v)

        # If client left masked placeholders (e.g., "••••••••") unchanged for secrets,
        # skip updating to avoid overwriting with literal bullets.
        if k in {"ACTION_TOKEN", "SECRET_KEY"} and v.strip() in ("", "••••••••"):
            continue

        # Detect restart requirement only if value changes
        old_v = current.get(k)
        if old_v is None:
            # also consider environment variable loaded via python-dotenv on process start
            old_v = os.getenv(k)
        if k in restart_sensitive and (old_v or "") != v:
            restart_required = True

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
                return jsonify({"ok": False, "error": f"Failed to init from example: {e}"}), 500
        if not applied:
            return jsonify({"ok": True, "updated": [], "restart_required": False, "path": ENV_PATH})

    # Write back
    tmp_path = ENV_PATH + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines).rstrip() + "\n")
    os.replace(tmp_path, ENV_PATH)

    return jsonify({"ok": True, "updated": applied, "restart_required": restart_required, "path": ENV_PATH})


if __name__ == "__main__":
    # Dev run only; in production we use Gunicorn
    host = os.getenv("BIND_HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "8080"))
    app.run(host=host, port=port, debug=False)
