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

mkdir -p "$tmp_dir/sessions"
cat >"$tmp_dir/sessions/session-1.jsonl" <<'JSONL'
{"timestamp":"2026-05-06T09:00:00.000Z","type":"session_meta","payload":{"id":"session-1","cwd":"/tmp/Codexex"}}
{"timestamp":"2026-05-06T09:01:00.000Z","type":"turn_context","payload":{"turn_id":"turn-1","cwd":"/tmp/Codexex","model":"gpt-5.1-codex-max"}}
{"timestamp":"2026-05-06T09:01:01.000Z","type":"event_msg","payload":{"type":"exec_command_end","turn_id":"turn-1","cwd":"/tmp/Codexex"}}
{"timestamp":"2026-05-06T09:01:02.000Z","type":"event_msg","payload":{"type":"exec_command_end","turn_id":"turn-1","cwd":"/tmp/Codexex"}}
{"timestamp":"2026-05-06T09:01:03.000Z","type":"event_msg","payload":{"type":"exec_command_end","turn_id":"turn-1","cwd":"/tmp/Codexex"}}
{"timestamp":"2026-05-06T09:01:04.000Z","type":"event_msg","payload":{"type":"exec_command_end","turn_id":"turn-1","cwd":"/tmp/Codexex"}}
{"timestamp":"2026-05-06T09:01:05.000Z","type":"event_msg","payload":{"type":"exec_command_end","turn_id":"turn-1","cwd":"/tmp/Codexex"}}
{"timestamp":"2026-05-06T09:01:06.000Z","type":"event_msg","payload":{"type":"exec_command_end","turn_id":"turn-1","cwd":"/tmp/Codexex"}}
{"timestamp":"2026-05-06T09:01:07.000Z","type":"event_msg","payload":{"type":"exec_command_end","turn_id":"turn-1","cwd":"/tmp/Codexex"}}
{"timestamp":"2026-05-06T09:01:08.000Z","type":"event_msg","payload":{"type":"exec_command_end","turn_id":"turn-1","cwd":"/tmp/Codexex"}}
{"timestamp":"2026-05-06T09:01:09.000Z","type":"event_msg","payload":{"type":"exec_command_end","turn_id":"turn-1","cwd":"/tmp/Codexex"}}
{"timestamp":"2026-05-06T09:01:09.500Z","type":"event_msg","payload":{"type":"exec_command_end","turn_id":"turn-1","cwd":"/tmp/Codexex"}}
{"timestamp":"2026-05-06T09:01:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":50000,"cached_input_tokens":40000,"output_tokens":300,"reasoning_output_tokens":40,"total_tokens":52000},"model_context_window":1000000}},"rate_limits":{"primary":{"used_percent":22.5,"window_minutes":300,"resets_at":1778079600},"secondary":{"used_percent":41.0,"window_minutes":10080,"resets_at":1778684400},"plan_type":"pro"}}
JSONL

status_json="$(CODEXEX_SESSIONS_DIR="$tmp_dir/sessions" "$repo_root/Scripts/codexex-status.sh")"
python3 - "$status_json" <<'PY'
import json
import sys

status = json.loads(sys.argv[1])
assert status["totalTokens"] == 52000
assert status["allSessions"] == 1
assert status["sessionAutopsies"][0]["id"] == "session-1"
assert status["sessionAutopsies"][0]["project"] == "Codexex"
assert status["sessionAutopsies"][0]["commandCount"] == 10
assert status["attributionConfidence"]["level"] == "high"
assert status["cacheReadPressure"]["level"] == "high"
assert status["wasteSignals"][0]["kind"] == "highCacheRead"
assert status["wasteSignals"][1]["kind"] == "toolLoop"
assert status["wasteSignals"][2]["kind"] == "modelOverkill"
assert status["resetWindows"]["primary"]["usedPercent"] == 22.5
assert status["resetWindows"]["primary"]["resetsAt"] == "2026-05-06T15:00:00+00:00"
assert status["resetWindows"]["secondary"]["windowMinutes"] == 10080
assert status["planType"] == "pro"
assert status["contextWindowPercent"] == 5.2
PY

echo "Codexex companion checks passed"
