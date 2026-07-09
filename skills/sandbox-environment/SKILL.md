---
name: sandbox-environment
description: Use at the start of any conversation when running inside a Docker sandbox (check for /.dockerenv) — covers CLAUDE_ENV_FILE persistence, the shell-completions-break-bash landmine, login-shell PATH gotchas, and network/Docker access notes specific to sandbox sessions. Not relevant on the host machine.
---

# Sandbox Environment Notes

This only applies inside a Docker sandbox (check for `/.dockerenv`). None of this applies when working directly on the host machine.

## Environment persistence

The sandbox has a persistent environment configured via `CLAUDE_ENV_FILE` (`/etc/sandbox-persistent.sh`). Per the [Claude Code docs](https://code.claude.com/docs/en/settings#bash-tool-behavior), this file is sourced before every Bash command execution, so environment variables set there persist across all Bash tool invocations in the session.

- Use `echo "export VAR_NAME=value" >> /etc/sandbox-persistent.sh` to add persistent variables
- Useful for tool installations (nvm, sdkman, etc.) that modify PATH or environment variables

## Critical: never put shell completions in CLAUDE_ENV_FILE

Shell completion scripts (e.g. `bash_completion` for NVM, SDKMAN) **will completely break the Bash tool** if sourced via `CLAUDE_ENV_FILE`. It's sourced before *every* Bash command, not just at shell init — completion scripts depend on `COMP_WORDS`/`COMP_CWORD`/`COMPREPLY`, which only exist during actual tab-completion, so they error out silently on every single command.

**Wrong** — breaks the shell:
```bash
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
[[ -s "$SDKMAN_DIR/etc/bash_completion.sh" ]] && source "$SDKMAN_DIR/etc/bash_completion.sh"
```

**Correct** — only the core init script:
```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
```

**Symptoms if this happens:** every Bash command returns no output at all — `echo`, `pwd`, everything silently fails. The tool is unusable. Fix: remove the completion line(s) from `/etc/sandbox-persistent.sh` and restart the session.

## Using the Bash tool after installing something

If a just-installed tool isn't found on `PATH`, use a fresh login shell instead of retrying directly — shell snapshots can hold cached environment state from before the tool was installed, and a login shell always re-sources `/etc/sandbox-persistent.sh` fresh:

```bash
bash -l -c "node --version"
bash -l -c "java -version"
```

Example of persisting an nvm/sdkman install so this works going forward:
```bash
echo 'export NVM_DIR="$HOME/.nvm"' >> /etc/sandbox-persistent.sh
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /etc/sandbox-persistent.sh
```

## Network access

Raw Bash/curl egress is broad in this sandbox — it is not narrowly restricted. What CLAUDE.md elsewhere calls "a firewall" is actually the `WebFetch` tool's own per-domain permission list in `settings.json`, not a network-layer block; unlisted domains still work fine from a shell command.

The filesystem, not the network, is the real isolation boundary: only the working directory tree (e.g. `~/dev`) is mounted from the host. Nothing else under the home directory exists or is writable in the container.

## Docker network access

A Docker daemon is available. Published ports on `localhost` are reachable directly (it's in the shell's "no proxy" config) — useful for hitting a locally-run dev server or a published container port.

## git clone can corrupt through the proxy

`git clone` over HTTPS (smart-HTTP pack protocol) can reliably fail with pack corruption errors (`inflate: data stream error`, `pack checksum mismatch`, `bad object`) on repos with any meaningful size — reproduced consistently on a ~50MB repo, with corruption still occurring even after limiting blobs to `--filter=blob:limit=100k`. `--depth 1`, forcing `http.version=HTTP/1.1`, and raising `http.postBuffer` did not help. This looks like the sandbox's proxy mishandling large binary pack streams specifically — not a general network reliability problem.

A plain tarball fetch through the same proxy works fine, since it's a simple GET rather than git's pack negotiation:

```bash
BRANCH=$(gh api repos/<owner>/<repo> --jq '.default_branch')
curl -sSL -H "Authorization: token $(gh auth token)" \
  -o repo.tar.gz "https://codeload.github.com/<owner>/<repo>/tar.gz/refs/heads/$BRANCH"
mkdir repo && tar -xzf repo.tar.gz -C repo --strip-components=1
```

Use this when you just need a working tree (e.g. to run a dev server) and don't need git history. If you need actual git history/operations, retry `git clone` — the corruption is reproducible but not deterministic, so it may succeed on a retry for smaller repos.

## Testing a local dev server

`curl` works fine against `localhost`/`127.0.0.1` from Bash. The `WebFetch` tool does not — it rejects a literal `localhost` URL outright ("Invalid URL"), and even given a raw loopback IP like `127.0.0.1`, it force-upgrades `http://` to `https://` per its own documented behavior, which fails the TLS handshake against a plain-HTTP dev server. Use `curl` (or the Chrome DevTools MCP server, if set up — see the `vercel-preview-verification` skill) to check a local server instead of WebFetch.

## Backgrounding a dev server

A backgrounded process started without `disown` can die when its parent shell context ends between Bash tool calls — it'll look like it started fine but `curl` against it moments later gives connection refused. Use `disown` after backgrounding, and confirm reachability with `curl` before relying on it being up.

If you kill and restart a dev server in a hurry, make sure the old process is actually dead (check for zombies with `ps aux`, not just `pkill` and move on) before starting a new one — two processes racing to write the same local build cache can corrupt it. Hit this with Next.js/Turbopack specifically: a killed-and-immediately-restarted `next dev` threw `Failed to restore task data (corrupted database or bug)` / `Invalid block type` from its persistent cache. Fix is `rm -rf .next` and a single clean restart, not a retry loop.
