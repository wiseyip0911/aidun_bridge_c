"""Aidun kq-pool C 端守护进程入口:``python -m aidun_bridge_c``。"""
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
