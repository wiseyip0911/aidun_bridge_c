"""本机消息看板 Web UI(FastAPI + 单页 HTML)。

设计目标(与用户约定一致):
- 仅本机访问:默认 ``127.0.0.1``。
- 无鉴权(仅 loopback 场景)。
- 双栏布局:左侧 peer 列表 + 右侧气泡时间线 + 底部发送框。
- 实时性:前端每 1.5s 轮询 ``GET /api/snapshot``。

启动::

    aidun-chat-web
    aidun-chat-web --port 8645

浏览器打开终端里打印的 URL 即可。
"""
from __future__ import annotations

import argparse
import logging
import sys
import uuid
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

from aidun_bridge_c.aidun_chat import (
    _load_client,
    _self_instance_id,
    read_message_log_rows,
    resolve_message_log_path,
)

logger = logging.getLogger(__name__)


def _static_dir() -> Path:
    return Path(__file__).resolve().parent / "web_static"


def _serialize_row(r: dict[str, Any]) -> dict[str, Any]:
    return {
        "ts": r.get("ts") or "",
        "direction": r.get("direction") or "",
        "peer_instance_id": r.get("peer_instance_id") or "",
        "text": r.get("text") or "",
        "channel": r.get("channel") or "",
        "record_type": r.get("record_type") or "",
        "correlation_id": r.get("correlation_id") or "",
        "record_id": r.get("record_id") or "",
    }


def _build_snapshot(peer: str | None) -> dict[str, Any]:
    rows = read_message_log_rows()
    items: list[dict[str, Any]] = []
    try:
        client = _load_client()
        try:
            resp = client.directory_relaxed()
        finally:
            client.close()
        if isinstance(resp, dict) and resp.get("success", True):
            raw = resp.get("items")
            if isinstance(raw, list):
                items = [it for it in raw if isinstance(it, dict)]
    except Exception as e:
        logger.warning("directory_relaxed 失败(看板仍可用 log): %s", e)

    dir_ids = {str(it.get("instance_id") or "").strip() for it in items}
    dir_ids.discard("")

    last_by: dict[str, dict[str, Any]] = {}
    for r in rows:
        pid = str(r.get("peer_instance_id") or "").strip()
        if not pid:
            continue
        ts = str(r.get("ts") or "")
        cur = last_by.get(pid)
        if cur is None or ts > str(cur.get("ts") or ""):
            last_by[pid] = r

    all_ids = sorted(dir_ids | set(last_by.keys()))
    summaries: list[dict[str, Any]] = []
    for pid in all_ids:
        row = last_by.get(pid)
        summaries.append(
            {
                "peer": pid,
                "last_ts": row.get("ts", "") if row else "",
                "last_preview": (str(row.get("text") or ""))[:120] if row else "",
                "last_direction": str(row.get("direction") or "") if row else "",
                "last_record_type": str(row.get("record_type") or "")
                if row else "",
            }
        )
    summaries.sort(key=lambda s: s["last_ts"] or "", reverse=True)

    thread: list[dict[str, Any]] = []
    if peer:
        p = peer.strip()
        for r in rows:
            if str(r.get("peer_instance_id") or "") == p:
                thread.append(_serialize_row(r))
        thread.sort(key=lambda m: m["ts"])

    return {
        "log_path": str(resolve_message_log_path()),
        "self_instance_id": _self_instance_id(),
        "directory": items,
        "peer_summaries": summaries,
        "thread": thread,
        "peer": peer or "",
    }


class SendBody(BaseModel):
    to: str = Field(..., min_length=1)
    text: str = Field(..., min_length=1)
    channel: str = Field(default="chat", min_length=1)


app = FastAPI(title="aidun-chat-web", version="1.0")


@app.get("/")
def index() -> FileResponse:
    html = _static_dir() / "index.html"
    if not html.exists():
        raise HTTPException(
            status_code=500,
            detail=f"缺少静态页: {html}",
        )
    return FileResponse(html, media_type="text/html; charset=utf-8")


@app.get("/api/snapshot")
def api_snapshot(peer: str = Query(default="")) -> JSONResponse:
    return JSONResponse(_build_snapshot(peer or None))


@app.post("/api/send")
def api_send(body: SendBody) -> JSONResponse:
    cid = f"web-{uuid.uuid4().hex[:10]}"
    payload = {
        "channel": body.channel.strip(),
        "input_text": body.text,
    }
    me = _self_instance_id()
    if me:
        payload.setdefault("source", me)
    req = {
        "to_instance_id": body.to.strip(),
        "correlation_id": cid,
        "record_type": "task",
        "payload_json": payload,
    }
    try:
        client = _load_client()
        try:
            resp = client.submit_to(req)
        finally:
            client.close()
    except Exception as e:
        logger.exception("submit_to 失败")
        raise HTTPException(status_code=502, detail=str(e)) from e

    rid = str(resp.get("record_id") or "")
    return JSONResponse(
        {
            "success": True,
            "record_id": rid,
            "correlation_id": cid,
            "response": resp,
        }
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="aidun-chat-web",
        description="Aidun 本机消息看板(双栏 + 轮询)。",
    )
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="监听地址,默认仅本机 loopback",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8645,
        help="监听端口,默认 8645",
    )
    args = parser.parse_args(argv)

    try:
        import uvicorn
    except ImportError as e:
        sys.stderr.write(
            "[ERR] 缺少 uvicorn/fastapi。请在本仓库执行: pip install -e .\n"
            f"详情: {e}\n"
        )
        return 1

    url = f"http://{args.host}:{args.port}/"
    print(f"aidun-chat-web 已启动: {url}")
    print("  Ctrl+C 停止服务。")
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
