import logging
import os
import sys
from flask import Flask, render_template, jsonify, request

# Add the current directory to Python path for proper imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core.config import BASE_DIR, SECRET_KEY
from core.conda_manager import get_conda_envs, get_available_python_versions
from core.service_manager import get_services, control_service
from core.env_file_handler import get_env_file, update_env_file
from core.comfyui_setup import setup_comfyui_environment

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
print("DEBUG: App starting", file=sys.stderr)
logger.info("TEST - App logger initialized")


app = Flask(__name__, template_folder=os.path.join(BASE_DIR, "templates"), static_folder=os.path.join(BASE_DIR, "static"))

# Configure Flask app to use the same logger
if __name__ != '__main__':
    # Running under Gunicorn
    gunicorn_logger = logging.getLogger('gunicorn.error')
    app.logger.handlers = gunicorn_logger.handlers
    app.logger.setLevel(gunicorn_logger.level)

app.secret_key = SECRET_KEY
logger.info("TEST - App logger initialized")
logger.error("TEST - App logger initialized")
print("DEBUG: App starting", file=sys.stderr)


@app.get("/")
def index():
    logger.debug("Serving index page")
    return render_template("index.html")


@app.get("/api/conda/envs")
def api_conda_envs():
    logger.debug("Getting conda environments")
    result = get_conda_envs()
    logger.debug(f"Returning {len(result.get('envs', []))} environments")
    return jsonify(result)

@app.get("/api/conda/python-versions")
def api_python_versions():
    logger.debug("Getting available Python versions")
    versions = get_available_python_versions()
    logger.debug(f"Returning {len(versions)} Python versions")
    return jsonify(versions)


@app.post("/api/conda/envs")
def api_create_conda_env():
    logger.debug("Creating new conda environment")
    try:
        body = request.get_json(force=True)
    except Exception:
        body = {}
    
    name = (body.get("name") or "").strip()
    pyver = (body.get("python") or "3.11").strip()
    
    logger.debug(f"Creating environment: {name}, Python version: {pyver}")
    result = setup_comfyui_environment(name, pyver)
    
    if result.get("ok"):
        logger.debug(f"Environment {name} created successfully")
        return jsonify(result), 200
    else:
        logger.error(f"Failed to create environment {name}: {result.get('error')}")
        return jsonify(result), 400


@app.get("/api/services")
def api_services():
    logger.debug("Getting services")
    result = get_services()
    logger.debug(f"Returning {len(result.get('services', []))} services")
    return jsonify(result)


@app.post("/api/services/<scope>/<name>/<action>")
def api_service_action(scope: str, name: str, action: str):
    logger.debug(f"Controlling service: {scope}/{name} with action: {action}")
    result = control_service(scope, name, action)
    
    if result.get("ok"):
        logger.debug(f"Service action successful: {scope}/{name}/{action}")
        return jsonify(result), 200
    else:
        logger.error(f"Service action failed: {scope}/{name}/{action} - {result.get('error')}")
        return jsonify(result), 500


@app.get("/api/envfile")
def api_envfile():
    logger.debug("Getting env file")
    result = get_env_file()
    logger.debug(f"Returning env file with {len(result.get('values', {}))} values")
    return jsonify(result)


@app.post("/api/envfile")
def api_envfile_update():
    logger.debug("Updating env file")
    try:
        body = request.get_json(force=True)
    except Exception:
        body = {}
    
    updates = body.get("updates") or {}
    logger.debug(f"Received {len(updates)} updates")
    if not isinstance(updates, dict):
        logger.error("Invalid payload: updates is not a dict")
        return jsonify({"ok": False, "error": "Invalid payload"}), 400
    
    result = update_env_file(updates)
    
    if result.get("ok"):
        logger.debug(f"Env file updated successfully, {len(result.get('updated', []))} keys applied")
        return jsonify(result), 200
    else:
        logger.error(f"Failed to update env file: {result.get('error')}")
        return jsonify(result), 500


if __name__ == "__main__":
    # Dev run only; in production we use Gunicorn
    host = os.getenv("BIND_HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "8080"))
    app.run(host=host, port=port, debug=False)
