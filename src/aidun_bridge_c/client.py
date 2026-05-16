"""Aidun 实例池 (kq-pool) C 端 HTTP 客户端。"""
from __future__ import annotations

from bridge_c_core import BaseClient


class KqPoolClient(BaseClient):
    URL_PREFIX = "/kq-pool/v1"
    INSTANCE_HEADER = "X-Kq-Pool-Instance-Id"

    DEFAULT_BASE_URL = "https://c.aidunkouqiang.com"

    ENV_BASE_URL = "KQ_POOL_BASE_URL"
    ENV_API_KEY = "KQ_POOL_API_KEY"
    ENV_INSTANCE_ID = "KQ_POOL_INSTANCE_ID"
    ENV_MESSAGE_LOG_PATH = "KQ_POOL_MESSAGE_LOG_PATH"
