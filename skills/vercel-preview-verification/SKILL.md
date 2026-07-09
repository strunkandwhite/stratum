---
name: vercel-preview-verification
description: Use after pushing changes to any Vercel-hosted project to verify the preview deployment is live and correct — polling for the deployment, fetching HTML, and visually inspecting via Chrome DevTools MCP or Playwright.
---

# Vercel Preview Deployment Verification

After pushing changes to any Vercel-hosted project, use this loop to verify the deployment is live and correct.

## Prerequisites

- **Vercel protection bypass secret** is stored in the environment variable `VERCEL_PROTECTION_BYPASS` (persisted in `/etc/sandbox-persistent.sh`). All Vercel preview deployments in this sandbox require this secret.
- Playwright with Chromium must be installed (`npx playwright install chromium` if needed).
- The `*.vercel.app` domain must be allowlisted in the sandbox firewall.

## Verification loop

1. **Push and create PR** — Vercel only deploys previews when a PR exists (bare branch pushes don't trigger deploys).

2. **Poll for deployment** — Wait ~15s, then check via GH API:
   ```bash
   gh api repos/<owner>/<repo>/deployments?per_page=5 \
     --jq '.[] | select(.environment == "Preview") | {id, ref, created_at}'
   ```

3. **Get the preview URL** — From the deployment status:
   ```bash
   gh api repos/<owner>/<repo>/deployments/<id>/statuses \
     --jq '.[0] | {state, environment_url}'
   ```
   Or parse the Vercel bot's PR comment (contains the canonical branch-based preview URL):
   ```bash
   gh pr view <pr-number> --json comments --jq '.comments[] | select(.author.login == "vercel") | .body'
   ```

4. **Verify HTML content** — Quick check via curl:
   ```bash
   curl -s "<preview-url>?x-vercel-protection-bypass=$VERCEL_PROTECTION_BYPASS" | grep "expected text"
   ```

5. **Visual verification** — Two options:

   **Option A: Chrome DevTools MCP** (interactive, supports clicking/inspecting — but see the setup section below before trying this first; it has not been gotten working in a fresh sandbox as of the last attempt):
   ```
   mcp__chrome-devtools__navigate_page  url=<preview-url>?x-vercel-protection-bypass=$VERCEL_PROTECTION_BYPASS
   mcp__chrome-devtools__take_screenshot  fullPage=true
   ```

   **Option B: Playwright CLI** (screenshot only, but reliably works — start here unless Chrome DevTools MCP is already confirmed working this session):
   ```bash
   npx playwright screenshot --browser chromium --ignore-https-errors --full-page \
     --proxy-server "http://host.docker.internal:3128" \
     "<preview-url>?x-vercel-protection-bypass=$VERCEL_PROTECTION_BYPASS" \
     screenshot.png
   ```
   Then read the screenshot with the Read tool to visually inspect.

## Chrome DevTools MCP setup — unresolved as of last attempt

**This has not been gotten working end-to-end via the `chrome-devtools-mcp` plugin in a fresh sandbox.** Every attempt failed with `Protocol error (Target.setDiscoverTargets): Target closed` when calling `new_page`, even after the steps below. Treat what follows as partial progress and known dead ends, not a working procedure — check for a newer plugin version or a different config before re-attempting.

1. **Chromium binary**: Install via Playwright (`npx playwright install chromium`), then create a wrapper at `/opt/google/chrome/chrome` that adds `--no-sandbox`:
   ```bash
   sudo mkdir -p /opt/google/chrome
   sudo tee /opt/google/chrome/chrome-wrapper.sh > /dev/null << 'EOF'
   #!/bin/bash
   exec /home/agent/.cache/ms-playwright/chromium-1200/chrome-linux/chrome --no-sandbox --disable-setuid-sandbox "$@"
   EOF
   sudo chmod +x /opt/google/chrome/chrome-wrapper.sh
   sudo ln -sf /opt/google/chrome/chrome-wrapper.sh /opt/google/chrome/chrome
   ```

2. **Virtual display**: Chrome needs an X server since the MCP server launches it in headful mode (`--headless` defaults to false and the plugin's launch command passes no extra args):
   ```bash
   Xvfb :99 -screen 0 1920x1080x24 &>/dev/null &
   ```
   `xvfb-run` is pre-installed in the sandbox. The Xvfb process does not survive a sandbox restart and must be started fresh each session — there's no way to persist a running process, only env vars.

3. **`DISPLAY` in `/etc/sandbox-persistent.sh` does NOT reach the MCP server.** This was the actual blocker, and it's a dead end, not a missing step: `CLAUDE_ENV_FILE` is documented as sourced before Bash tool commands specifically — it is not inherited by however the harness spawns MCP server subprocesses. Confirmed directly: with Xvfb running and `DISPLAY=:99` visible in every Bash command, reading `/proc/<chrome-devtools-mcp-pid>/environ` still showed no `DISPLAY` at all, and `new_page` still failed identically. Manually launching Chrome from a Bash command under the same Xvfb succeeded fine (real CDP handshake, real `webSocketDebuggerUrl`) — so Xvfb itself was never the problem, only getting `DISPLAY` into the MCP server's own process.

4. **Killing the MCP server process to force a fresh launch does not trigger a respawn** — it fully drops the tool connection instead. Reconnecting requires the user to reload the plugin from outside the session (e.g. `/reload-plugins`); there's no way to do this from Bash.

**Most promising untested lead:** the MCP server supports `--headless`, which would remove the `DISPLAY` dependency entirely. The plugin's launch command (`.claude-plugin/plugin.json` under the plugin's cache dir) currently passes no args beyond the package name — passing `--headless` (and possibly `--chrome-arg='--no-sandbox'`) there, if that config is editable and survives a plugin reload, is worth trying before spending more time on Xvfb/DISPLAY plumbing.

## Important notes

- The bypass secret is passed as a **query parameter** (`?x-vercel-protection-bypass=<secret>`), not a header.
- For Playwright CLI, always pass `--proxy-server "http://host.docker.internal:3128"` — Chromium doesn't inherit shell proxy env vars. The DevTools MCP handles this automatically.
- Preview URLs follow the pattern: `<project>-git-<branch>-<scope>.vercel.app`
- Deployment status should be `"success"` before attempting to fetch.
