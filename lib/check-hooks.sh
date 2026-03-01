#!/usr/bin/env bash
# Adapter: check user hooks for updates
# Output: JSON array of update objects to stdout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
HOOKS_DIR="${CLAUDE_DIR}/hooks"

check_hooks() {
  local results="[]"
  local checked_paths=()

  # Collect all hook command paths from settings.json
  if [ -f "$SETTINGS_FILE" ]; then
    local hook_commands
    hook_commands=$(jq -r '
      .hooks // {} | to_entries[] | .value[] | .hooks[]? | .command // empty
    ' "$SETTINGS_FILE" 2>/dev/null | sort -u)

    while IFS= read -r cmd; do
      [ -z "$cmd" ] && continue

      # Extract the script path from the command string
      # Commands might be: "/path/to/script.sh" or "'${CLAUDE_PLUGIN_ROOT}/...' args"
      local script_path
      script_path=$(echo "$cmd" | sed "s/'//g" | sed 's/\${CLAUDE_PLUGIN_ROOT}[^ ]*//' | awk '{print $1}')

      # Skip if path contains plugin variable (plugin-managed hooks)
      if [[ "$cmd" == *'CLAUDE_PLUGIN_ROOT'* ]]; then
        continue
      fi

      # Skip if already checked this path
      local already_checked=false
      for p in "${checked_paths[@]+"${checked_paths[@]}"}"; do
        if [ "$p" = "$script_path" ]; then
          already_checked=true
          break
        fi
      done
      if $already_checked; then
        continue
      fi
      checked_paths+=("$script_path")

      # Skip if inside plugin cache (managed by plugin adapter)
      if is_plugin_managed "$script_path"; then
        continue
      fi

      local hook_name
      hook_name=$(basename "$script_path" | sed 's/\.[^.]*$//')

      local resolved_dir
      resolved_dir=$(resolve_dir "$script_path")

      if [ -z "$resolved_dir" ]; then
        results=$(echo "$results" | jq \
          --arg n "$hook_name" \
          '. + [{"name": $n, "type": "hook", "source_type": "unknown", "status": "untracked"}]')
        continue
      fi

      local git_root
      git_root=$(find_git_root "$resolved_dir")

      if [ -z "$git_root" ]; then
        results=$(echo "$results" | jq \
          --arg n "$hook_name" \
          '. + [{"name": $n, "type": "hook", "source_type": "local", "status": "untracked"}]')
        continue
      fi

      # Git-backed hook — check for updates
      local current_sha
      current_sha=$(git -C "$git_root" rev-parse HEAD 2>/dev/null || echo "")

      if git_fetch_check "$git_root"; then
        local default_branch latest_sha changelog
        default_branch=$(git -C "$git_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
        default_branch="${default_branch:-main}"
        latest_sha=$(git -C "$git_root" rev-parse "origin/${default_branch}" 2>/dev/null || echo "")
        changelog=$(git_changelog "$git_root" "$current_sha" "origin/${default_branch}")

        local changelog_escaped
        changelog_escaped=$(escape_json "${changelog:-}")

        results=$(echo "$results" | jq \
          --arg n "$hook_name" \
          --arg cs "$current_sha" \
          --arg ls "$latest_sha" \
          --arg cl "$changelog_escaped" \
          '. + [{"name": $n, "type": "hook", "source_type": "git", "current_sha": $cs, "latest_sha": $ls, "changelog": $cl, "status": "update_available"}]')
      fi
    done <<< "$hook_commands"
  fi

  # Also scan ~/.claude/hooks/ directory for git-backed hook dirs
  if [ -d "$HOOKS_DIR" ]; then
    for dir in "$HOOKS_DIR"/*/; do
      [ ! -d "$dir" ] && continue
      local dir_name
      dir_name=$(basename "$dir")

      local git_root
      git_root=$(find_git_root "$dir")

      if [ -z "$git_root" ]; then
        continue
      fi

      # Check if already covered by settings.json scan
      local already_covered=false
      for p in "${checked_paths[@]+"${checked_paths[@]}"}"; do
        if [[ "$p" == "$dir"* ]]; then
          already_covered=true
          break
        fi
      done
      if $already_covered; then
        continue
      fi

      local current_sha
      current_sha=$(git -C "$git_root" rev-parse HEAD 2>/dev/null || echo "")

      if git_fetch_check "$git_root"; then
        local default_branch latest_sha changelog
        default_branch=$(git -C "$git_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
        default_branch="${default_branch:-main}"
        latest_sha=$(git -C "$git_root" rev-parse "origin/${default_branch}" 2>/dev/null || echo "")
        changelog=$(git_changelog "$git_root" "$current_sha" "origin/${default_branch}")

        local changelog_escaped
        changelog_escaped=$(escape_json "${changelog:-}")

        results=$(echo "$results" | jq \
          --arg n "$dir_name" \
          --arg cs "$current_sha" \
          --arg ls "$latest_sha" \
          --arg cl "$changelog_escaped" \
          '. + [{"name": $n, "type": "hook", "source_type": "git", "current_sha": $cs, "latest_sha": $ls, "changelog": $cl, "status": "update_available"}]')
      fi
    done
  fi

  echo "$results"
}

check_hooks
