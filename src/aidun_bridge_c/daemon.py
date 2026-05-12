from __future__ import annotations

import json
import logging
import time
from pathlib import Path

from aidun_bridge_c.client import KqPoolClient
from aidun_bridge_c.config import Settings

logger = logging.getLogger(__name__)


def _write_local_item(pool_dir: Path, record: dict) -> Path | None:
    rid = str(record.get("record_id") or record.get("id") or "").strip()
    if not rid:
        rid = str(hash(json.dumps(record, sort_keys=True, ensure_ascii=True)))
    path = pool_dir / f"{rid}.json"
    if path.exists():
        return None
    path.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def run_daemon(settings: Settings) -> None:
    client = KqPoolClient(
        base_url=settings.bridge_base_url,
        api_key=settings.api_key,
        instance_id=settings.instance_id or None,
        timeout=settings.request_timeout_sec,
    )
    pool = Path(settings.local_pool_dir)
    pool.mkdir(parents=True, exist_ok=True)

    logger.info(
        "AidunBridgeC 守护启动 base=%s pool=%s interval=%ss",
        settings.bridge_base_url,
        pool.resolve(),
        settings.poll_interval_sec,
    )

    while True:
        try:
            resp = client.inbox_pull_relaxed(limit=settings.pull_limit)
            if not resp.get("success", True) and resp.get("http_status") == 404:
                logger.error(
                    "Aidun 返回 404：可能尚未部署 /kq-pool/v1/inbox/pull，或 KQ_POOL_BASE_URL 不对。"
                )
            items = resp.get("items")
            if isinstance(items, list) and items:
                for item in items:
                    if not isinstance(item, dict):
                        continue
                    written = _write_local_item(pool, item)
                    if written:
                        logger.info("已写入本地池 %s", written.name)
                    rid = str(item.get("record_id") or item.get("id") or "").strip()
                    if rid and resp.get("auto_ack") is True:
                        ack_r = client.inbox_ack_relaxed(rid)
                        logger.debug("ack %s -> %s", rid, ack_r.get("success", ack_r))
            elif isinstance(resp.get("data"), dict):
                nested = resp["data"].get("items")
                if isinstance(nested, list):
                    for item in nested:
                        if isinstance(item, dict):
                            written = _write_local_item(pool, item)
                            if written:
                                logger.info("已写入本地池 %s", written.name)
        except Exception:
            logger.exception("轮询失败，%s 秒后重试", settings.poll_interval_sec)

        time.sleep(settings.poll_interval_sec)
