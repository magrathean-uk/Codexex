#!/usr/bin/env bash
set -euo pipefail

event_name="${1:-unknown}"
output_dir="${CODEXEX_HOOK_LOG_DIR:-$HOME/Library/Application Support/Codexex/hooks}"
mkdir -p "$output_dir"
raw_input="$(cat)"

HOOK_PAYLOAD="$raw_input" python3 - "$event_name" "$output_dir" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

event_name = sys.argv[1]
output_dir = sys.argv[2]
raw = os.environ.get("HOOK_PAYLOAD", "")

try:
    payload = json.loads(raw) if raw.strip() else {}
except Exception:
    payload = {"parse_error": True}

safe = {
    "captured_at": datetime.now(timezone.utc).isoformat(),
    "event": event_name,
    "cwd": payload.get("cwd") or payload.get("project_dir") or payload.get("workspace"),
    "tool": payload.get("tool_name") or payload.get("tool"),
    "session_id": payload.get("session_id") or payload.get("sessionId"),
    "turn_id": payload.get("turn_id") or payload.get("turnId"),
    "status": payload.get("status"),
}

path = os.path.join(output_dir, f"{datetime.now(timezone.utc).date().isoformat()}.jsonl")
with open(path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(safe, separators=(",", ":")) + "\n")
PY
