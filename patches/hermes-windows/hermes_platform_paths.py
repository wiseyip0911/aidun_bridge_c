# AIDUN_BRIDGE_C_WINDOWS_MANDATORY_PATCH v1
"""Host path normalization for Windows (Git Bash / MSYS -> native Python paths).

Import-safe: no dependencies on tools/ or gateway/.
"""

from __future__ import annotations

import os
import re
import sys
from typing import Optional

_MSYS_DRIVE = re.compile(r"^/([a-zA-Z])/(.*)$")
_MSYS_CYGDRIVE = re.compile(r"^/(?:cygdrive|mnt)/([a-zA-Z])/(.*)$")


def is_windows() -> bool:
    return sys.platform == "win32"


def normalize_host_path(path: Optional[str]) -> Optional[str]:
    """Translate ``/d/foo`` or ``/cygdrive/d/foo`` to ``D:\\foo`` for Python/stdlib."""
    if not path:
        return path
    if not is_windows():
        return path
    p = os.path.expanduser(path)
    m = _MSYS_DRIVE.match(p)
    if m:
        rest = (m.group(2) or "").replace("/", "\\")
        return f"{m.group(1).upper()}:\\{rest}" if rest else f"{m.group(1).upper()}:\\"
    m = _MSYS_CYGDRIVE.match(p)
    if m:
        rest = (m.group(2) or "").replace("/", "\\")
        return f"{m.group(1).upper()}:\\{rest}" if rest else f"{m.group(1).upper()}:\\"
    return p


def apply_terminal_cwd_env() -> str:
    """Normalize ``TERMINAL_CWD`` in ``os.environ``; return the effective value."""
    raw = os.environ.get("TERMINAL_CWD", "")
    if not raw or raw in {".", "auto", "cwd"}:
        return raw
    norm = normalize_host_path(raw)
    if norm:
        os.environ["TERMINAL_CWD"] = norm
    return os.environ.get("TERMINAL_CWD", "")


def popen_cwd(path: str) -> str:
    """``cwd=`` for ``subprocess.Popen`` on Windows."""
    return normalize_host_path(path) or path


def read_subprocess_capture_file(path: str) -> str:
    """Read a temp stdout/stderr file from ``subprocess`` with tolerant decoding.

    On Windows, child processes often emit the system code page (e.g. GBK) while
    Hermes historically assumed UTF-8. Try UTF-8 first, then locale/CP936, then
    replacement so browser/CLI tools never crash mid-read.
    """
    from pathlib import Path

    raw = Path(path).read_bytes()
    if not raw:
        return ""
    candidates: list[str] = ["utf-8", "utf-8-sig"]
    if is_windows():
        candidates.extend(["gbk", "cp936"])
    try:
        import locale

        pref = locale.getpreferredencoding(False)
        if pref and pref.lower() not in {c.lower() for c in candidates}:
            candidates.append(pref)
    except Exception:
        pass
    for enc in candidates:
        try:
            return raw.decode(enc)
        except (UnicodeDecodeError, LookupError):
            continue
    return raw.decode("utf-8", errors="replace")
