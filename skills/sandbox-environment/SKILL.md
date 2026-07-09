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
