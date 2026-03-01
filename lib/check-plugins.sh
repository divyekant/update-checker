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

    # Determine if plugin is external (own git repo) vs marketplace-native
    # External plugins have their own .git with a remote different from the marketplace
    local repo_dir default_branch is_external="false"

    if [ -n "$install_path" ] && [ -d "${install_path}/.git" ]; then
      local plugin_remote marketplace_remote
      plugin_remote=$(git -C "$install_path" remote get-url origin 2>/dev/null || echo "")
      marketplace_remote=$(git -C "$marketplace_dir" remote get-url origin 2>/dev/null || echo "")
      if [ -n "$plugin_remote" ] && [ "$plugin_remote" != "$marketplace_remote" ]; then
        is_external="true"
        repo_dir="$install_path"
      fi
    fi

    if [ "$is_external" = "false" ]; then
      repo_dir="$marketplace_dir"
    fi

    # Fetch latest from the correct repo
    if ! run_timeout "$GIT_TIMEOUT" git -C "$repo_dir" fetch origin --quiet 2>/dev/null; then
      results=$(echo "$results" | jq --arg n "$name" --arg v "$installed_version" \
        '. + [{"name": $n, "current_version": $v, "status": "fetch_failed"}]')
      continue
    fi

    # Get default branch and latest SHA from the correct repo
    default_branch=$(git -C "$repo_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    default_branch="${default_branch:-main}"

    local latest_sha
    latest_sha=$(git -C "$repo_dir" rev-parse "origin/${default_branch}" 2>/dev/null || echo "")

    if [ -z "$latest_sha" ] || [ -z "$installed_sha" ]; then
      continue
    fi

    if [ "$installed_sha" = "$latest_sha" ]; then
      # Up to date
      continue
    fi

    # Update available — get changelog and latest version from the correct source
    local changelog latest_version

    if [ "$is_external" = "true" ]; then
      # External: changelog and version from the plugin's own repo
      changelog=$(git -C "$repo_dir" log --oneline -n 5 "${installed_sha}..origin/${default_branch}" 2>/dev/null || true)
      latest_version=$(git -C "$repo_dir" show "origin/${default_branch}:.claude-plugin/plugin.json" 2>/dev/null | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")
    else
      # Marketplace-native: scope changelog to plugin subdirectory
      changelog=$(git -C "$repo_dir" log --oneline -n 5 "${installed_sha}..origin/${default_branch}" -- "plugins/${name}" 2>/dev/null || true)
      if [ -z "$changelog" ]; then
        changelog=$(git -C "$repo_dir" log --oneline -n 5 "${installed_sha}..origin/${default_branch}" 2>/dev/null || true)
      fi
      latest_version=$(git -C "$repo_dir" show "origin/${default_branch}:plugins/${name}/.claude-plugin/plugin.json" 2>/dev/null | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")
    fi

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
