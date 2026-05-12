"""示例：从环境变量读取配置，拉一次 directory。"""

from __future__ import annotations

import json
import sys

from aidun_bridge_c import KqPoolClient


def main() -> int:
    try:
        c = KqPoolClient()
    except ValueError as e:
        print(e, file=sys.stderr)
        return 2
    try:
        out = c.directory()
    except Exception as e:
        print(e, file=sys.stderr)
        return 1
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
