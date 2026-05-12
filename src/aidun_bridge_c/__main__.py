"""Aidun kq-pool C 端：默认守护轮询（与誉佳 `python -m bridge_c` 行为对齐）；`--once` 仅测 directory。"""

from __future__ import annotations

import argparse
import json
import logging
import sys

from aidun_bridge_c import KqPoolClient
from aidun_bridge_c.config import load_settings
from aidun_bridge_c.daemon import run_daemon


def main() -> int:
    parser = argparse.ArgumentParser(
        description="AidunBridgeC：轮询 Aidun /kq-pool/v1/inbox/pull，写入本地 data/pending/"
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="不启动守护进程，仅请求一次 GET /kq-pool/v1/directory 并打印 JSON（连通性检查）",
    )
    parser.add_argument(
        "--no-interactive",
        action="store_true",
        help="无 TTY 时不要交互输入密钥（未设 KQ_POOL_API_KEY 则退出）",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    if args.once:
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

    settings = load_settings(interactive=not args.no_interactive)
    run_daemon(settings)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130) from None
