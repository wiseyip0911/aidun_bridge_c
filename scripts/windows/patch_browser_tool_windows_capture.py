"""Patch Hermes tools/browser_tool.py for Windows subprocess capture decoding.

Invoked by Apply-HermesWindowsAgentMandatoryFixes.ps1 when the live tree lacks
the import + read_subprocess_capture_file usage for agent-browser stdout/stderr.
"""
from __future__ import annotations

import sys
from pathlib import Path

IMPORT_LINE = "from hermes_platform_paths import read_subprocess_capture_file\n"
ANCHOR = "from hermes_cli.config import cfg_get\n"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_browser_tool_windows_capture.py <path-to-browser_tool.py>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"missing file: {path}", file=sys.stderr)
        return 1
    text = path.read_text(encoding="utf-8")
    if "from hermes_platform_paths import read_subprocess_capture_file" in text and (
        "read_subprocess_capture_file(stdout_path)" in text
        or "read_subprocess_capture_file(stdout_path).strip()" in text
    ):
        return 0

    if IMPORT_LINE in text:
        return 0

    if ANCHOR not in text:
        print("browser_tool.py: anchor import not found; manual merge required", file=sys.stderr)
        return 1

    text = text.replace(ANCHOR, ANCHOR + IMPORT_LINE, 1)

    # Common upstream: Path(stdout_path).read_text(encoding="utf-8")...
    text = text.replace(
        "Path(stdout_path).read_text(encoding=\"utf-8\").strip()",
        "read_subprocess_capture_file(stdout_path).strip()",
    )
    text = text.replace(
        "Path(stderr_path).read_text(encoding=\"utf-8\").strip()",
        "read_subprocess_capture_file(stderr_path).strip()",
    )
    text = text.replace(
        "Path(stdout_path).read_text(encoding=\"utf-8\")",
        "read_subprocess_capture_file(stdout_path)",
    )
    text = text.replace(
        "Path(stderr_path).read_text(encoding=\"utf-8\")",
        "read_subprocess_capture_file(stderr_path)",
    )

    if "read_subprocess_capture_file(stdout_path)" not in text:
        print(
            "browser_tool.py: no stdout_path capture lines matched; file unchanged after import",
            file=sys.stderr,
        )
        return 1

    path.write_text(text, encoding="utf-8", newline="\n")
    print(f"patched: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
