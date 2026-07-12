#!/usr/bin/env python3
"""Block direct edits to the generated Xcode project."""

from __future__ import annotations

import json
import sys


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (TypeError, ValueError):
        return 0

    tool_input = payload.get("tool_input")
    command = str(tool_input.get("command", "")) if isinstance(tool_input, dict) else ""
    if ".xcodeproj/" not in command:
        return 0

    print(
        "BLOCKED: edit project.yml, then regenerate CodexMeter.xcodeproj with XcodeGen.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
