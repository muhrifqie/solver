<img width="1919" height="1079" alt="Image" src="https://github.com/user-attachments/assets/6f9ac168-00c4-41e2-9dd2-284c0de9dfbb" />

CAPTCHA solver (Cloudflare Turnstile, reCAPTCHA v2/v2-invisible/v2-enterprise, reCAPTCHA v3/v3-enterprise) powered by FastAPI + camoufox. Now with **multi-port** + **brutal concurrency** support for VPS.

---

### Quick start (local / single port)

1. Download ZIP <a href="https://codeload.github.com/agathasangkara/solver/zip/refs/heads/main">here</a> and extract the ZIP
2. Open CMD in folder `solver`, run `pip install -r requirements.txt`
3. Install camoufox: `camoufox download`
4. Edit `.env` and setup your configuration
5. Run `python main.py`
6. Run `python tes.py` for testing

---

### Windows VPS — one-command dev environment (PowerShell)

`install.ps1` is a **general-purpose** developer setup script (not tied to this project). It installs only the dev tools / frameworks you pick: Git, Python, Node.js, Go, Rust, Docker, **nginx**, **Caddy**, **cloudflared**, Redis, PostgreSQL, VS Code, plus CLI utils (jq, make, vim, openssl, 7zip, wget) and PowerShell 7 + Windows Terminal.

Open **PowerShell as Administrator** on a fresh Windows VPS and paste:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
iwr -UseBasicParsing https://raw.githubusercontent.com/muhrifqie/solver/main/install.ps1 | iex
```

That installs the **Core** set (Git + Python + Node.js) by default. To choose more, save the file and run with switches:

```powershell
& .\install.ps1 -Core -Web -Tunnel -Utils      # categories
& .\install.ps1 -All                            # install everything
& .\install.ps1 -Tools go,rust,nginx            # individual tools
& .\install.ps1 -OpenPorts 80,443,8080          # open firewall ports
& .\install.ps1 -SetupProfile                   # ll/which/touch/grep/Get-PublicIP/Open-Port
& .\install.ps1 -List                           # show the full tool catalog
```

Categories: `Core` (git,python,node) · `Lang` (go,rust) · `Container` (docker) · `Web` (nginx,caddy) · `Tunnel` (cloudflared) · `DB` (redis,postgres) · `Editor` (vscode) · `Utils` (jq,make,vim,openssl,7zip,wget) · `Shell` (pwsh,windows-terminal).

Notes:
- Uses **winget** first, auto-falls back to **Chocolatey** if a tool isn't found.
- Idempotent: skips tools already installed (use `-Force` to reinstall).
- Auto re-launches elevated if you forget "Run as Administrator".
- After install, **open a new terminal** so PATH refreshes.

Quick tunnel to expose any local port to the internet (after installing cloudflared):
```powershell
cloudflared tunnel --url http://localhost:8080
```

---

### Multi-port + brutal concurrency (VPS)

Each port runs **its own** browser + page pool as an independent process, so:
- a crash on one port never affects the others,
- capacity scales horizontally = `len(PORTS) * THREAD * PAGE_COUNT` concurrent solves,
- crashed workers are auto-restarted.

**Total concurrent capacity example:** `PORTS=5032-5036` (5 ports) × `THREAD=2` × `PAGE_COUNT=10` = **100 concurrent solves**. Tune to your VPS CPU/RAM.

#### 1) Configure `.env`

```env
HOST=0.0.0.0                 # bind all interfaces => accessible from outside
# Pick ONE way to define ports:
PORTS=5032-5036             # range 5032..5036 (5 ports)   <-- recommended
# or:
# PORT_START=5032
# PORT_COUNT=5

THREAD=2                     # browser contexts per port
PAGE_COUNT=10                # pages per context per port
HEADLESS=True
```

Tuning knobs (per port):

```env
LIMIT_CONCURRENCY=5000
BACKLOG=8192
TIMEOUT_KEEP_ALIVE=30
ACCESS_LOG=false
```

#### 2) Install & run on the VPS

```bash
git clone <your-repo> /opt/solver
cd /opt/solver
pip install -r requirements.txt
camoufox download
# (optional, Linux only) extra perf: pip install uvloop httptools

# open the firewall ports (UFW/firewalld/iptables auto-detected from .env):
sudo bash open_ports.sh

# start in foreground (Ctrl+C to stop):
bash start.sh
```

Each port is reachable as:

```
http://<VPS_IP>:5032/health
http://<VPS_IP>:5033/health
...
```

#### 3) Run as a service (systemd, auto-start on boot)

```bash
sudo cp solver.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now solver
sudo systemctl status solver
# live logs:
sudo journalctl -u solver -f
tail -f /var/log/solver-launcher.log
```

#### 4) Verify from your local machine

```bash
curl http://<VPS_IP>:5032/health
```

```json
{"status":"ok","max_concurrent":20,"in_progress":0,"free_slots":20,"pool_ready":20}
```

---

### Endpoints (every port)

| Method | Path | Description |
|---|---|---|
| GET | `/` | Service info + capacity |
| GET | `/health` | Live capacity (max/in-progress/free/pool) |
| GET | `/turnstile` | Solve Turnstile (`url`, `sitekey`, `action?`, `cdata?`) |
| GET | `/recaptchav2` | Solve reCAPTCHA v2 (`url`, `sitekey`) |
| GET | `/recaptchav2invisible` | Solve reCAPTCHA v2 invisible |
| GET | `/recaptchav2enterprise` | Solve reCAPTCHA v2 enterprise |
| GET | `/recaptchav3` | Solve reCAPTCHA v3 (`url`, `sitekey`, `action`, `min_score`) |
| GET | `/recaptchav3enterprise` | Solve reCAPTCHA v3 enterprise |
| GET | `/result?id=<task_id>` | Get task result |

Usage pattern (every port is identical):

```
1) POST task : GET /turnstile?url=...&sitekey=...   -> { "task_id": "..." }
2) poll      : GET /result?id=<task_id>             -> { "status":"success", "value":"<token>" }
```

---

### Running a single custom port manually

```bash
python main.py --host 0.0.0.0 --port 7000
```

---

### Scaling tips

- **More throughput** → add ports (`PORTS=5032-5051`) or raise `THREAD`/`PAGE_COUNT`.
- **Stability** → keep per-port pool moderate (e.g. 10–25) and scale via ports rather than one giant browser.
- **RAM rule of thumb** → each browser context/page uses memory; watch `htop` and tune.
- **Firewall / cloud** → also open the same TCP ports in your provider's security group (AWS/Azure/GCP/DigitalOcean panel) — `open_ports.sh` only handles the OS firewall.

--------------------------------------

### Please note

This script was made for educational purposes, I am not responsible for your actions using this script. This script was made for educational purposes.
