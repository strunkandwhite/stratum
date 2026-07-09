#!/usr/bin/env bash
set -euo pipefail

STRATUM_REPO="$(cd "$(dirname "$0")/.." && pwd)"
CODE_DIR="$(dirname "$STRATUM_REPO")"
CLAUDE_HOME="$HOME/.claude"
TMPDIR_SYNC="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_SYNC"' EXIT

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters for summary
promoted_count=0
symlinks_created_count=0

# --- Phase 0: Pull latest from origin ---

echo -e "${BLUE}Phase 0: Pulling latest stratum changes...${NC}"
git -C "$STRATUM_REPO" pull

# --- jq filter: categorize a permission ---
# Returns "promote" or "local" based on the rules
CATEGORIZE_FILTER="
def is_generic_tool:
  test(\"^Bash\\\\((git|gh|npm|npx|pnpm|node|python3|jq|curl|tree|mkdir|cp|cat|find|ls|head|grep|awk|sort|cut|tee|wc|du|echo|xargs|test|basename|xxd|lsof|pkill|md5|turso|brew|pdftotext|cat >)[: )]\");

def is_shell_keyword:
  . == \"Bash(for:\" or . == \"Bash(done)\" or . == \"Bash(do)\" or . == \"Bash(then)\" or . == \"Bash(fi)\";

def is_always_promote:
  is_generic_tool or
  is_shell_keyword or
  startswith(\"Skill(\") or
  startswith(\"mcp__\") or
  . == \"WebSearch\" or
  startswith(\"Read(/$HOME/.claude/\") or
  startswith(\"Read(//$HOME/.claude/\");

def is_project_specific:
  (contains(\"$CODE_DIR/\")) or
  startswith(\"Bash(./\") or
  startswith(\"Bash(BUCKET=\") or
  startswith(\"Bash(export \") or
  startswith(\"Bash(do \");

if is_project_specific then \"local\"
elif is_always_promote then \"promote\"
elif startswith(\"WebFetch(domain:\") then \"webfetch\"
else \"promote\"
end
"

# --- Phase 1: Gather permissions from all projects ---

echo -e "${BLUE}Phase 1: Gathering permissions from projects...${NC}"

# Collect all permissions with their project source and category
echo '[]' > "$TMPDIR_SYNC/all_perms.json"

for settings_file in "$CODE_DIR"/*/.claude/settings.local.json; do
  [ -f "$settings_file" ] || continue
  project="$(basename "$(dirname "$(dirname "$settings_file")")")"
  [ "$project" = "stratum" ] && continue

  # Extract permissions, tag each with project and category
  jq --arg project "$project" --argjson categorize "null" \
    '[.permissions.allow[]? | {perm: ., project: $project}]' \
    "$settings_file" > "$TMPDIR_SYNC/project_perms.json"

  # Merge into all_perms
  jq -s '.[0] + .[1]' "$TMPDIR_SYNC/all_perms.json" "$TMPDIR_SYNC/project_perms.json" \
    > "$TMPDIR_SYNC/all_perms_new.json"
  mv "$TMPDIR_SYNC/all_perms_new.json" "$TMPDIR_SYNC/all_perms.json"
done

# Count occurrences of each permission across projects and categorize
jq "$CATEGORIZE_FILTER" <<< '"test"' > /dev/null 2>&1  # validate filter

# Build the promotion list: categorize each unique perm, count projects, decide
jq --arg filter "$CATEGORIZE_FILTER" '
  group_by(.perm) |
  map({
    perm: .[0].perm,
    count: (map(.project) | unique | length),
    projects: (map(.project) | unique)
  }) |
  map(. + {
    category: (.perm | '"$CATEGORIZE_FILTER"')
  }) |
  map(. + {
    action: (
      if .category == "promote" then "promote"
      elif .category == "webfetch" then
        if .count >= 2 then "promote" else "local" end
      else "local"
      end
    )
  })
' "$TMPDIR_SYNC/all_perms.json" > "$TMPDIR_SYNC/categorized.json"

# Get the list of perms to promote
jq '[.[] | select(.action == "promote") | .perm]' "$TMPDIR_SYNC/categorized.json" > "$TMPDIR_SYNC/to_promote.json"

# Load or create the global settings.json
if [ ! -f "$STRATUM_REPO/settings.json" ]; then
  if [ -f "$CLAUDE_HOME/settings.json" ]; then
    cp "$CLAUDE_HOME/settings.json" "$STRATUM_REPO/settings.json"
  else
    echo '{"permissions":{"allow":[],"deny":[],"ask":[]}}' | jq . > "$STRATUM_REPO/settings.json"
  fi
fi

# Merge promoted perms into global settings (deduplicate and sort)
jq --argjson new_perms "$(cat "$TMPDIR_SYNC/to_promote.json")" \
  '.permissions.allow = (.permissions.allow + $new_perms | unique | sort)' \
  "$STRATUM_REPO/settings.json" > "$STRATUM_REPO/settings.json.tmp"
mv "$STRATUM_REPO/settings.json.tmp" "$STRATUM_REPO/settings.json"

promoted_count=$(jq 'length' "$TMPDIR_SYNC/to_promote.json")
echo -e "${GREEN}  Promoted $promoted_count new permission(s) to global${NC}"

# Print what was promoted
if [ "$promoted_count" -gt 0 ]; then
  jq -r '.[] | select(.action == "promote") | "  + \(.perm) (from \(.projects | join(", ")))"' \
    "$TMPDIR_SYNC/categorized.json"
fi

# --- Phase 2: Trim project local files ---

echo -e "${BLUE}Phase 2: Trimming promoted entries from project settings...${NC}"

# Get the full global allow list
jq '.permissions.allow' "$STRATUM_REPO/settings.json" > "$TMPDIR_SYNC/global_allow.json"

for settings_file in "$CODE_DIR"/*/.claude/settings.local.json; do
  [ -f "$settings_file" ] || continue
  project="$(basename "$(dirname "$(dirname "$settings_file")")")"
  [ "$project" = "stratum" ] && continue

  # Filter out entries that exist in global
  remaining=$(jq --argjson global "$(cat "$TMPDIR_SYNC/global_allow.json")" \
    '.permissions.allow = [.permissions.allow[]? | select(. as $p | $global | index($p) | not)]' \
    "$settings_file")

  remaining_count=$(echo "$remaining" | jq '.permissions.allow | length')

  # Check if any other meaningful fields exist
  has_deny=$(echo "$remaining" | jq '.permissions.deny // [] | length')
  has_ask=$(echo "$remaining" | jq '.permissions.ask // [] | length')
  has_dirs=$(echo "$remaining" | jq '[.permissions.additionalDirectories // [] | .[] | select(. != "/tmp")] | length')

  if [ "$remaining_count" -eq 0 ] && [ "$has_deny" -eq 0 ] && [ "$has_ask" -eq 0 ] && [ "$has_dirs" -eq 0 ]; then
    rm "$settings_file"
    echo -e "  ${YELLOW}~${NC} $project (removed — all permissions now global)"
  else
    echo "$remaining" | jq . > "$settings_file.tmp"
    mv "$settings_file.tmp" "$settings_file"
    echo -e "  ${YELLOW}~${NC} $project ($remaining_count local permission(s) remaining)"
  fi
done

# --- Phase 3: Verify symlinks (or copy in sandbox) ---

IS_SANDBOX=false
if [ -f "/.dockerenv" ]; then
  IS_SANDBOX=true
  echo -e "${BLUE}Phase 3: Copying files (sandbox mode — read-only ~/.claude)...${NC}"
else
  echo -e "${BLUE}Phase 3: Verifying symlinks...${NC}"
fi

link_or_copy() {
  local source="$1"
  local target="$2"
  local label="$3"

  mkdir -p "$(dirname "$target")"

  if [ "$IS_SANDBOX" = true ]; then
    cp "$source" "$target"
    echo -e "  ${GREEN}✓${NC} $label copied"
    return
  fi

  if [ -L "$target" ]; then
    current=$(readlink "$target")
    if [ "$current" = "$source" ]; then
      echo -e "  ${GREEN}✓${NC} $label already linked"
      return
    else
      echo -e "  ${YELLOW}⚠${NC} $label points to $current, updating..."
      rm "$target"
    fi
  elif [ -f "$target" ]; then
    echo -e "  ${YELLOW}⚠${NC} $label exists as regular file, backing up to ${target}.bak"
    mv "$target" "${target}.bak"
  fi

  ln -s "$source" "$target"
  symlinks_created_count=$((symlinks_created_count + 1))
  echo -e "  ${GREEN}✓${NC} $label → $source"
}

link_or_copy_dir() {
  local source="${1%/}"
  local target="${2%/}"
  local label="$3"

  mkdir -p "$(dirname "$target")"

  if [ "$IS_SANDBOX" = true ]; then
    rm -rf "$target"
    cp -r "$source" "$target"
    echo -e "  ${GREEN}✓${NC} $label copied"
    return
  fi

  if [ -L "$target" ]; then
    current=$(readlink "$target")
    if [ "$current" = "$source" ]; then
      echo -e "  ${GREEN}✓${NC} $label already linked"
      return
    else
      echo -e "  ${YELLOW}⚠${NC} $label points to $current, updating..."
      rm "$target"
    fi
  elif [ -d "$target" ]; then
    echo -e "  ${YELLOW}⚠${NC} $label exists as directory, replacing with link..."
    rm -rf "$target"
  fi

  ln -s "$source" "$target"
  symlinks_created_count=$((symlinks_created_count + 1))
  echo -e "  ${GREEN}✓${NC} $label → $source"
}

if [ "$IS_SANDBOX" = true ] && [ -f "$STRATUM_REPO/settings.sandbox.json" ]; then
  link_or_copy "$STRATUM_REPO/settings.sandbox.json" "$CLAUDE_HOME/settings.json" "settings.json (sandbox)"
else
  link_or_copy "$STRATUM_REPO/settings.json" "$CLAUDE_HOME/settings.json" "settings.json"
fi
link_or_copy "$STRATUM_REPO/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md" "CLAUDE.md"
link_or_copy "$STRATUM_REPO/bin/statusline-command.sh" "$CLAUDE_HOME/statusline-command.sh" "statusline-command.sh"

# Symlink commands
if [ -d "$STRATUM_REPO/commands" ]; then
  mkdir -p "$CLAUDE_HOME/commands"
  for cmd_file in "$STRATUM_REPO/commands"/*.md; do
    [ -f "$cmd_file" ] || continue
    cmd_name="$(basename "$cmd_file")"
    link_or_copy "$cmd_file" "$CLAUDE_HOME/commands/$cmd_name" "commands/$cmd_name"
  done
fi

# Sync skills (symlink on host, copy in sandbox)
if [ -d "$STRATUM_REPO/skills" ]; then
  mkdir -p "$CLAUDE_HOME/skills"
  for skill_dir in "$STRATUM_REPO/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    link_or_copy_dir "$skill_dir" "$CLAUDE_HOME/skills/$skill_name" "skills/$skill_name"
  done
fi

# --- Phase 4: Patch settings.json for current environment ---

echo -e "${BLUE}Phase 4: Patching settings for environment...${NC}"

# Ensure statusLine config points to the right path
STATUSLINE_PATH="$CLAUDE_HOME/statusline-command.sh"
CURRENT_CMD=$(jq -r '.statusLine.command // empty' "$CLAUDE_HOME/settings.json")

if [ "$CURRENT_CMD" != "bash $STATUSLINE_PATH" ]; then
  jq --arg cmd "bash $STATUSLINE_PATH" \
    '.statusLine = {"type": "command", "command": $cmd}' \
    "$CLAUDE_HOME/settings.json" > "$CLAUDE_HOME/settings.json.tmp"
  mv "$CLAUDE_HOME/settings.json.tmp" "$CLAUDE_HOME/settings.json"
  echo -e "  ${GREEN}✓${NC} statusLine command → $STATUSLINE_PATH"
else
  echo -e "  ${GREEN}✓${NC} statusLine command already correct"
fi

# --- Summary ---

echo ""
echo -e "${BLUE}=== Sync Complete ===${NC}"
echo -e "  Global permissions: $(jq '.permissions.allow | length' "$CLAUDE_HOME/settings.json")"
echo -e "  Synced: settings.json, CLAUDE.md, statusline-command.sh, commands/, skills/"
echo -e "${BLUE}Done.${NC}"
