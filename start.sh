#!/usr/bin/env bash
# Start the multi-port CAPTCHA solver launcher in foreground.
set -euo pipefail
cd "$(dirname "$0")"
exec python3 launcher.py "$@"
