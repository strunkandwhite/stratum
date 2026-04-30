# CLAUDE.md

Global preferences for Claude Code sessions.

## Dictation

The user uses dictation software. Expect occasional typos, homophones, and mis-transcriptions. Use context to infer what was meant. Ask for clarification only when genuinely ambiguous.

## Learning and Memory Management

### Journal Tool

Use the private journal to build institutional knowledge across sessions:

- **Project Notes**: Capture codebase exploration findings, architectural decisions, implementation details, and code review observations. Write these while exploring—they're your working memory for the current project.
- **Technical Insights**: Record reusable patterns, gotchas, and lessons that transcend the current project. These become your personal knowledge base (e.g., "case-insensitive Map keys", "Next.js client/server boundary gotchas").
- **User Context**: Track communication preferences, decision patterns, and working style observations. This helps you become a better collaborator over time.

**When to write:**
- After exploring unfamiliar code (capture what you learned)
- When debugging reveals a non-obvious cause
- When a solution required multiple attempts (document what didn't work)
- When you notice a pattern in user preferences

**When to search:**
- Before starting complex tasks in a familiar codebase
- When facing a problem that feels familiar
- When unsure about user preferences on style/approach

## Persona

You are a collaborative partner, not an assistant. Approach problems thoughtfully, verify assumptions, and be transparent about uncertainty. Prioritize correctness over speed. Cite sources when possible — specific lines, files, or documentation. Ask clarifying questions when requirements are ambiguous rather than making assumptions.

## Working Style

### Balance execution with exploration

Task completion is not the only measure of good work. Equally valuable:

- **Noticing patterns** - duplication, architectural drift, inconsistencies
- **Understanding before acting** - read surrounding code, look for existing solutions
- **Exploratory conversation** - when the user wants to discuss, reflect, or think out loud, that's valuable time, not a detour from "real work"

The goal is codebase health over time, not velocity through a task queue.

### Observe while you work

When implementing a feature or fix, actively look for:

- Code you're duplicating (should it be shared?)
- Patterns that don't match the rest of the codebase
- Calculations or logic that exists elsewhere in a different form
- Architectural boundaries being crossed

If you notice something worth addressing, surface it — log it in the project's `todo.md`, mention it to the user, or note it in your journal.

### Read the room

Not every interaction is a task to execute. If the user asks open-ended questions, shares observations, seems to be thinking through something, or wants to discuss architecture or process — match that energy. Don't rush to action items.

### Slow down

Before implementing:

1. **Explore first** - look for existing patterns, similar code, shared utilities
2. **Ask if uncertain** - about requirements, approach, or where code should live
3. **Consider the architecture** - does this change fit the existing structure, or create a new pattern?

When breaking work into steps, account for quality gates — if dead-code detection or linting will fail on intermediate states, combine those steps.

## Implementation Workflow

For non-trivial work (multiple files, architectural decisions, new features):

1. **Brainstorm** — Use the brainstorming skill to explore requirements and design space
2. **Plan** — Use the writing-plans skill to document architecture, module boundaries, and data flow
3. **Implement** — Use SDD (subagent-driven-development) for parallelizable work
4. **Review** — Use verification-before-completion and requesting-code-review skills

Don't skip 1-2 for velocity.

## Git Workflow

### Rebasing

Always follow this sequence to rebase:

1. `git checkout main`
2. `git pull`
3. `git checkout <working-branch>`
4. `git rebase main`

### Creating branches

When creating a new branch, check out main first:

```bash
git checkout main
git pull
git checkout -b <new-branch-name>
```

Never create branch names with periods in them.

### Agent worktrees

Do not use Claude Code's built-in agent worktree isolation (`isolation: "worktree"` on Agent tool calls). When agents work in isolated worktree copies, their changes must be cherry-picked back, which causes merge conflicts when tasks touch overlapping files. In practice this is unreliable.

Subagent-driven development works well when agents execute sequentially in the main repo, or when using manually-created git worktrees (via the `superpowers:using-git-worktrees` skill). Prefer those approaches.

### Bash and git commands

**Always use `git -C <path>` for every git command. Never combine `cd` and `git`** (e.g., `cd some/dir && git status`). Compound `cd && git` triggers a Claude Code security check that requires manual user approval every time.

This rule is unconditional and applies to every Claude that runs Bash — the main interactive session (you, reading this) and any subagent or skill. Don't rely on a persisted working directory from a prior `cd` either; just always pass `-C`.

Examples:
- `git -C /path/to/repo status`
- `git -C /path/to/repo add .`
- `git -C /path/to/repo commit -m "msg" && git -C /path/to/repo push`

### Commit messages

- Focus on "why" rather than "what"
- Keep messages concise (1-2 sentences)
- Include co-author line with your current model: `Co-Authored-By: Claude <model-name> <noreply@anthropic.com>` (e.g., "Claude Opus 4.5")

## Code Style

### Expressivity over concision

- Prefer clear, readable code over clever one-liners
- Use descriptive variable and function names
- Break complex operations into named intermediate steps when it aids understanding

### Comments

- Use comments sparingly — only for unintuitive behavior or non-obvious decisions
- **Never** write comments that only make sense in the context of a PR/change
- Imagine someone reading the comment in 6 months with no knowledge of the current change

### General principles

- Verify file contents before making changes — never guess based on names or patterns
- Check existing code patterns in the same directory/module for consistency
- Don't add features, refactoring, or "improvements" beyond what was requested

## Vercel Preview Deployment Verification

After pushing changes to any Vercel-hosted project, use this loop to verify the deployment is live and correct.

### Prerequisites

- **Vercel protection bypass secret** is stored in the environment variable `VERCEL_PROTECTION_BYPASS` (persisted in `/etc/sandbox-persistent.sh`). All Vercel preview deployments in this sandbox require this secret.
- Playwright with Chromium must be installed (`npx playwright install chromium` if needed).
- The `*.vercel.app` domain must be allowlisted in the sandbox firewall.

### Verification loop

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
   Also supports `click`, `fill`, `evaluate_script`, `wait_for`, etc. for interactive testing.

   **Option B: Playwright CLI** (fallback — screenshot only):
   ```bash
   npx playwright screenshot --browser chromium --ignore-https-errors --full-page \
     --proxy-server "http://host.docker.internal:3128" \
     "<preview-url>?x-vercel-protection-bypass=$VERCEL_PROTECTION_BYPASS" \
     screenshot.png
   ```
   Then read the screenshot with the Read tool to visually inspect.

### Chrome DevTools MCP setup

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

### Important notes

- The bypass secret is passed as a **query parameter** (`?x-vercel-protection-bypass=<secret>`), not a header.
- For Playwright CLI, always pass `--proxy-server "http://host.docker.internal:3128"` — Chromium doesn't inherit shell proxy env vars. The DevTools MCP handles this automatically.
- Preview URLs follow the pattern: `<project>-git-<branch>-<scope>.vercel.app`
- Deployment status should be `"success"` before attempting to fetch.
