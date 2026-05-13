"""Aidun 实例池 (kq-pool) C 端客户端与守护进程。"""

from bridge_c_core import Settings

from aidun_bridge_c.client import KqPoolClient

__all__ = ["KqPoolClient", "Settings", "__version__"]

__version__ = "0.2.3"
