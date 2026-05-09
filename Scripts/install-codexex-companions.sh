#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
codex_home="${CODEX_HOME:-$HOME/.codex}"
hooks_path="$codex_home/hooks.json"
config_path="$codex_home/config.toml"
mkdir -p "$codex_home"

if [[ -f "$hooks_path" ]]; then
  cp "$hooks_path" "$hooks_path.codexex-backup-$(date +%Y%m%d%H%M%S)"
fi
if [[ -f "$config_path" ]] && ! grep -q '^codex_hooks *= *true' "$config_path"; then
  cp "$config_path" "$config_path.codexex-backup-$(date +%Y%m%d%H%M%S)"
fi

python3 - "$hooks_path" "$repo_root" <<'PY'
import json
import sys
from pathlib import Path

hooks_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2])
command = str(repo_root / "Scripts" / "codexex-hook-event.sh")

if hooks_path.exists():
    try:
        data = json.loads(hooks_path.read_text(encoding="utf-8"))
    except Exception:
        data = {}
else:
    data = {}

hooks = data.setdefault("hooks", {})

def entry(event):
    return [{
        "matcher": "*",
        "hooks": [{
            "type": "command",
            "command": f"{command} {event.lower()}"
        }]
    }]

for event in ["SessionStart", "PermissionRequest", "PostToolUse", "Stop"]:
    hooks[event] = entry(event)

hooks_path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

if [[ -f "$config_path" ]]; then
  if ! grep -q '^\[features\]' "$config_path"; then
    printf '\n[features]\ncodex_hooks = true\n' >> "$config_path"
  elif ! grep -q '^codex_hooks *= *true' "$config_path"; then
    printf '\ncodex_hooks = true\n' >> "$config_path"
  fi
fi

echo "Codexex companions installed in $hooks_path"
