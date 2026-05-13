"""aidun_bridge_c 烟测:验证差异点 + 一次完整 HTTP 路由。"""
from __future__ import annotations

import httpx

from aidun_bridge_c import KqPoolClient


def test_kqpool_protocol_constants() -> None:
    assert KqPoolClient.URL_PREFIX == "/kq-pool/v1"
    assert KqPoolClient.INSTANCE_HEADER == "X-Kq-Pool-Instance-Id"
    assert KqPoolClient.ENV_BASE_URL == "KQ_POOL_BASE_URL"
    assert KqPoolClient.ENV_API_KEY == "KQ_POOL_API_KEY"
    assert KqPoolClient.ENV_INSTANCE_ID == "KQ_POOL_INSTANCE_ID"


def test_kqpool_inbox_pull_url_and_headers() -> None:
    captured: dict[str, object] = {}

    def handler(req: httpx.Request) -> httpx.Response:
        captured["url"] = str(req.url)
        captured["method"] = req.method
        captured["headers"] = dict(req.headers)
        return httpx.Response(200, json={"success": True, "items": []})

    c = KqPoolClient(
        base_url="https://aidun.example",
        api_key="kqp-abc",
        instance_id="my-device",
    )
    c.close()
    c._client = httpx.Client(transport=httpx.MockTransport(handler), timeout=5.0)

    out = c.inbox_pull(limit=3)
    assert out == {"success": True, "items": []}
    assert captured["url"] == "https://aidun.example/kq-pool/v1/inbox/pull?limit=3"
    assert captured["method"] == "GET"
    assert captured["headers"]["authorization"] == "Bearer kqp-abc"
    assert captured["headers"]["x-kq-pool-instance-id"] == "my-device"


def test_kqpool_reads_from_env(monkeypatch) -> None:
    monkeypatch.setenv("KQ_POOL_BASE_URL", "https://from-env.example")
    monkeypatch.setenv("KQ_POOL_API_KEY", "env-key")
    monkeypatch.setenv("KQ_POOL_INSTANCE_ID", "env-inst")

    c = KqPoolClient()
    try:
        assert c.base_url == "https://from-env.example"
        assert c.api_key == "env-key"
        assert c.instance_id == "env-inst"
    finally:
        c.close()
