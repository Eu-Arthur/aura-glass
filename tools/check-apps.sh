#!/usr/bin/env bash
# Assert aura-glass-apps manages VS Code and Obsidian styling and integrates with CLI.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/aura-glass"
APPS_BIN="$REPO_ROOT/bin/aura-glass-apps"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Check executable and help
[ -x "$APPS_BIN" ] || note "bin/aura-glass-apps is not executable"
out_help="$("$APPS_BIN" --help)" || note "aura-glass-apps --help failed"
[[ "$out_help" == *"aura-glass-apps"* ]] || note "--help missing aura-glass-apps"
[[ "$out_help" == *"vscode"* ]] || note "--help missing vscode"
[[ "$out_help" == *"obsidian"* ]] || note "--help missing obsidian"

# 2. Check snippet generation
out_snip_vsc="$("$APPS_BIN" snippet vscode)" || note "snippet vscode failed"
[[ "$out_snip_vsc" == *"workbench.colorCustomizations"* ]] || note "vscode snippet missing colorCustomizations"

out_snip_obs="$("$APPS_BIN" snippet obsidian)" || note "snippet obsidian failed"
[[ "$out_snip_obs" == *"workspace-leaf"* ]] || note "obsidian snippet missing workspace-leaf"

# 3. Test mock application environments
TMP_DIR="$(mktemp -d /tmp/aura-apps-test-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Mock VS Code
MOCK_CFG="$TMP_DIR/config"
mkdir -p "$MOCK_CFG/Code/User"
printf '{\n  "editor.fontSize": 14\n}\n' > "$MOCK_CFG/Code/User/settings.json"

XDG_CONFIG_HOME="$MOCK_CFG" "$APPS_BIN" apply vscode >/dev/null 2>&1 || note "apply vscode failed"
[ -f "$MOCK_CFG/Code/User/settings.json.aurabackup" ] || note "VS Code backup not created"
grep -q "workbench.colorCustomizations" "$MOCK_CFG/Code/User/settings.json" || note "colorCustomizations not injected"

XDG_CONFIG_HOME="$MOCK_CFG" "$APPS_BIN" revert vscode >/dev/null 2>&1 || note "revert vscode failed"
grep -qv "workbench.colorCustomizations" "$MOCK_CFG/Code/User/settings.json" || note "colorCustomizations not reverted"

# Mock Obsidian Vault
MOCK_VAULT="$TMP_DIR/vault"
mkdir -p "$MOCK_VAULT/.obsidian"
printf '{\n  "theme": "obsidian"\n}\n' > "$MOCK_VAULT/.obsidian/app.json"

AURA_GLASS_VAULT_DIR="$MOCK_VAULT" "$APPS_BIN" apply obsidian >/dev/null 2>&1 || note "apply obsidian failed"
[ -f "$MOCK_VAULT/.obsidian/snippets/aura-glass.css" ] || note "Obsidian snippet file not created"
grep -q "aura-glass" "$MOCK_VAULT/.obsidian/app.json" || note "Obsidian app.json missing snippet enablement"

AURA_GLASS_VAULT_DIR="$MOCK_VAULT" "$APPS_BIN" revert obsidian >/dev/null 2>&1 || note "revert obsidian failed"
[ ! -f "$MOCK_VAULT/.obsidian/snippets/aura-glass.css" ] || note "Obsidian snippet file not removed"

# 4. Check CLI delegation via aura-glass
out_cli="$("$CLI" apps --help)" || note "aura-glass apps delegation failed"
[[ "$out_cli" == *"aura-glass-apps"* ]] || note "CLI delegation missing aura-glass-apps"

out_cli_status="$("$CLI" apps status 2>&1)" || note "aura-glass apps status failed"
[[ "$out_cli_status" == *"Productivity Apps Glass Status"* ]] || note "CLI status output missing header"

if [ "$fail" -eq 1 ]; then
    printf 'check-apps.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-apps.sh: passed (VS Code & Obsidian styling, snippets, & CLI verified)\n'
