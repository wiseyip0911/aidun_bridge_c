"""aidun-chat-web: 本机消息看板入口(转 ``bridge_c_core.chat_webapp``)。

自 v0.2.9 起,看板的实际实现下沉到了 ``bridge_c_core.chat_webapp``,这里只
保留一个**薄壳**:

- 把 ``BRIDGE_C_CLIENT_FACTORY`` 默认设成 ``aidun_bridge_c:KqPoolClient``,
  使最终用户继续敲 ``aidun-chat-web`` 即可,无需再传 ``--client-factory``。
- 若包内存在 ``web_static/index.html``,则设置 ``BRIDGE_C_CHAT_WEB_STATIC_DIR``
  指向该目录,加载 **V-Teeth卫齿士** 品牌皮肤(core ≥0.1.7)。
- 在调用 core 之前**显式加载**本仓库根目录的 ``.env``。否则从任意 cwd 启动
  ``aidun-chat-web`` 时,core 只会沿 ``bridge_c_core`` 的安装路径找 ``.env``,
  常常读不到 ``KQ_POOL_API_KEY``,出现 ``directory_relaxed 失败``。
- 透传所有 CLI 参数到 core 的 ``main``,等同于 ``bridge-c-chat-web``。

如需自定义客户端工厂(很少见),也可以显式 ``--client-factory``,会覆盖默认值。
"""
from __future__ import annotations

import os
from pathlib import Path

from bridge_c_core.chat_webapp import main as _core_main

DEFAULT_FACTORY = "aidun_bridge_c:KqPoolClient"


def _load_repo_dotenv() -> None:
    """加载仓库根 ``.env``,与 cwd 无关。

    仅当本文件位于 ``…/<repo>/src/aidun_bridge_c/chat_webapp.py``(editable 或
    ``pip install -e``)时,向上定位 ``<repo>/.env``。若安装在纯 ``site-packages``
    且无 ``src`` 段,则无法推断仓库路径,请从含 ``.env`` 的目录启动或导出环境变量。
    """
    try:
        from dotenv import load_dotenv  # type: ignore
    except Exception:
        return
    here = Path(__file__).resolve()
    parts = here.parts
    if len(parts) >= 3 and parts[-3] == "src" and parts[-2] == "aidun_bridge_c":
        env = here.parents[2] / ".env"
        if env.is_file():
            load_dotenv(env, override=False)


def main(argv: list[str] | None = None) -> int:
    _load_repo_dotenv()
    os.environ.setdefault("BRIDGE_C_CLIENT_FACTORY", DEFAULT_FACTORY)
    _static = Path(__file__).resolve().parent / "web_static"
    if _static.is_dir() and (_static / "index.html").is_file():
        os.environ.setdefault(
            "BRIDGE_C_CHAT_WEB_STATIC_DIR",
            str(_static.resolve()),
        )
    return _core_main(argv)


if __name__ == "__main__":
    raise SystemExit(main())
