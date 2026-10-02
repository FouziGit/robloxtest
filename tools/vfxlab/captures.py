#!/usr/bin/env python3
"""Pulls the Studio screen captures of a Claude Code session out of its transcript, as image files.

The Roblox Studio MCP's screen_capture returns the image to the agent but writes nothing to disk, and a
sandboxed shell cannot record the screen. The session transcript (a JSONL file) keeps every tool result,
images included, so a capture taken with a capture_id can be recovered by that id.

    python3 tools/vfxlab/captures.py <transcript.jsonl> <out_dir> <capture_id> [<capture_id> ...]

Each capture is written as <out_dir>/<capture_id>.<jpg|png>; the latest capture wins when an id was used
twice. Prints the files written and the ids it could not find.
"""

from __future__ import annotations

import base64
import json
import sys
from pathlib import Path

EXTENSIONS = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}


def find(transcript: Path, wanted: set[str]) -> dict[str, tuple[str, bytes]]:
    """capture_id -> (media type, bytes), the last one of each id in the transcript."""
    tool_ids: dict[str, str] = {}
    found: dict[str, tuple[str, bytes]] = {}
    with transcript.open() as handle:
        for line in handle:
            if "screen_capture" not in line and '"tool_result"' not in line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            message = record.get("message")
            content = message.get("content") if isinstance(message, dict) else None
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_use" and str(block.get("name", "")).endswith("screen_capture"):
                    capture = (block.get("input") or {}).get("capture_id")
                    if capture in wanted:
                        tool_ids[block.get("id")] = capture
                elif block.get("type") == "tool_result" and block.get("tool_use_id") in tool_ids:
                    parts = block.get("content")
                    for part in parts if isinstance(parts, list) else []:
                        source = part.get("source") if isinstance(part, dict) else None
                        if part.get("type") == "image" and isinstance(source, dict) and source.get("data"):
                            found[tool_ids[block["tool_use_id"]]] = (
                                source.get("media_type", "image/jpeg"),
                                base64.b64decode(source["data"]),
                            )
    return found


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        raise SystemExit(__doc__)
    transcript, out = Path(argv[1]), Path(argv[2])
    wanted = set(argv[3:])
    out.mkdir(parents=True, exist_ok=True)
    found = find(transcript, wanted)
    for capture, (media, data) in sorted(found.items()):
        path = out / f"{capture}.{EXTENSIONS.get(media, 'jpg')}"
        path.write_bytes(data)
        print(f"WROTE {path}")
    missing = sorted(wanted - set(found))
    for capture in missing:
        print(f"MISSING {capture}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
