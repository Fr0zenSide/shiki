# Shikki Plugins

## Overview

Plugins extend Shikki with new commands, capabilities, and integrations. A plugin is a folder with a `manifest.json` and code.

## Quick Start

### Install a plugin
```bash
# From local path
shikki plugins install ./my-plugin/

# From GitHub (roadmap — not yet implemented)
# shikki plugins install github:obyw-one/creative-studio
```

### List installed plugins
```bash
shikki plugins list
```

### Verify a plugin
```bash
shikki plugins verify creative-studio
```

### Uninstall
```bash
shikki plugins uninstall creative-studio
```

## Building a Plugin

### 1. Create the structure

```
my-plugin/
  manifest.json     ← required
  Sources/           ← Swift code (optional)
  prompts/           ← skill prompts (optional)
  scripts/           ← bash/python (optional)
  README.md          ← documentation
```

### 2. Write manifest.json

```json
{
  "id": "your-name/plugin-name",
  "displayName": "My Plugin",
  "version": "0.1.0",
  "source": "local",
  "commands": [
    { "name": "mycommand", "description": "What this command does" }
  ],
  "capabilities": ["my-feature"],
  "dependencies": {
    "systemTools": [],
    "pythonPackages": [],
    "minimumDiskGB": 0,
    "minimumRAMGB": 0
  },
  "minimumShikkiVersion": "0.3.0",
  "author": "Your Name",
  "license": "AGPL-3.0",
  "description": "What this plugin does",
  "checksum": ""
}
```

### 3. Generate checksum

```bash
# Compute SHA-256 of your plugin directory (excluding .git)
find my-plugin -type f ! -path '*/.git/*' | sort | xargs shasum -a 256 | shasum -a 256
# Put the hash in manifest.json "checksum" field
```

### 4. Test locally

```bash
shikki plugins install ./my-plugin/
shikki plugins verify my-plugin
shikki mycommand  # your command works!
```

## Plugin Storage

Installed plugins live at `~/.shikki/plugins/` (created by `setup.sh` or auto-created on first install):

```
~/.shikki/plugins/
  obyw-one--creative-studio/
    manifest.json
    Sources/
    ...
```

## Certification

| Level | Meaning |
|-------|---------|
| uncertified | Local use, no review |
| communityReviewed | Published to registry, CI validated |
| shikkiCertified | Reviewed by Shikki team, GPG signed |
| enterpriseSafe | Full security audit + compliance |

## Sharing

### Via GitHub (roadmap — P2)
Push your plugin to a GitHub repo with `manifest.json` at the root.
When implemented: `shikki plugins install github:your-name/plugin-name`
See `features/shikki-plugin-marketplace.md` for the full distribution plan.

### Via Marketplace (coming soon)
Submit a PR to the `shikki-plugins/registry` repo.
After review, your plugin appears at `plugins.shikki.dev`.
