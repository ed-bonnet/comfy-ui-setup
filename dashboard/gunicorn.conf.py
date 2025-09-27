# gunicorn.conf.py
bind = "0.0.0.0:8080"
workers = 2
worker_class = "sync"
timeout = 300 # 5 minutes
keepalive = 5

# Logging configuration
accesslog = "-"  # Log to stdout
errorlog = "-"   # Log to stderr
loglevel = "info"
capture_output = True  # Capture print statements

# Format logs for better readability
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)s'