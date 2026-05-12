# aidun_bridge_c

Aidun **实例池 (kq-pool)** 的 HTTP 客户端，与 AB WebSocket `/bridge/ws` 无关。

服务端路径与鉴权见 Aidun 仓库：`backend/docs/KQ_POOL_API_Aidun.md`。

## 环境变量

复制 `.env.example` 为 `.env` 后填写（或仅在启动脚本里 export）：

| 变量 | 必填 | 说明 |
|------|------|------|
| `KQ_POOL_BASE_URL` | 是 | Aidun 根地址，无尾斜杠 |
| `KQ_POOL_API_KEY` | 是 | 管理端创建的 api_key |
| `KQ_POOL_INSTANCE_ID` | 否 | 与凭证一致时可填，会带 `X-Kq-Pool-Instance-Id` |

与誉佳 C 端常用名 `C_BRIDGE_*` 刻意区分，避免同机多项目 env 冲突。

## 安装

```bash
cd aidun_bridge_c
python -m venv .venv
.venv\Scripts\activate   # Windows
pip install -e .
```

## 用法

```python
from aidun_bridge_c import KqPoolClient

c = KqPoolClient(
    base_url="http://127.0.0.1:8000",
    api_key="...",
    instance_id="my-device",  # 可选
)
print(c.directory())
```

命令行试连（需已配置环境变量或系统 env）：

```bash
python -m aidun_bridge_c
```

## Git 远程

```bash
git remote add origin git@github.com:wiseyip0911/aidun_bridge_c.git
git branch -M main
git push -u origin main
```

首次推送前需在 GitHub 建好空仓库并配置本机 SSH key。
