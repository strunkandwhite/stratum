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

5. **Visual verification** — Two options, in order of preference:

   **Option A: Chrome DevTools MCP** (preferred — interactive, supports clicking/inspecting):
   ```
   mcp__chrome-devtools__navigate_page  url=<preview-url>?x-vercel-protection-bypass=$VERCEL_PROTECTION_BYPASS
   mcp__chrome-devtools__take_screenshot  fullPage=true
   ```

   **Option B: Playwright CLI** (fallback — screenshot only):
   ```bash
   npx playwright screenshot --browser chromium --ignore-https-errors --full-page \
     --proxy-server "http://host.docker.internal:3128" \
     "<preview-url>?x-vercel-protection-bypass=$VERCEL_PROTECTION_BYPASS" \
     screenshot.png
   ```
   Then read the screenshot with the Read tool to visually inspect.

## Chrome DevTools MCP setup

The Chrome DevTools MCP server (`chrome-devtools-mcp`) requires setup in the sandbox:

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

2. **Virtual display**: The MCP server launches Chrome in headful mode, which needs an X server:
   ```bash
   Xvfb :99 -screen 0 1920x1080x24 &>/dev/null &
   echo 'export DISPLAY=:99' >> /etc/sandbox-persistent.sh
   ```
   `xvfb-run` is pre-installed in the sandbox.

Both steps are persisted — the wrapper script survives across calls, and `DISPLAY=:99` is in `/etc/sandbox-persistent.sh`. However, the Xvfb process must be restarted if the sandbox restarts.

## Important notes

- The bypass secret is passed as a **query parameter** (`?x-vercel-protection-bypass=<secret>`), not a header.
- For Playwright CLI, always pass `--proxy-server "http://host.docker.internal:3128"` — Chromium doesn't inherit shell proxy env vars. The DevTools MCP handles this automatically.
- Preview URLs follow the pattern: `<project>-git-<branch>-<scope>.vercel.app`
- Deployment status should be `"success"` before attempting to fetch.
