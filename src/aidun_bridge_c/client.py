from __future__ import annotations

import json
import logging
import os
from typing import Any

import httpx

logger = logging.getLogger(__name__)


class KqPoolClient:
    """调用 Aidun `/kq-pool/v1/*` 的轻量客户端。"""

    def __init__(
        self,
        base_url: str | None = None,
        api_key: str | None = None,
        instance_id: str | None = None,
        *,
        timeout: float = 60.0,
    ) -> None:
        self.base_url = (base_url or os.environ.get("KQ_POOL_BASE_URL") or "").rstrip("/")
        self.api_key = (api_key or os.environ.get("KQ_POOL_API_KEY") or "").strip()
        self.instance_id = (instance_id or os.environ.get("KQ_POOL_INSTANCE_ID") or "").strip()
        if not self.base_url:
            raise ValueError("KQ_POOL_BASE_URL is required (or pass base_url=)")
        if not self.api_key:
            raise ValueError("KQ_POOL_API_KEY is required (or pass api_key=)")

        self._timeout = timeout

    def _headers(self) -> dict[str, str]:
        h: dict[str, str] = {"Authorization": f"Bearer {self.api_key}"}
        if self.instance_id:
            h["X-Kq-Pool-Instance-Id"] = self.instance_id
        return h

    def _request(
        self,
        method: str,
        path: str,
        *,
        json_body: dict[str, Any] | None = None,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        url = f"{self.base_url}{path}"
        with httpx.Client(timeout=self._timeout) as client:
            r = client.request(
                method,
                url,
                headers=self._headers(),
                json=json_body,
                params=params,
            )
            r.raise_for_status()
            data = r.json()
        if not isinstance(data, dict):
            raise ValueError("unexpected non-JSON object response")
        return data

    def _parse_response(self, r: httpx.Response) -> dict[str, Any]:
        """与誉佳 BridgeC 一致：HTTP 错误不抛异常，便于守护进程轮询。"""
        try:
            data = r.json()
        except json.JSONDecodeError:
            data = {"raw": (r.text or "")[:2000]}
        if r.status_code >= 400:
            logger.warning("Aidun 响应 http=%s body=%s", r.status_code, data)
            return {
                "success": False,
                "http_status": r.status_code,
                **(data if isinstance(data, dict) else {}),
            }
        if isinstance(data, dict):
            return data
        return {"success": True, "data": data}

    def _request_relaxed(
        self,
        method: str,
        path: str,
        *,
        json_body: dict[str, Any] | None = None,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        url = f"{self.base_url}{path}"
        with httpx.Client(timeout=self._timeout) as client:
            r = client.request(
                method,
                url,
                headers=self._headers(),
                json=json_body,
                params=params,
            )
        return self._parse_response(r)

    def directory(self) -> dict[str, Any]:
        return self._request("GET", "/kq-pool/v1/directory")

    def submit(self, body: dict[str, Any]) -> dict[str, Any]:
        return self._request("POST", "/kq-pool/v1/submit", json_body=body)

    def submit_to(self, body: dict[str, Any]) -> dict[str, Any]:
        return self._request("POST", "/kq-pool/v1/submit_to", json_body=body)

    def inbox_pull(self, limit: int = 10) -> dict[str, Any]:
        return self._request(
            "GET",
            "/kq-pool/v1/inbox/pull",
            params={"limit": limit},
        )

    def inbox_pull_relaxed(self, limit: int = 10) -> dict[str, Any]:
        return self._request_relaxed(
            "GET",
            "/kq-pool/v1/inbox/pull",
            params={"limit": limit},
        )

    def inbox_ack(self, record_id: str) -> dict[str, Any]:
        rid = (record_id or "").strip()
        if not rid:
            raise ValueError("record_id required")
        return self._request("POST", f"/kq-pool/v1/inbox/{rid}/ack")

    def inbox_ack_relaxed(self, record_id: str) -> dict[str, Any]:
        rid = (record_id or "").strip()
        if not rid:
            return {"success": False, "detail": "record_id required"}
        return self._request_relaxed(
            "POST", f"/kq-pool/v1/inbox/{rid}/ack", json_body={}
        )
