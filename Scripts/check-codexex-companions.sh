#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$repo_root/Scripts/codexex-status.sh"
bash -n "$repo_root/Scripts/codexex-hook-event.sh"
bash -n "$repo_root/Scripts/install-codexex-companions.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

sample='{"session_id":"s","turn_id":"t","cwd":"/tmp/Codexex","tool_name":"Bash","status":"completed"}'
printf '%s\n' "$sample" | CODEXEX_HOOK_LOG_DIR="$tmp_dir" "$repo_root/Scripts/codexex-hook-event.sh" PostToolUse

python3 - "$tmp_dir" <<'PY'
import json
import pathlib
import sys

files = list(pathlib.Path(sys.argv[1]).glob("*.jsonl"))
assert len(files) == 1
event = json.loads(files[0].read_text(encoding="utf-8").strip())
assert event["event"] == "PostToolUse"
assert event["cwd"] == "/tmp/Codexex"
assert event["tool"] == "Bash"
PY

CODEXEX_SESSIONS_DIR="$tmp_dir/empty" "$repo_root/Scripts/codexex-status.sh" >/dev/null
echo "Codexex companion checks passed"
