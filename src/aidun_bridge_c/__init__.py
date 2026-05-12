"""Aidun 实例池 (kq-pool) 客户端。"""

from aidun_bridge_c.client import KqPoolClient
from aidun_bridge_c.config import Settings, load_settings

__all__ = ["KqPoolClient", "Settings", "load_settings", "__version__"]

__version__ = "0.1.0"
