import os
from pathlib import Path
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")


def _split_ints(raw, default):
    """Parse '5032,5033' or '5032-5036' into a list of ints."""
    if not raw:
        return default
    out = []
    for part in raw.replace(" ", "").split(","):
        if part == "":
            continue
        try:
            out.append(int(part))
        except ValueError:
            try:
                a, b = part.split("-")
                out.extend(range(int(a), int(b) + 1))
            except Exception:
                continue
    return out or default


# ---------------------------------------------------------------------------
# Network / multi-port
# ---------------------------------------------------------------------------
HOST = os.getenv("HOST", "0.0.0.0")          # 0.0.0.0 => accessible from outside (VPS)
PORT = int(os.getenv("PORT", "5032"))         # single-port fallback
WORKER_PORT = int(os.getenv("WORKER_PORT", str(PORT)))  # per-worker override

# Multi-port launcher (launcher.py) port set.
# Priority: explicit PORTS list/range > PORT_START+PORT_COUNT > single PORT.
PORTS = _split_ints(os.getenv("PORTS", ""), [])
if not PORTS:
    PORT_START = int(os.getenv("PORT_START", str(PORT)))
    PORT_COUNT = int(os.getenv("PORT_COUNT", "1"))
    PORTS = list(range(PORT_START, PORT_START + PORT_COUNT))

# ---------------------------------------------------------------------------
# Browser pool (per worker / per port)
#   max concurrent solves per port = THREAD x PAGE_COUNT
# ---------------------------------------------------------------------------
HEADLESS = os.getenv("HEADLESS", "true").lower() == "true"
THREAD = int(os.getenv("THREAD", "1"))
PAGE_COUNT = int(os.getenv("PAGE_COUNT", "1"))
PROXY_SUPPORT = os.getenv("PROXY_SUPPORT", "false").lower() == "true"

# ---------------------------------------------------------------------------
# Uvicorn tuning (brutal concurrency, per port)
# ---------------------------------------------------------------------------
UVICORN_WORKERS = int(os.getenv("UVICORN_WORKERS", "1"))   # keep 1 (pool is in-process)
LIMIT_CONCURRENCY = int(os.getenv("LIMIT_CONCURRENCY", "5000"))
BACKLOG = int(os.getenv("BACKLOG", "8192"))
TIMEOUT_KEEP_ALIVE = int(os.getenv("TIMEOUT_KEEP_ALIVE", "30"))
ACCESS_LOG = os.getenv("ACCESS_LOG", "false").lower() == "true"

# ---------------------------------------------------------------------------
# Worker manager (launcher.py)
# ---------------------------------------------------------------------------
RESTART_ON_CRASH = os.getenv("RESTART_ON_CRASH", "true").lower() == "true"
RESTART_DELAY = float(os.getenv("RESTART_DELAY", "3"))
WORKER_SPAWN_STAGGER = float(os.getenv("WORKER_SPAWN_STAGGER", "1.5"))

# ---------------------------------------------------------------------------
# Cleanup / logging
# ---------------------------------------------------------------------------
CLEANUP_INTERVAL_MINUTES = int(os.getenv("CLEANUP_INTERVAL_MINUTES", "60"))
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
LOG_ROTATION = os.getenv("LOG_ROTATION", "10 MB")
LOG_RETENTION = os.getenv("LOG_RETENTION", "7 days")

STATIC_DIR = BASE_DIR / "static"
LOGS_DIR = BASE_DIR / "logs"
