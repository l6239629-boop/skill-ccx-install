---
name: "ccx-install"
description: "Install CCX AI API proxy gateway on macOS from GitHub (BenedictKing/ccx). Clones the repo, downloads the latest prebuilt binary, configures access password and port, sets up launch-on-boot via LaunchAgent, and verifies the service is running. Use when the user wants to set up CCX for the first time, reinstall, or troubleshoot an existing installation."
---

# CCX Install

## Overview

CCX is a high-performance AI API proxy and protocol translation gateway for Claude, OpenAI Chat, OpenAI Images, Codex Responses, and Gemini.

This skill automates the full installation on macOS:
1. Clone or update the CCX repository from GitHub
2. Download the latest prebuilt binary for your Mac architecture (arm64 / amd64)
3. Configure `.env` with your access password and preferred port
4. Set up a macOS LaunchAgent for auto-start on boot + crash recovery
5. Start the service and verify it is running

After installation, open `http://localhost:3688` in your browser and enter the access password to manage channels.

## Prerequisites

- macOS (Apple Silicon or Intel)
- Git installed (`git --version`)
- Internet connection to access GitHub

Go is **not required** — this skill downloads prebuilt binaries from GitHub Releases.

## Quick Workflow

```bash
# 1. Run the install script (follow prompts for install directory)
bash "<path-to-skill>/scripts/install_ccx.sh"

# 2. Open browser
open http://localhost:3688

# 3. Enter access password (default: 123456)
```

## Step-by-Step Installation Guide

### Step 1: Choose Install Directory

The script will ask where to install CCX. Default is `~/Desktop/ccx`.

- If the directory already has a CCX installation, the script will detect it and offer to update or reinstall.
- If you want a fresh install, choose a new directory or let the script overwrite after backup.

### Step 2: Clone Repository

The script clones `https://github.com/BenedictKing/ccx` into your chosen directory.

- If the repo already exists, it pulls the latest changes via `git pull`.
- Configuration files (`.env`, `.config/`) are preserved and backed up before any changes.

### Step 3: Download Binary

The script detects your macOS architecture:
- **Apple Silicon (M1/M2/M3/M4)** → downloads `ccx-darwin-arm64`
- **Intel Mac** → downloads `ccx-darwin-amd64`

It fetches the latest release from GitHub Releases and extracts the binary into `backend-go/ccx`.

### Step 4: Configure Environment

The script creates `backend-go/.env` with optimized defaults:

```bash
PORT=3688                          # Web UI + API port
ENV=production                     # Production mode
ENABLE_WEB_UI=true                 # Enable management UI
APP_UI_LANGUAGE=zh-CN              # Chinese UI
PROXY_ACCESS_KEY=123456            # Access password (change this!)
LOG_LEVEL=info                     # Log level
ENABLE_REQUEST_LOGS=false          # Disable request logging
ENABLE_RESPONSE_LOGS=false         # Disable response logging
REQUEST_TIMEOUT=300000             # 5 min request timeout
```

You will be prompted to set a custom access password. The default is `123456`.

### Step 5: Set Up Auto-Start (LaunchAgent)

The script creates `~/Library/LaunchAgents/com.ccx.proxy.plist` with:

- **RunAtLoad=true** — starts CCX automatically when you log in
- **KeepAlive=true** — restarts CCX if it crashes
- **WorkingDirectory** — set to the `backend-go` directory

Then loads the service with `launchctl load`.

### Step 6: Start and Verify

The script starts CCX and verifies:

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:3688/
# Expected: 200
```

### Step 7: Open Management UI

Open your browser and go to **http://localhost:3688**

Enter the access password you set (default: `123456`).

## Safety Rules

- **Never overwrite existing `.env` without backup.** The script creates a timestamped backup before making changes.
- **Never overwrite existing `.config/` channel data.** Channel configurations are preserved across reinstalls.
- **Never delete the repository directory.** If a reinstall is needed, the script backs up configs and pulls fresh code.
- **Preserve existing LaunchAgent.** If `com.ccx.proxy.plist` already exists, the script unloads it before updating.
- **Always verify after install.** The script must confirm HTTP 200 before reporting success.
- **Prefer prebuilt binaries over source builds.** Only fall back to `make build` if the download fails.

## Common Tasks

### Start CCX

```bash
launchctl start com.ccx.proxy
```

### Stop CCX

```bash
launchctl stop com.ccx.proxy
```

### Check if CCX is Running

```bash
# Check service status
launchctl list | grep ccx

# Check port
curl -s -o /dev/null -w "%{http_code}" http://localhost:3688/
```

### View Logs

```bash
# Standard output
cat /tmp/ccx.stdout.log

# Error output
cat /tmp/ccx.stderr.log

# Application log
cat "<install-dir>/backend-go/logs/app.log"
```

### Update CCX to Latest Version

```bash
bash "<path-to-skill>/scripts/install_ccx.sh"
```

The script will detect the existing installation and offer to update.

### Change Access Password

Edit `backend-go/.env` and change `PROXY_ACCESS_KEY`, then restart:

```bash
launchctl stop com.ccx.proxy
launchctl start com.ccx.proxy
```

### Change Port

Edit `backend-go/.env` and change `PORT`, then restart:

```bash
launchctl stop com.ccx.proxy
launchctl start com.ccx.proxy
```

### Uninstall CCX

```bash
# 1. Stop and remove LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.ccx.proxy.plist
rm ~/Library/LaunchAgents/com.ccx.proxy.plist

# 2. Delete install directory (caution: removes all configs)
rm -rf "<install-dir>"
```

## Troubleshooting

See `references/troubleshooting.md` for detailed solutions to common issues.

### Quick Fixes

| Problem | Solution |
|---------|----------|
| Browser shows "无法访问此网站" | CCX is not running. Run `launchctl start com.ccx.proxy` |
| Port 3688 already in use | Change `PORT` in `.env` to another value (e.g., 3689) |
| "Permission denied" on binary | Run `chmod +x backend-go/ccx` |
| Wrong architecture binary | Ensure you downloaded the correct binary for your Mac (arm64 vs amd64) |
| Config lost after update | Check `backend-go/.config/backups/` for automatic backups |

## Resources

- `scripts/install_ccx.sh` — Automated install script
- `assets/com.ccx.proxy.plist` — LaunchAgent template for macOS auto-start
- `references/troubleshooting.md` — Detailed troubleshooting guide
- GitHub Repository: https://github.com/BenedictKing/ccx
