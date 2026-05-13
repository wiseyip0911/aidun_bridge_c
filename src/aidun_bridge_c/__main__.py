"""Aidun kq-pool C 端入口。全部行为继承自 ``bridge_c_core``,本文件只负责绑定本公司适配器。"""
from __future__ import annotations

from bridge_c_core.cli import make_cli

from aidun_bridge_c.client import KqPoolClient


main = make_cli(
    client_cls=KqPoolClient,
    env_prefix="KQ_POOL_",
    prog_name="AidunBridgeC",
)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130) from None
