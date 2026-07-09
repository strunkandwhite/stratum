# /stratum

Synchronize shared Claude Code configuration across all projects, and keep the stratum repo itself in sync with its remote.

## What this does

1. **Pulls** the latest stratum changes from `origin/main`
2. **Gathers** permissions from all project `.claude/settings.local.json` files in `~/code/`
3. **Promotes** generic tool permissions to the global `settings.json` (project-specific ones stay local)
4. **Trims** promoted entries from project local files to keep them clean
5. **Verifies** symlinks from `~/.claude/` point to the stratum repo
6. **Commits and pushes** any other outstanding stratum repo changes

## Promotion rules

- Generic CLI tools (git, npm, pnpm, node, turso, etc.) → always promote
- Skills, MCP tools, WebSearch → always promote
- WebFetch domains → promote if found in 2+ projects
- Project-specific commands (absolute paths, env prefixes, `./` scripts) → keep local
- `additionalDirectories` (except `/tmp`) → keep local

## Run it

```bash
$HOME/code/stratum/bin/sync.sh
```

This pulls first, then promotes/trims/symlinks as above. Review the summary output and verify changes look correct. If this is the first run, existing files at `~/.claude/settings.json` and `~/.claude/CLAUDE.md` will be backed up to `.bak` before symlinking.

## Commit and push

`settings.json` is gitignored, so the sync script itself rarely leaves anything to commit. This step catches any other tracked changes sitting in the stratum repo — CLAUDE.md edits, skill/command edits, etc. — made earlier in the session:

```bash
git -C $HOME/code/stratum status --short
```

If there are tracked changes worth keeping, stage them by name (not `-A` — some vendored plugin directories carry their own untracked `.claude/settings.local.json` that should stay local), commit with a message describing why, and push:

```bash
git -C $HOME/code/stratum add <files>
git -C $HOME/code/stratum commit -m "..."
git -C $HOME/code/stratum push
```
