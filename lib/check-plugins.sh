#!/usr/bin/env bash
# Adapter: check installed CC plugins for updates
# Output: JSON array of update objects to stdout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

INSTALLED_FILE="${PLUGINS_DIR}/installed_plugins.json"
MARKETPLACES_DIR="${PLUGINS_DIR}/marketplaces"

check_plugins() {
  if [ ! -f "$INSTALLED_FILE" ]; then
    echo "[]"
    return
  fi

  local results="[]"
  local plugin_keys
  plugin_keys=$(jq -r '.plugins | keys[]' "$INSTALLED_FILE" 2>/dev/null)

  for key in $plugin_keys; do
    # key format: "name@marketplace"
    local name marketplace
    name="${key%%@*}"
    marketplace="${key##*@}"

    # Get installed info (use first entry — scope: user)
    local installed_version installed_sha install_path
    installed_version=$(jq -r ".plugins[\"${key}\"][0].version // \"unknown\"" "$INSTALLED_FILE")
    installed_sha=$(jq -r ".plugins[\"${key}\"][0].gitCommitSha // \"\"" "$INSTALLED_FILE")
    install_path=$(jq -r ".plugins[\"${key}\"][0].installPath // \"\"" "$INSTALLED_FILE")

    local marketplace_dir="${MARKETPLACES_DIR}/${marketplace}"
    if [ ! -d "$marketplace_dir" ]; then
      continue
    fi

    # Fetch latest from marketplace
    if ! run_timeout "$GIT_TIMEOUT" git -C "$marketplace_dir" fetch origin --quiet 2>/dev/null; then
      results=$(echo "$results" | jq --arg n "$name" --arg v "$installed_version" \
        '. + [{"name": $n, "current_version": $v, "status": "fetch_failed"}]')
      continue
    fi

    # Get the latest SHA for this plugin's directory in the marketplace
    local default_branch
    default_branch=$(git -C "$marketplace_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    default_branch="${default_branch:-main}"

    local latest_sha
    latest_sha=$(git -C "$marketplace_dir" rev-parse "origin/${default_branch}" 2>/dev/null || echo "")

    if [ -z "$latest_sha" ] || [ -z "$installed_sha" ]; then
      continue
    fi

    if [ "$installed_sha" = "$latest_sha" ]; then
      # Up to date
      continue
    fi

    # Update available — get changelog
    local changelog
    changelog=$(git -C "$marketplace_dir" log --oneline -n 5 "${installed_sha}..origin/${default_branch}" -- "plugins/${name}" 2>/dev/null || true)
    if [ -z "$changelog" ]; then
      changelog=$(git -C "$marketplace_dir" log --oneline -n 5 "${installed_sha}..origin/${default_branch}" 2>/dev/null || true)
    fi

    # Try to find latest version from plugin.json on remote
    local latest_version
    latest_version=$(git -C "$marketplace_dir" show "origin/${default_branch}:plugins/${name}/.claude-plugin/plugin.json" 2>/dev/null | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")

    local changelog_escaped
    changelog_escaped=$(escape_json "$changelog")

    results=$(echo "$results" | jq \
      --arg n "$name" \
      --arg cv "$installed_version" \
      --arg lv "$latest_version" \
      --arg cs "$installed_sha" \
      --arg ls "$latest_sha" \
      --arg cl "$changelog_escaped" \
      --arg ip "$install_path" \
      --arg mk "$marketplace" \
      '. + [{"name": $n, "type": "plugin", "current_version": $cv, "latest_version": $lv, "current_sha": $cs, "latest_sha": $ls, "changelog": $cl, "install_path": $ip, "marketplace": $mk, "status": "update_available"}]')
  done

  echo "$results"
}

check_plugins
