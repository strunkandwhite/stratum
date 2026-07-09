---
name: wrap
description: Use when the user types /wrap or says to wrap up work - dispatches code review, fixes issues, then commits and pushes
---

# Wrap

Finish a unit of work: review, fix, commit, push.

## Steps

### 1. Dispatch code reviewer

Get the commit range for the current work:

```bash
BASE_SHA=$(git merge-base HEAD origin/master)
HEAD_SHA=$(git rev-parse HEAD)
```

**If BASE_SHA == HEAD_SHA** (work was already committed and pushed before /wrap was called), find the relevant commits from recent history using context clues (commit messages, what was implemented this session) and use those commits' parent as the base. Example: if the session produced 2 commits, use `git diff HEAD~2..HEAD`.

If there are uncommitted changes (staged or unstaged), note them — the reviewer should see the full diff including working tree changes.

Dispatch the `superpowers:code-reviewer` subagent with:
- What was implemented (summarize from context)
- The commit range (BASE_SHA..HEAD_SHA) or the diff for the relevant commits
- Include `git diff` output if there are uncommitted changes

### 2. Fix issues

When the reviewer returns:
- **Critical/Important issues**: Fix them immediately
- **Minor issues**: Fix if quick, otherwise note and move on
- Run the project's quality checks after fixes (`pnpm precommit` or equivalent from CLAUDE.md)

### 3. Commit

Stage and commit all changes (the work + any review fixes) with a descriptive message. Follow the project's commit message conventions from CLAUDE.md.

### 4. Push

Push to the remote. If on a feature branch, use `git push -u origin <branch>`. If on master/main, just `git push`.
