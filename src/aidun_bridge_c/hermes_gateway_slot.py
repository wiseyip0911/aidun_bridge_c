"""Hermes gateway 全局并行槽位：POST notify 前按 /health 的活跃 Agent 数节流。

与渠道无关：计数来自 gateway 进程内 ``_running_agent_count()``（含 Telegram
等所有入口触发的会话），需 Hermes webhook 的 ``GET /health`` 返回字段
``gateway_active_agents``（见 ``gateway/platforms/webhook.py``）。

环境变量（均在 ``KQ_POOL_`` 前缀下，便于与 bridge 其它项放同一 .env）：

- ``KQ_POOL_NOTIFY_MAX_GATEWAY_AGENTS``：全局上限，默认 ``3``；``0`` 表示不限制。
- ``KQ_POOL_GATEWAY_STATUS_URL``：可选，显式指定状态 URL（默认由 notify URL
  推导为同 host:port 的 ``/health``）。
- ``KQ_POOL_NOTIFY_GATEWAY_POLL_SEC``：等槽位时的轮询间隔，默认 ``1.0``。
- ``KQ_POOL_NOTIFY_GATEWAY_SLOT_MAX_WAIT_SEC``：单条 notify 最长等待秒数；
  留空表示一直等到有空槽；超时后会打 warning 并**仍尝试 POST**（避免任务
  永远挂住不落 notify）。
"""
from __future__ import annotations

import json
import logging
import os
import time
import urllib.error
import urllib.request
from typing import Any, Callable
from urllib.parse import urlparse, urlunparse

logger = logging.getLogger(__name__)

_warned_no_agent_field = False

_ORIG_NOTIFY_WEBHOOK: Callable[..., bool] | None = None


def max_gateway_agents() -> int:
    raw = (os.environ.get("KQ_POOL_NOTIFY_MAX_GATEWAY_AGENTS") or "").strip()
    if not raw:
        return 3
    try:
        v = int(raw, 10)
    except ValueError:
        return 3
    return max(0, v)


def gateway_status_health_url(*, notify_url: str | None = None) -> str | None:
    explicit = (os.environ.get("KQ_POOL_GATEWAY_STATUS_URL") or "").strip()
    if explicit:
        return explicit
    raw = (notify_url or (os.environ.get("KQ_POOL_NOTIFY_WEBHOOK_URL") or "").strip())
    if not raw:
        port = (os.environ.get("HERMES_GATEWAY_PORT") or "8644").strip()
        raw = f"http://127.0.0.1:{port}/webhooks/bridge-task"
    try:
        p = urlparse(raw)
        if not p.scheme or not p.netloc:
            return None
        return urlunparse((p.scheme, p.netloc, "/health", "", "", ""))
    except Exception:
        return None


def fetch_gateway_active_agents(health_url: str, *, timeout: float = 3.0) -> int | None:
    req = urllib.request.Request(health_url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        logger.warning("读取 gateway 状态失败 %s: %s", health_url, e)
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    v = data.get("gateway_active_agents")
    if isinstance(v, bool) or not isinstance(v, int):
        return None
    return max(0, v)


def wait_for_gateway_slot(*, notify_url: str | None = None) -> None:
    """在 notify POST 之前调用：阻塞直到 gateway 活跃数 < 上限或无法获知状态。"""
    global _warned_no_agent_field

    mx = max_gateway_agents()
    if mx <= 0:
        return

    health = gateway_status_health_url(notify_url=notify_url)
    if not health:
        return

    poll_raw = (os.environ.get("KQ_POOL_NOTIFY_GATEWAY_POLL_SEC") or "").strip()
    try:
        poll = float(poll_raw) if poll_raw else 1.0
    except ValueError:
        poll = 1.0
    poll = max(0.05, min(30.0, poll))

    max_wait_raw = (os.environ.get("KQ_POOL_NOTIFY_GATEWAY_SLOT_MAX_WAIT_SEC") or "").strip()
    deadline: float | None
    if max_wait_raw:
        try:
            deadline = time.monotonic() + max(0.0, float(max_wait_raw))
        except ValueError:
            deadline = None
    else:
        deadline = None

    while True:
        n = fetch_gateway_active_agents(health)
        if n is None:
            if not _warned_no_agent_field:
                logger.info(
                    "GET %s 未返回 gateway_active_agents，跳过全局并行限制"
                    "（请升级 Hermes webhook 平台）",
                    health,
                )
                _warned_no_agent_field = True
            return
        if n < mx:
            if n > 0:
                logger.debug("gateway 槽位 OK active=%s max=%s", n, mx)
            return
        if deadline is not None and time.monotonic() >= deadline:
            logger.warning(
                "gateway 槽位等待超时仍尝试 notify：active=%s max=%s",
                n,
                mx,
            )
            return
        logger.debug("gateway 槽位已满 active=%s max=%s，%.2fs 后再试", n, mx, poll)
        time.sleep(poll)


def install_daemon_notify_guard() -> None:
    """把 ``bridge_c_core.daemon.notify_webhook`` 包一层槽位等待（幂等）。"""
    global _ORIG_NOTIFY_WEBHOOK

    import bridge_c_core.daemon as dmod  # type: ignore[import-untyped]

    if getattr(dmod.notify_webhook, "__aidun_gateway_slot_wrapped__", False):
        return
    if _ORIG_NOTIFY_WEBHOOK is None:
        _ORIG_NOTIFY_WEBHOOK = dmod.notify_webhook

    def _wrapped(
        url: str,
        record: dict[str, Any],
        *,
        secret: str = "",
        timeout: float = 5.0,
        record_id: str = "",
    ) -> bool:
        assert _ORIG_NOTIFY_WEBHOOK is not None
        wait_for_gateway_slot(notify_url=url or None)
        return _ORIG_NOTIFY_WEBHOOK(
            url,
            record,
            secret=secret,
            timeout=timeout,
            record_id=record_id,
        )

    _wrapped.__aidun_gateway_slot_wrapped__ = True  # type: ignore[attr-defined]
    dmod.notify_webhook = _wrapped
