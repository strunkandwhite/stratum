#!/usr/bin/env bash
input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
commit=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)

parts=""

if [ -f "/.dockerenv" ]; then
  parts="[sandbox]"
fi

parts="$parts  $cwd"

if [ -n "$branch" ]; then
  parts="$parts  $branch"
fi

if [ -n "$commit" ]; then
  parts="$parts  $commit"
fi

if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  parts="$parts  ctx: ${used_int}%"
fi

printf "%s" "$parts"
