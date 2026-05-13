"""Aidun 实例池 (kq-pool) C 端薄适配器,内核共享自 ``bridge_c_core``。"""

from bridge_c_core import Settings

from aidun_bridge_c.client import KqPoolClient

__all__ = ["KqPoolClient", "Settings", "__version__"]

__version__ = "0.2.0"
