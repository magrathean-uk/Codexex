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
    "totalTokens": 0,
    "todayTokens": 0,
    "weekTokens": 0,
    "inputTokens": 0,
    "cachedInputTokens": 0,
    "outputTokens": 0,
    "projects": {},
    "models": {},
    "sessions": {},
}
latest_rate_limits = None
latest_context_window_percent = None

def iso_from_epoch(value):
    try:
        return datetime.fromtimestamp(float(value), timezone.utc).isoformat()
    except Exception:
        return None

def window_summary(window):
    if not isinstance(window, dict):
        return None
    return {
        "usedPercent": window.get("used_percent"),
        "windowMinutes": window.get("window_minutes"),
        "resetsAt": iso_from_epoch(window.get("resets_at")),
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
    turn_id = None
    command_counts_by_turn = {}
    session_id = os.path.splitext(os.path.basename(path))[0]
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for line in handle:
                try:
                    event = json.loads(line)
                except Exception:
                    continue
                payload = event.get("payload") or {}
                if event.get("type") == "session_meta":
                    session_id = payload.get("id") or session_id
                    cwd = payload.get("cwd") or cwd
                    model = payload.get("model") or model
                if event.get("type") == "turn_context":
                    turn_id = payload.get("turn_id") or turn_id
                    cwd = payload.get("cwd") or cwd
                    model = payload.get("model") or model
                if payload.get("type") == "exec_command_end":
                    current_turn = payload.get("turn_id") or turn_id
                    if current_turn:
                        command_counts_by_turn[current_turn] = command_counts_by_turn.get(current_turn, 0) + 1
                    cwd = payload.get("cwd") or cwd
                    continue
                if payload.get("type") != "token_count":
                    continue
                usage = ((payload.get("info") or {}).get("last_token_usage") or {})
                total = int(usage.get("total_tokens") or 0)
                if total <= 0:
                    continue
                totals["entries"] += 1
                totals["totalTokens"] += total
                input_tokens = int(usage.get("input_tokens") or 0)
                cached_input_tokens = int(usage.get("cached_input_tokens") or 0)
                output_tokens = int(usage.get("output_tokens") or 0)
                totals["inputTokens"] += input_tokens
                totals["cachedInputTokens"] += cached_input_tokens
                totals["outputTokens"] += output_tokens
                info = payload.get("info") or {}
                context_window = info.get("model_context_window")
                if context_window:
                    try:
                        latest_context_window_percent = min(100, (total / float(context_window)) * 100)
                    except Exception:
                        pass
                rate_limits = payload.get("rate_limits") or event.get("rate_limits")
                if isinstance(rate_limits, dict):
                    latest_rate_limits = rate_limits
                entry_turn = payload.get("turn_id") or turn_id
                command_count = command_counts_by_turn.get(entry_turn, 0)
                session = totals["sessions"].setdefault(session_id, {
                    "id": session_id,
                    "project": os.path.basename(cwd) if cwd else None,
                    "model": model or "unknown",
                    "entries": 0,
                    "commandCount": 0,
                    "totalTokens": 0,
                    "inputTokens": 0,
                    "cachedInputTokens": 0,
                    "outputTokens": 0,
                })
                session["entries"] += 1
                session["commandCount"] += command_count
                session["totalTokens"] += total
                session["inputTokens"] += input_tokens
                session["cachedInputTokens"] += cached_input_tokens
                session["outputTokens"] += output_tokens
                session["project"] = os.path.basename(cwd) if cwd else session["project"]
                session["model"] = model or session["model"]
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
sessions = sorted(totals["sessions"].values(), key=lambda item: item["totalTokens"], reverse=True)
session_autopsies = [
    {
        "id": session["id"],
        "project": session["project"],
        "model": session["model"],
        "entries": session["entries"],
        "commandCount": session["commandCount"],
        "totalTokens": session["totalTokens"],
        "cachedInputTokens": session["cachedInputTokens"],
        "outputTokens": session["outputTokens"],
        "totalSharePercent": round((session["totalTokens"] / totals["totalTokens"]) * 100, 1) if totals["totalTokens"] else 0,
    }
    for session in sessions[:5]
]
if totals["entries"] == 0:
    confidence = {"level": "unknown", "title": "Unknown confidence"}
elif any((session["project"] is None or session["model"] == "unknown") for session in sessions):
    confidence = {"level": "partial", "title": "Partial confidence"}
else:
    confidence = {"level": "high", "title": "High confidence"}
cache_hit_rate = (totals["cachedInputTokens"] / totals["inputTokens"]) if totals["inputTokens"] else 0
if totals["entries"] == 0:
    cache_pressure = {
        "level": "unknown",
        "cachedInputPercent": 0,
        "detail": "No token rows found.",
    }
elif totals["totalTokens"] >= 50000 and cache_hit_rate >= 0.65:
    cache_pressure = {
        "level": "high",
        "cachedInputPercent": round(cache_hit_rate * 100, 1),
        "detail": "Watch repeated cache reads.",
    }
elif cache_hit_rate >= 0.40:
    cache_pressure = {
        "level": "medium",
        "cachedInputPercent": round(cache_hit_rate * 100, 1),
        "detail": "Moderate cache reads.",
    }
else:
    cache_pressure = {
        "level": "low",
        "cachedInputPercent": round(cache_hit_rate * 100, 1),
        "detail": "Cache reads look normal.",
    }
waste_signals = []
if cache_pressure["level"] == "high":
    waste_signals.append({
        "id": "high-cache-read",
        "kind": "highCacheRead",
        "title": "High cache read",
        "detail": f'{round(cache_hit_rate * 100):.0f}% cached input. Watch repeated reads.',
    })
for session in sessions:
    if session["commandCount"] >= 10:
        waste_signals.append({
            "id": f'tool-loop-{session["id"]}',
            "kind": "toolLoop",
            "title": "Tool loop",
            "detail": f'{session["commandCount"]} shell/tool completions in one session.',
        })
        break
for session in sessions:
    if (
        "max" in session["model"].lower()
        and session["totalTokens"] >= 50000
        and (session["outputTokens"] / max(1, session["totalTokens"])) < 0.02
    ):
        waste_signals.append({
            "id": f'model-overkill-{session["model"]}',
            "kind": "modelOverkill",
            "title": "Model overkill",
            "detail": f'{session["model"]} spent {session["totalTokens"]} tokens for a small output.',
        })
        break
reset_windows = {
    "primary": window_summary((latest_rate_limits or {}).get("primary")),
    "secondary": window_summary((latest_rate_limits or {}).get("secondary")),
}
print(json.dumps({
    "provider": "codex",
    "sessionsPath": root,
    "entries": totals["entries"],
    "totalTokens": totals["totalTokens"],
    "todayTokens": totals["todayTokens"],
    "weekTokens": totals["weekTokens"],
    "inputTokens": totals["inputTokens"],
    "cachedInputTokens": totals["cachedInputTokens"],
    "outputTokens": totals["outputTokens"],
    "cacheReadPressure": cache_pressure,
    "wasteSignals": waste_signals,
    "resetWindows": reset_windows,
    "planType": (latest_rate_limits or {}).get("plan_type"),
    "contextWindowPercent": round(latest_context_window_percent, 1) if latest_context_window_percent is not None else None,
    "allSessions": len(sessions),
    "sessionAutopsies": session_autopsies,
    "attributionConfidence": confidence,
    "topProject": top_project[0],
    "topModel": top_model[0],
}, separators=(",", ":")))
PY
