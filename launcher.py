"""
Multi-port launcher for the CAPTCHA solver.

Spawns one independent worker process per port (PORTS / PORT_START+PORT_COUNT
from .env). Each worker has its OWN camoufox browser + page pool, so:
  - a crash in one worker never affects the others
  - capacity scales horizontally (more ports = more concurrent solves)
  - crashed workers are auto-restarted

Usage:
    python launcher.py                 # uses PORTS from .env
    python launcher.py --host 0.0.0.0 --ports 5032,5033,5040-5042

Total capacity = len(PORTS) * THREAD * PAGE_COUNT  concurrent solves.
"""
import os
import sys
import time
import signal
import subprocess
import threading
from pathlib import Path

from utils.config import (
    HOST, PORTS, RESTART_ON_CRASH, RESTART_DELAY, WORKER_SPAWN_STAGGER,
)
from utils.logger import logger

BASE_DIR = Path(__file__).resolve().parent
MAIN_PY = str(BASE_DIR / "main.py")
PYTHON = sys.executable


class WorkerManager:
    def __init__(self, host, ports):
        self.host = host
        self.ports = list(ports)
        self.workers = {}          # port -> subprocess.Popen
        self._stopping = False
        self._lock = threading.Lock()

    def _spawn(self, port):
        env = os.environ.copy()
        env["WORKER_PORT"] = str(port)
        env["WORKER_ID"] = f"solver-{port}"
        cmd = [PYTHON, MAIN_PY, "--host", self.host, "--port", str(port)]
        logger.info(f"Spawning worker -> {self.host}:{port}")
        # Inherit stdio so worker logs flow into the launcher console.
        proc = subprocess.Popen(cmd, env=env)
        return proc

    def start(self):
        bar = "=" * 64
        logger.info(bar)
        logger.info(f"Launching {len(self.ports)} worker(s)")
        logger.info(f"Host  : {self.host}")
        logger.info(f"Ports : {self.ports[0]}..{self.ports[-1]}  ({len(self.ports)} port)")
        logger.info(f"Access: http://<VPS_IP>:{self.ports[0]}/health")
        logger.info(bar)
        for port in self.ports:
            self.workers[port] = self._spawn(port)
            # Stagger heavy browser startups to avoid RAM/CPU spikes.
            time.sleep(WORKER_SPAWN_STAGGER)
        logger.success("All workers launched. Monitoring (Ctrl+C to stop)...")

    def monitor(self):
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        try:
            while not self._stopping:
                time.sleep(3)
                with self._lock:
                    for port in list(self.workers.keys()):
                        proc = self.workers[port]
                        if proc.poll() is None:
                            continue
                        if self._stopping:
                            continue
                        logger.warning(f"Worker :{port} exited (code {proc.returncode})")
                        if RESTART_ON_CRASH:
                            logger.info(f"Restarting worker :{port} in {RESTART_DELAY}s ...")
                            time.sleep(RESTART_DELAY)
                            self.workers[port] = self._spawn(port)
                        else:
                            self.workers.pop(port, None)
        except KeyboardInterrupt:
            pass
        self.shutdown()

    def _signal_handler(self, signum, frame):
        logger.info(f"Received signal {signum}, stopping all workers ...")
        self._stopping = True

    def shutdown(self):
        with self._lock:
            if not self.workers:
                return
            logger.info("Terminating workers (SIGTERM) ...")
            for port, proc in self.workers.items():
                if proc.poll() is None:
                    try:
                        proc.terminate()
                    except Exception:
                        pass
            deadline = time.time() + 20
            for port, proc in self.workers.items():
                remaining = max(0.1, deadline - time.time())
                try:
                    proc.wait(timeout=remaining)
                    logger.success(f"Worker :{port} stopped cleanly")
                except subprocess.TimeoutExpired:
                    logger.warning(f"Worker :{port} did not stop, force killing")
                    try:
                        proc.kill()
                    except Exception:
                        pass
            self.workers.clear()
        logger.success("All workers stopped. Bye!")


def _parse_cli_ports(raw):
    out = []
    for part in raw.replace(" ", "").split(","):
        if not part:
            continue
        try:
            out.append(int(part))
        except ValueError:
            a, b = part.split("-")
            out.extend(range(int(a), int(b) + 1))
    return out


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Multi-port CAPTCHA solver launcher.")
    parser.add_argument("--host", default=HOST)
    parser.add_argument("--ports", default=None,
                        help="Override ports, e.g. 5032,5033 or 5032-5041")
    args = parser.parse_args()

    ports = _parse_cli_ports(args.ports) if args.ports else PORTS
    if not ports:
        logger.error("No ports configured. Set PORTS or PORT_START/PORT_COUNT in .env, "
                     "or pass --ports.")
        sys.exit(1)

    mgr = WorkerManager(args.host, ports)
    mgr.start()
    mgr.monitor()


if __name__ == "__main__":
    main()
