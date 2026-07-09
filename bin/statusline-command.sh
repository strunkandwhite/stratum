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

ahead_behind=""
upstream=$(git -C "$cwd" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
if [ -n "$upstream" ]; then
  read -r behind_count ahead_count < <(git -C "$cwd" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)
  if [ -n "$ahead_count" ] && [ "$ahead_count" -gt 0 ]; then
    ahead_behind="${ahead_behind}↑${ahead_count}"
  fi
  if [ -n "$behind_count" ] && [ "$behind_count" -gt 0 ]; then
    ahead_behind="${ahead_behind}↓${behind_count}"
  fi
fi

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
  append_part "${commit}${ahead_behind}"
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
    now_epoch=$(date +%s)
    seconds_until_reset=$(( ${five_hour_resets_at%.*} - now_epoch ))
    if [ "$seconds_until_reset" -lt 0 ]; then
      seconds_until_reset=0
    fi
    hours_until_reset=$(( seconds_until_reset / 3600 ))
    minutes_until_reset=$(( (seconds_until_reset % 3600) / 60 ))
    usage="$usage (resets in $(printf '%d:%02d' "$hours_until_reset" "$minutes_until_reset"))"
  fi
fi
if [ -n "$seven_day" ]; then
  usage="$usage 7d:$(printf '%.0f' "$seven_day")%"
fi
if [ -n "$usage" ]; then
  append_part "$usage"
fi

printf "%s" "$parts"
