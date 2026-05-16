"""模拟 worker：写入一条 lookup 任务到 data/pending 并 POST Hermes bridge-task。

用法（仓库根）::

    py -3 scripts/hermes_simulate_lookup_task.py

需：本机 Hermes gateway 在 8644（或 .env 里 KQ_POOL_NOTIFY_WEBHOOK_URL）；
    yujia bridge 在 8000 时任务正文会指向 /bridge/test/product/3。
"""
from __future__ import annotations

import json
import os
import sys
import uuid
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

_REPO = Path(__file__).resolve().parents[1]


def main() -> int:
    os.chdir(_REPO)
    try:
        from dotenv import load_dotenv

        load_dotenv(_REPO / ".env", override=False)
    except Exception:
        pass

    rid = "hermes-col3-test-" + uuid.uuid4().hex[:12]
    pool = _REPO / "data" / "pending"
    pool.mkdir(parents=True, exist_ok=True)
    rec = {
        "record_id": rid,
        "correlation_id": "cid-" + rid,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "record_type": "task",
        "payload_json": {
            "channel": "lookup",
            "input_text": (
                "请用 curl GET http://127.0.0.1:8000/bridge/test/product/3 ，"
                "只回复接口 JSON 里 content 字段原文。"
            ),
            "_from_instance_id": "hermes-local-test",
        },
    }
    fp = pool / f"{rid}.json"
    fp.write_text(json.dumps(rec, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[OK] wrote {fp}", flush=True)

    url = (os.environ.get("KQ_POOL_NOTIFY_WEBHOOK_URL") or "").strip()
    if not url:
        port = (os.environ.get("HERMES_GATEWAY_PORT") or "8644").strip()
        url = f"http://127.0.0.1:{port}/webhooks/bridge-task"
    body = json.dumps({"record_id": rid}, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json", "X-Request-ID": rid},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            print(f"[OK] POST {url} -> {r.status} {r.read().decode()[:400]}", flush=True)
    except urllib.error.HTTPError as e:
        print(f"[ERR] HTTP {e.code} {(e.read() or b'').decode()[:400]}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"[ERR] {e}", file=sys.stderr)
        return 1
    print(f"[OK] record_id={rid}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
