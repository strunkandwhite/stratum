#!/usr/bin/env bash
input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
five_hour=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hour_resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
commit=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)

parts=""

append_part() {
  if [ -n "$parts" ]; then
    parts="$parts | $1"
  else
    parts="$1"
  fi
}

if [ -f "/.dockerenv" ]; then
  append_part "[sandbox]"
fi

append_part "$cwd"

if [ -n "$branch" ]; then
  append_part "$branch"
fi

if [ -n "$commit" ]; then
  append_part "$commit"
fi

if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  append_part "ctx: ${used_int}%"
fi

if [ -n "$model" ]; then
  append_part "$model"
fi

usage=""
if [ -n "$five_hour" ]; then
  five_hour_int=$(printf '%.0f' "$five_hour")
  usage="5h:${five_hour_int}%"
  if [ "$five_hour_int" -gt 80 ] && [ -n "$five_hour_resets_at" ]; then
    reset_time=$(date -r "$five_hour_resets_at" '+%H:%M' 2>/dev/null || date -d "@$five_hour_resets_at" '+%H:%M' 2>/dev/null)
    if [ -n "$reset_time" ]; then
      usage="$usage (resets $reset_time)"
    fi
  fi
fi
if [ -n "$seven_day" ]; then
  usage="$usage 7d:$(printf '%.0f' "$seven_day")%"
fi
if [ -n "$usage" ]; then
  append_part "$usage"
fi

printf "%s" "$parts"
