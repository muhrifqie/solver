import argparse
import asyncio
import os
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
import uvicorn
from utils.config import (
    HOST, PORT, HEADLESS, THREAD, PAGE_COUNT, PROXY_SUPPORT, STATIC_DIR,
    LIMIT_CONCURRENCY, BACKLOG, TIMEOUT_KEEP_ALIVE, ACCESS_LOG,
)
from utils.logger import logger
from utils.browser import (
    initialize_browser, cleanup_results_loop, periodic_cleanup_loop,
    create_context_with_proxy,
)
from utils.routes import register_routes


class CaptchaSolverServer:
    def __init__(self, headless, thread, page_count, proxy_support):
        self.headless = headless
        self.thread_count = thread
        self.page_count = page_count
        self.proxy_support = proxy_support
        self.page_pool = asyncio.Queue()
        self.camoufox = None
        self.browser = None
        self.results = {}
        self.proxies = []
        self.max_task_num = self.thread_count * self.page_count
        self.current_task_num = 0

        STATIC_DIR.mkdir(parents=True, exist_ok=True)

        @asynccontextmanager
        async def lifespan(app):
            await self._startup()
            yield
            await self._shutdown()

        self.app = FastAPI(lifespan=lifespan)
        self.app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

        register_routes(self.app, self)

    def decrement_task(self):
        if self.current_task_num > 0:
            self.current_task_num -= 1

    async def _startup(self):
        logger.info("Start initializing the browser")
        try:
            self.camoufox, self.browser = await initialize_browser(
                self.headless, self.thread_count, self.page_count, self.page_pool
            )
            asyncio.create_task(cleanup_results_loop(self.results))
            asyncio.create_task(periodic_cleanup_loop(
                self.page_pool,
                self.max_task_num,
                lambda: create_context_with_proxy(self.browser)
            ))
        except Exception as e:
            logger.error(f"Browser initialization failed: {str(e)}")
            raise

    async def _shutdown(self):
        logger.info("Start cleaning browser resources")
        try:
            if self.browser:
                await self.browser.close()
        except Exception as e:
            logger.warning(f"Exception when closing the browser: {e}")
        logger.success("All browser resources have been cleaned")


def create_app():
    server = CaptchaSolverServer(
        headless=HEADLESS,
        thread=THREAD,
        page_count=PAGE_COUNT,
        proxy_support=PROXY_SUPPORT
    )
    return server.app


# Module-level app (used by `uvicorn main:app` and import-based launchers).
app = create_app()


def _resolve_port(cli_port):
    if cli_port is not None:
        return cli_port
    wp = os.getenv("WORKER_PORT")
    if wp:
        return int(wp)
    return PORT


def run_single_worker(host=None, port=None):
    """Run one FastAPI+uvicorn worker bound to (host, port). Tuned for high concurrency."""
    host = host or HOST
    port = _resolve_port(port)
    logger.info(
        f"Starting solver worker on {host}:{port} "
        f"| pool={THREAD * PAGE_COUNT} ({THREAD} thread x {PAGE_COUNT} pages) "
        f"| limit_concurrency={LIMIT_CONCURRENCY} backlog={BACKLOG}"
    )
    uvicorn.run(
        app,
        host=host,
        port=port,
        workers=1,
        log_level="info",
        access_log=ACCESS_LOG,
        timeout_keep_alive=TIMEOUT_KEEP_ALIVE,
        limit_concurrency=LIMIT_CONCURRENCY,
        backlog=BACKLOG,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run a single CAPTCHA solver worker.")
    parser.add_argument("--host", default=HOST, help="Bind host (default from .env)")
    parser.add_argument("--port", type=int, default=None, help="Bind port (default WORKER_PORT/PORT)")
    args = parser.parse_args()
    run_single_worker(host=args.host, port=args.port)
