"""aidun-chat-web: 本机消息看板入口(转 ``bridge_c_core.chat_webapp``)。

自 v0.2.9 起,看板的实际实现下沉到了 ``bridge_c_core.chat_webapp``,这里只
保留一个**薄壳**:

- 把 ``BRIDGE_C_CLIENT_FACTORY`` 默认设成 ``aidun_bridge_c:KqPoolClient``,
  使最终用户继续敲 ``aidun-chat-web`` 即可,无需再传 ``--client-factory``。
- 若包内存在 ``web_static/index.html``,则设置 ``BRIDGE_C_CHAT_WEB_STATIC_DIR``
  指向该目录,加载 **V-Teeth卫齿士** 品牌皮肤(core ≥0.1.7)。
- 在调用 core 之前**显式加载** ``.env``:先当前工作目录下的 ``.env``(与一键脚本
  ``-WorkingDirectory`` 对齐),再尝试从包路径推断的仓库根(editable 布局)。
  否则 core 常读不到 ``KQ_POOL_API_KEY``,出现 ``directory_relaxed 失败``。
- 透传所有 CLI 参数到 core 的 ``main``,等同于 ``bridge-c-chat-web``。

如需自定义客户端工厂(很少见),也可以显式 ``--client-factory``,会覆盖默认值。
"""
from __future__ import annotations

import os
from pathlib import Path

from bridge_c_core.chat_webapp import main as _core_main

DEFAULT_FACTORY = "aidun_bridge_c:KqPoolClient"


def _load_repo_dotenv() -> None:
    """加载 ``.env``:优先当前工作目录(与一键启动脚本的 ``-WorkingDirectory`` 对齐),
    再尝试从包路径推断的仓库根(仅 editable / ``src`` 布局)。

    纯 ``site-packages`` 安装时无 ``src`` 段,必须依赖 cwd 下的 ``.env`` 或已导出的环境变量。
    """
    try:
        from dotenv import load_dotenv  # type: ignore
    except Exception:
        return
    cwd_env = Path.cwd() / ".env"
    if cwd_env.is_file():
        load_dotenv(cwd_env, override=False)
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
