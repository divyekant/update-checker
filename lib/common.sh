#!/usr/bin/env bash
# Shared utilities for update-checker adapters

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
PLUGINS_DIR="${CLAUDE_DIR}/plugins"
THROTTLE_FILE="${PLUGINS_DIR}/cache/update-checker-last-check"
THROTTLE_HOURS=24
GIT_TIMEOUT=15

# Portable timeout — macOS lacks GNU timeout
# Falls back to no-timeout execution (safe: hook is async, manual use is interactive)
run_timeout() {
  local secs="$1"
  shift
  if command -v timeout &>/dev/null; then
    timeout "$secs" "$@"
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$secs" "$@"
  else
    "$@"
  fi
}

# Check if throttle period has elapsed. Returns 0 if check should run, 1 if throttled.
should_check() {
  if [ ! -f "$THROTTLE_FILE" ]; then
    return 0
  fi
  local last_check now diff
  last_check=$(cat "$THROTTLE_FILE")
  now=$(date +%s)
  diff=$(( (now - last_check) / 3600 ))
  if [ "$diff" -lt "$THROTTLE_HOURS" ]; then
    return 1
  fi
  return 0
}

# Update the throttle timestamp
update_throttle() {
  mkdir -p "$(dirname "$THROTTLE_FILE")"
  date +%s > "$THROTTLE_FILE"
}

# Git fetch with timeout. Returns 0 if new commits available, 1 if up to date, 2 on error.
git_fetch_check() {
  local repo_dir="$1"
  local branch="${2:-}"

  if [ ! -d "$repo_dir/.git" ] && ! git -C "$repo_dir" rev-parse --is-inside-work-tree &>/dev/null; then
    return 2
  fi

  # Fetch with timeout
  if ! run_timeout "$GIT_TIMEOUT" git -C "$repo_dir" fetch origin --quiet 2>/dev/null; then
    return 2
  fi

  # Determine branch to compare (local-only, no network)
  if [ -z "$branch" ]; then
    branch=$(git -C "$repo_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    branch="${branch:-main}"
  fi

  local local_sha remote_sha
  local_sha=$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)
  remote_sha=$(git -C "$repo_dir" rev-parse "origin/${branch}" 2>/dev/null)

  if [ "$local_sha" = "$remote_sha" ]; then
    return 1
  fi
  return 0
}

# Get commit log between two SHAs. Returns one-line-per-commit summary.
git_changelog() {
  local repo_dir="$1"
  local from_sha="$2"
  local to_sha="${3:-HEAD}"
  # Use -n instead of piping to head to avoid SIGPIPE with set -eo pipefail
  git -C "$repo_dir" log --oneline -n 10 "${from_sha}..${to_sha}" 2>/dev/null || true
}

# Escape a string for safe JSON embedding
escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Resolve the directory containing a file path (follows symlinks)
resolve_dir() {
  local path="$1"
  if [ -L "$path" ]; then
    path=$(readlink -f "$path" 2>/dev/null || readlink "$path")
  fi
  if [ -f "$path" ]; then
    dirname "$path"
  elif [ -d "$path" ]; then
    echo "$path"
  else
    echo ""
  fi
}

# Check if a path is inside a git repo. Returns the repo root or empty string.
find_git_root() {
  local dir="$1"
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    echo ""
    return
  fi
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo ""
}

# Check if a path is inside the plugins cache (i.e., managed by a plugin)
is_plugin_managed() {
  local path="$1"
  local cache_dir="${PLUGINS_DIR}/cache"
  if [[ "$path" == "$cache_dir"* ]]; then
    return 0
  fi
  return 1
}
