"""仓库根的兼容入口:`python hermes_worker.py ...` 仍然可用。

真正的实现搬到了 `aidun_bridge_c/hermes_worker.py`,装好本仓库后推荐用注册
好的 console script:

    aidun-hermes-worker list
    aidun-hermes-worker reply <rid> "<text>"

或等价的:

    python -m aidun_bridge_c.hermes_worker list

保留这个根脚本是为了**老的文档和老的运维肌肉记忆**,不引入新依赖。
"""
from __future__ import annotations

import sys

if __name__ == "__main__":
    try:
        from aidun_bridge_c.hermes_worker import main
    except Exception as e:
        sys.stderr.write(
            f"[ERR] 无法导入 aidun_bridge_c.hermes_worker。"
            f"请先在本仓库执行 `pip install -e .`。详情: {e}\n"
        )
        raise SystemExit(1)
    raise SystemExit(main())
