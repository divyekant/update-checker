# update-checker

A Claude Code plugin that checks for updates to your installed plugins, MCP servers, and hooks.

## What it does

- **On session start (daily):** Silently checks for updates. If any found, shows a one-line summary in your session context.
- **On demand (`/check-updates`):** Shows detailed update info with changelogs and offers to apply updates.

## What it checks

| Component | Detection Method | Update Method |
|-----------|-----------------|---------------|
| Plugins (marketplace) | Compare installed SHA against marketplace remote | Pull marketplace, copy new version |
| MCP servers (git-backed) | `git fetch` the source repo | `git pull` |
| MCP servers (npm) | `npm view` latest version | Manual (reported only) |
| Hooks (git-backed) | `git fetch` the source repo | `git pull` |
| Local scripts | N/A | Reported as "untracked" |

## Install

```bash
# From the DK marketplace
claude plugins marketplace add divyekant/dk-marketplace
claude plugins install update-checker

# Or install directly from GitHub
claude plugins install github:divyekant/update-checker
```

## Usage

Updates are checked automatically once per day on session start. To check manually:

```
/check-updates
```

## Requirements

- `jq` (for JSON parsing)
- `git` (for version checking)
- `timeout` command (standard on macOS and Linux)
