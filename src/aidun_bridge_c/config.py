from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from getpass import getpass


def _env(name: str, default: str = "") -> str:
    v = os.getenv(name, "").strip()
    return v if v else default


@dataclass
class Settings:
    bridge_base_url: str
    api_key: str
    instance_id: str
    poll_interval_sec: float
    pull_limit: int
    local_pool_dir: str
    request_timeout_sec: float


def load_settings(*, interactive: bool = True) -> Settings:
    """与誉佳 BridgeC 相同字段语义；环境变量前缀为 KQ_POOL_*（避免同机与 C_BRIDGE_* 冲突）。"""
    base = _env("KQ_POOL_BASE_URL", "").rstrip("/")
    if not base:
        print(
            "请设置环境变量 KQ_POOL_BASE_URL（Aidun 根 URL，无尾斜杠）",
            file=sys.stderr,
        )
        sys.exit(2)

    key = _env("KQ_POOL_API_KEY", "")
    if not key and interactive and sys.stdin.isatty():
        key = getpass("KQ_POOL_API_KEY（在 Aidun 管理页生成，输入不回显）: ").strip()
    if not key:
        print(
            "未配置密钥：请设置环境变量 KQ_POOL_API_KEY，或在终端交互输入。",
            file=sys.stderr,
        )
        sys.exit(2)

    instance = _env("KQ_POOL_INSTANCE_ID", "")
    try:
        interval = float(_env("KQ_POOL_POLL_INTERVAL_SEC", "5") or "5")
    except ValueError:
        interval = 5.0
    try:
        limit = int(_env("KQ_POOL_PULL_LIMIT", "10") or "10")
    except ValueError:
        limit = 10
    pool_dir = _env("KQ_POOL_LOCAL_POOL_DIR", "data/pending")
    try:
        timeout = float(_env("KQ_POOL_HTTP_TIMEOUT_SEC", "60") or "60")
    except ValueError:
        timeout = 60.0

    return Settings(
        bridge_base_url=base,
        api_key=key,
        instance_id=instance,
        poll_interval_sec=max(1.0, interval),
        pull_limit=max(1, min(limit, 100)),
        local_pool_dir=pool_dir,
        request_timeout_sec=max(5.0, timeout),
    )
