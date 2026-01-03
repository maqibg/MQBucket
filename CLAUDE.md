# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MQBucket is a Scoop bucket repository for Windows package management. Scoop is a command-line installer for Windows, and this bucket contains application manifests (JSON files) that define how to install, update, and uninstall various applications.

## Repository Structure

```
bucket/           # App manifests (*.json) - one file per application
bin/              # PowerShell wrapper scripts for Scoop maintenance tools
scripts/          # Shared PowerShell utilities (AppsUtils.psm1)
deprecated/       # Retired manifests kept for reference
.github/          # CI workflows and issue/PR templates
```

## Common Commands

All commands should be run from Git Bash, invoking PowerShell as needed:

```bash
# Run Pester-based bucket validation tests
pwsh -File bin/test.ps1

# Format all manifest JSON files (run before committing)
pwsh -File bin/formatjson.ps1

# Check for broken URLs in manifests
pwsh -File bin/checkurls.ps1

# Check for hash mismatches
pwsh -File bin/checkhashes.ps1

# Check for new versions (use -? for options)
pwsh -File bin/checkver.ps1 -?
pwsh -File bin/checkver.ps1 <app-name>
pwsh -File bin/checkver.ps1 *

# Smoke test: install an app locally
scoop bucket add mqbucket <path-to-repo>
scoop install mqbucket/<app>
```

## Manifest Structure

Manifests are JSON files in `bucket/` directory. Key fields:

- `version`: Current version string
- `description`: Brief app description
- `homepage`: Project homepage URL
- `license`: License identifier or object with `identifier` field
- `architecture`: Download URLs and hashes per architecture (64bit, 32bit, arm64)
- `checkver`: Version checking configuration (typically `{"github": "https://github.com/..."}`)
- `autoupdate`: URL patterns for automatic updates
- `persist`: Files/directories to preserve across updates
- `shortcuts`: Desktop/start menu shortcuts
- `pre_install`/`post_install`: Installation scripts
- `bin`: Executables to add to PATH

Use `bucket/app-name.json.template` as a starting point for new manifests.

## Utilities Module (scripts/AppsUtils.psm1)

Provides helper functions for complex manifest scripts:

- `Mount-ExternalRuntimeData $Source $Target`: Create junction links for persistent data
- `Dismount-ExternalRuntimeData $Target`: Remove junction links
- `Invoke-ExternalCommand2`: Enhanced external command execution with logging

## Coding Standards

- Follow `.editorconfig`: UTF-8, CRLF, 4-space indent (2-space for YAML)
- Always run `bin/formatjson.ps1` before committing manifest changes
- Keep one app per manifest file, filename matches canonical app name
- Update `hash` field whenever changing download URLs

## Commit Message Format

```
<app-name>: Update to version <x.y.z>
```

Keep one app/version bump per commit when possible.

## Testing Requirements

- Framework: Pester 5 (requires PowerShell 5.1+ with BuildHelpers and Pester modules)
- CI runs tests on both Windows PowerShell and PowerShell Core
- Run `bin/test.ps1` locally before submitting PRs
- Excavator workflow auto-updates manifests every 4 hours via GitHub Actions

## Key Patterns

1. **GitHub-based version checking**: Most manifests use `"checkver": {"github": "https://github.com/owner/repo"}` for automatic version detection

2. **Persistent data**: Use `persist` array for config files and data directories that should survive updates

3. **Junction links**: For apps that require data in specific locations, use the `Mount-ExternalRuntimeData` function from AppsUtils.psm1

4. **Multi-architecture support**: Define separate URLs/hashes under `architecture.64bit`, `architecture.32bit`, `architecture.arm64`
