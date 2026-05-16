"""模拟连续 10 次 bridge-task notify，观察槽位等待与 /health 活跃数。

用法（在仓库根）::

    py -3 scripts/simulate_bridge_notify_burst.py

依赖：已安装本包 ``pip install -e .``，且 .env 中 notify URL / secret 与守护一致。
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import sys
import time
import uuid
import urllib.error
import urllib.request
from pathlib import Path

_REPO = Path(__file__).resolve().parents[1]
_SRC = _REPO / "src"
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))


def _load_dotenv() -> None:
    try:
        from dotenv import load_dotenv  # type: ignore

        load_dotenv(_REPO / ".env", override=False)
    except Exception:
        pass


def _notify_url() -> str:
    raw = (os.environ.get("KQ_POOL_NOTIFY_WEBHOOK_URL") or "").strip()
    if raw:
        return raw
    port = (os.environ.get("HERMES_GATEWAY_PORT") or "8644").strip()
    return f"http://127.0.0.1:{port}/webhooks/bridge-task"


def _health_url(notify_url: str) -> str:
    from urllib.parse import urlparse, urlunparse

    p = urlparse(notify_url)
    return urlunparse((p.scheme, p.netloc, "/health", "", "", ""))


def _get_active(notify_url: str) -> int | None:
    hu = _health_url(notify_url)
    req = urllib.request.Request(hu, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    v = data.get("gateway_active_agents")
    return int(v) if isinstance(v, int) else None


def _post_notify(notify_url: str, record_id: str, *, timeout: float = 15.0) -> tuple[int, str]:
    secret = (os.environ.get("KQ_POOL_NOTIFY_WEBHOOK_SECRET") or "").strip()
    body = json.dumps({"record_id": record_id}, ensure_ascii=False).encode("utf-8")
    headers: dict[str, str] = {
        "Content-Type": "application/json",
        "X-Request-ID": record_id,
    }
    if secret and secret != "INSECURE_NO_AUTH":
        headers["X-Hub-Signature-256"] = (
            "sha256=" + hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()
        )
    req = urllib.request.Request(notify_url, data=body, method="POST", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, ""
    except urllib.error.HTTPError as e:
        return e.code, (e.read() or b"").decode("utf-8", errors="replace")[:200]
    except urllib.error.URLError as e:
        return -1, str(e)


def main() -> int:
    _load_dotenv()
    from aidun_bridge_c.hermes_gateway_slot import wait_for_gateway_slot

    notify_url = _notify_url()
    if not notify_url:
        print("未配置 KQ_POOL_NOTIFY_WEBHOOK_URL 且无法推导默认 URL", file=sys.stderr)
        return 2

    mx = (os.environ.get("KQ_POOL_NOTIFY_MAX_GATEWAY_AGENTS") or "(默认3)").strip() or "3"
    print(f"notify_url = {notify_url}")
    print(f"KQ_POOL_NOTIFY_MAX_GATEWAY_AGENTS = {mx}")
    print("--- 开始 10 次：每次先等槽位(wait_for_gateway_slot)，再 POST ---\n")

    for i in range(1, 11):
        rid = f"sim-{uuid.uuid4().hex[:24]}"
        t_wall = time.strftime("%H:%M:%S")
        before = _get_active(notify_url)
        t0 = time.perf_counter()
        wait_for_gateway_slot(notify_url=notify_url)
        t_wait = time.perf_counter() - t0
        mid = _get_active(notify_url)
        t1 = time.perf_counter()
        code, err = _post_notify(notify_url, rid)
        t_post = time.perf_counter() - t1
        after = _get_active(notify_url)
        extra = f" err={err!r}" if err else ""
        print(
            f"[{t_wall}] #{i:2d} rid={rid[:20]}… "
            f"active(before/wait_end/after)={before}/{mid}/{after} "
            f"wait={t_wait:.2f}s post={t_post:.2f}s http={code}{extra}"
        )
        sys.stdout.flush()

    print("\n--- 结束（sim-* 会在 Hermes 侧产生会话，可按需自行清理）---")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
