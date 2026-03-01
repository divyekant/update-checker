#!/usr/bin/env bash
# Adapter: check MCP servers for updates
# Output: JSON array of update objects to stdout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

MCP_FILE="${CLAUDE_DIR}/.mcp.json"

check_mcp() {
  if [ ! -f "$MCP_FILE" ]; then
    echo "[]"
    return
  fi

  local results="[]"
  local server_names
  server_names=$(jq -r '.mcpServers | keys[]' "$MCP_FILE" 2>/dev/null)

  for name in $server_names; do
    local command args_first
    command=$(jq -r ".mcpServers[\"${name}\"].command // \"\"" "$MCP_FILE")
    args_first=$(jq -r ".mcpServers[\"${name}\"].args[0] // \"\"" "$MCP_FILE")

    # Determine the path to inspect
    local check_path=""
    if [ -n "$args_first" ] && [ -e "$args_first" ]; then
      check_path="$args_first"
    elif [ -n "$args_first" ]; then
      # args_first might be a path that doesn't exist yet, try dirname
      local parent_dir
      parent_dir=$(dirname "$args_first" 2>/dev/null)
      if [ -d "$parent_dir" ]; then
        check_path="$parent_dir"
      fi
    fi

    # Detect source type
    local source_type="unknown"
    local status="untracked"
    local current_sha="" latest_sha="" changelog=""

    if [ -n "$check_path" ]; then
      local resolved_dir
      resolved_dir=$(resolve_dir "$check_path")

      if [ -n "$resolved_dir" ]; then
        local git_root
        git_root=$(find_git_root "$resolved_dir")

        if [ -n "$git_root" ]; then
          source_type="git"
          current_sha=$(git -C "$git_root" rev-parse HEAD 2>/dev/null || echo "")

          if git_fetch_check "$git_root"; then
            # Updates available
            local default_branch
            default_branch=$(git -C "$git_root" remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
            default_branch="${default_branch:-main}"
            latest_sha=$(git -C "$git_root" rev-parse "origin/${default_branch}" 2>/dev/null || echo "")
            changelog=$(git_changelog "$git_root" "$current_sha" "origin/${default_branch}")
            status="update_available"
          else
            status="up_to_date"
          fi
        fi
      fi
    fi

    # Check for npx-based servers
    if [ "$source_type" = "unknown" ] && [ "$command" = "npx" ]; then
      source_type="npm"
      local pkg_name="$args_first"
      # Strip any flags from package name
      pkg_name="${pkg_name##-*}"
      if [ -n "$pkg_name" ]; then
        local latest_npm_version
        latest_npm_version=$(timeout "$GIT_TIMEOUT" npm view "$pkg_name" version 2>/dev/null || echo "")
        if [ -n "$latest_npm_version" ]; then
          # For npx, we can't easily determine current version — just report latest
          status="check_manually"
          changelog="Latest npm version: ${latest_npm_version}"
        fi
      fi
    fi

    # Skip up-to-date entries
    if [ "$status" = "up_to_date" ]; then
      continue
    fi

    local changelog_escaped
    changelog_escaped=$(escape_json "${changelog:-}")

    results=$(echo "$results" | jq \
      --arg n "$name" \
      --arg st "$source_type" \
      --arg cs "$current_sha" \
      --arg ls "$latest_sha" \
      --arg cl "$changelog_escaped" \
      --arg s "$status" \
      '. + [{"name": $n, "type": "mcp", "source_type": $st, "current_sha": $cs, "latest_sha": $ls, "changelog": $cl, "status": $s}]')
  done

  echo "$results"
}

check_mcp
