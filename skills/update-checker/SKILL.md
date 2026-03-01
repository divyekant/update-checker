---
description: "Check for updates to installed CC plugins, MCP servers, and hooks. Shows available updates with changelogs and offers to apply them."
---

# Update Checker

You are the update-checker skill. When invoked, check all installed CC components for available updates and help the user update them.

## Process

### Step 1: Run Checks

Run the adapter scripts to detect available updates. Execute these three commands and collect their JSON output:

```bash
PLUGIN_ROOT="$(cd "$(dirname "$(find ~/.claude/plugins/cache -name 'update-checker' -type d -path '*/.claude-plugin/..' 2>/dev/null | head -1)")" 2>/dev/null && pwd)"
bash "${PLUGIN_ROOT}/lib/check-plugins.sh"
bash "${PLUGIN_ROOT}/lib/check-mcp.sh"
bash "${PLUGIN_ROOT}/lib/check-hooks.sh"
```

If PLUGIN_ROOT can't be found, ask the user for the install path.

### Step 2: Present Findings

Organize results into three categories:

**Updates available:**
List each component with current version, latest version, and changelog summary.
Format: `- [name] [current] → [latest] — [changelog first line]`

**Untracked (no upstream):**
List components where source couldn't be determined.
Format: `- [name] ([type]) — local source, can't check for updates`

**Up to date:**
Just state the count: "N components are current."

### Step 3: Offer Action

If updates are available, ask the user:
"Update all / Pick which to update / Skip?"

### Step 4: Execute Updates

For each component the user approves:

**Plugins:**
1. Create backup: `cp -r [install_path] [install_path].backup`
2. In the marketplace repo, pull latest: `git -C ~/.claude/plugins/marketplaces/[marketplace] pull origin [branch]`
3. Copy new version to cache (determine new version from plugin.json on the pulled branch)
4. Update installed_plugins.json with new version, SHA, and timestamp
5. Report: "Updated [name] from [old] to [new]"

**MCP servers (git-backed):**
1. Record current SHA for rollback
2. `git -C [repo_root] pull origin [branch]`
3. If the MCP server uses npm: `cd [repo_root] && npm install`
4. Report: "Updated [name] — pulled [N] new commits"

**Hooks (git-backed):**
1. Record current SHA for rollback
2. `git -C [repo_root] pull origin [branch]`
3. Report: "Updated [name] hooks"

### Step 5: Rollback (if requested)

If the user says "rollback" or something went wrong:

**Plugins:** `mv [install_path].backup [install_path]` and restore installed_plugins.json
**MCP/Hooks:** `git -C [repo_root] reset --hard [saved_sha]`

Always confirm before executing rollback: "Roll back [name] to previous version?"

## Important

- Never auto-update. Always show what's available and ask first.
- Always create backups before updating plugins.
- If a git fetch fails (network issue), report it but continue checking other components.
- Reset the throttle file after a manual check so the daily auto-check timer restarts.
- After updates, suggest the user restart their Claude Code session for changes to take effect.
