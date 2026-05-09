#!/usr/bin/env bash
set -euo pipefail

sessions_dir="${CODEXEX_SESSIONS_DIR:-${CODEX_HOME:-$HOME/.codex}/sessions}"
max_files="${CODEXEX_STATUS_MAX_FILES:-120}"

python3 - "$sessions_dir" "$max_files" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

root = sys.argv[1]
try:
    max_files = max(1, int(sys.argv[2]))
except Exception:
    max_files = 120
today = datetime.now(timezone.utc).date()
totals = {
    "entries": 0,
    "todayTokens": 0,
    "weekTokens": 0,
    "cachedInputTokens": 0,
    "outputTokens": 0,
    "projects": {},
    "models": {},
}

paths = []
for base, _, files in os.walk(root):
    for name in files:
        if not name.endswith(".jsonl"):
            continue
        path = os.path.join(base, name)
        try:
            paths.append((os.path.getmtime(path), os.path.getsize(path), path))
        except OSError:
            continue

paths.sort(key=lambda item: (item[0], item[1], item[2]), reverse=True)

for _, _, path in paths[:max_files]:
    cwd = None
    model = None
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for line in handle:
                try:
                    event = json.loads(line)
                except Exception:
                    continue
                payload = event.get("payload") or {}
                if event.get("type") in ("session_meta", "turn_context"):
                    cwd = payload.get("cwd") or cwd
                    model = payload.get("model") or model
                if payload.get("type") != "token_count":
                    continue
                usage = ((payload.get("info") or {}).get("last_token_usage") or {})
                total = int(usage.get("total_tokens") or 0)
                if total <= 0:
                    continue
                totals["entries"] += 1
                totals["cachedInputTokens"] += int(usage.get("cached_input_tokens") or 0)
                totals["outputTokens"] += int(usage.get("output_tokens") or 0)
                stamp = event.get("timestamp")
                if stamp:
                    try:
                        day = datetime.fromisoformat(stamp.replace("Z", "+00:00")).date()
                    except Exception:
                        day = None
                    if day == today:
                        totals["todayTokens"] += total
                    if day and (today - day).days < 7:
                        totals["weekTokens"] += total
                if cwd:
                    totals["projects"][os.path.basename(cwd)] = totals["projects"].get(os.path.basename(cwd), 0) + total
                if model:
                    totals["models"][model] = totals["models"].get(model, 0) + total
    except OSError:
        continue

top_project = max(totals["projects"].items(), key=lambda item: item[1], default=(None, 0))
top_model = max(totals["models"].items(), key=lambda item: item[1], default=(None, 0))
print(json.dumps({
    "provider": "codex",
    "sessionsPath": root,
    "entries": totals["entries"],
    "todayTokens": totals["todayTokens"],
    "weekTokens": totals["weekTokens"],
    "cachedInputTokens": totals["cachedInputTokens"],
    "outputTokens": totals["outputTokens"],
    "topProject": top_project[0],
    "topModel": top_model[0],
}, separators=(",", ":")))
PY
