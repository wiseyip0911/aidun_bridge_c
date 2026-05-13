"""Aidun kq-pool 实例池 C 端客户端 —— 仅声明协议差异点,逻辑全部继承自 ``bridge_c_core.BaseClient``。"""
from __future__ import annotations

from bridge_c_core import BaseClient


class KqPoolClient(BaseClient):
    URL_PREFIX = "/kq-pool/v1"
    INSTANCE_HEADER = "X-Kq-Pool-Instance-Id"

    DEFAULT_BASE_URL = "http://c.aidunkouqiang.com"

    ENV_BASE_URL = "KQ_POOL_BASE_URL"
    ENV_API_KEY = "KQ_POOL_API_KEY"
    ENV_INSTANCE_ID = "KQ_POOL_INSTANCE_ID"
