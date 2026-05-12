# aidun_bridge_c

Aidun **实例池 (kq-pool)** 的 C 端客户端，行为与誉佳 **`yujia_bridge_c`（`python -m bridge_c`）** 对齐：

- 默认 **`python -m aidun_bridge_c`**：**守护进程**，轮询 **`GET /kq-pool/v1/inbox/pull`**，将条目写入 **`data/pending/*.json`**
- **`python -m aidun_bridge_c --once`**：只请求一次 **`GET /kq-pool/v1/directory`**（连通性检查）

与 AB WebSocket `/bridge/ws` 无关。服务端说明见 Aidun：`backend/docs/KQ_POOL_API_Aidun.md`。

## 与誉佳 C 端的差异（刻意保留）

| 项目 | 誉佳 BridgeC | Aidun 本仓库 |
|------|----------------|--------------|
| Base URL 环境变量 | `C_BRIDGE_BASE_URL` | **`KQ_POOL_BASE_URL`**（同机可避免与誉佳 env 冲突） |
| API Key | `C_BRIDGE_API_KEY` | **`KQ_POOL_API_KEY`** |
| 实例头 | `X-C-Instance-Id` | **`X-Kq-Pool-Instance-Id`**（Aidun 仍兼容旧头） |
| HTTP 路径前缀 | `/c/v1` | **`/kq-pool/v1`** |

其余：**轮询间隔、pull limit、本地目录、日志、`--no-interactive`** 与誉佳逻辑一致（变量名见下表）。

## 环境变量

| 变量 | 必填 | 说明 |
|------|------|------|
| `KQ_POOL_BASE_URL` | 是 | Aidun 根地址，无尾斜杠 |
| `KQ_POOL_API_KEY` | 是* | 管理页创建的 api_key；TTY 下未设置可交互输入 |
| `KQ_POOL_INSTANCE_ID` | 否 | 与凭证一致时建议设置 |
| `KQ_POOL_POLL_INTERVAL_SEC` | 否 | 轮询秒数，默认 `5` |
| `KQ_POOL_PULL_LIMIT` | 否 | 每次拉取上限，默认 `10` |
| `KQ_POOL_LOCAL_POOL_DIR` | 否 | 本地 JSON 目录，默认 `data/pending` |
| `KQ_POOL_HTTP_TIMEOUT_SEC` | 否 | HTTP 超时，默认 `60` |

## 安装

```bash
cd aidun_bridge_c
python -m pip install -e .
# 或: pip install -r requirements.txt
```

## 运行（与誉佳「无 venv」方式类似）

```bash
export KQ_POOL_BASE_URL=https://你的Aidun根
export KQ_POOL_API_KEY=...
python -m aidun_bridge_c
```

无 TTY 时需预先设置 `KQ_POOL_API_KEY`，或使用：

```bash
python -m aidun_bridge_c --no-interactive
```

仅测连通：

```bash
python -m aidun_bridge_c --once
```

## 库用法

```python
from aidun_bridge_c import KqPoolClient

c = KqPoolClient(
    base_url="http://127.0.0.1:8000",
    api_key="...",
    instance_id="my-device",
)
print(c.directory())
```

## Git 远程

`git@github.com:wiseyip0911/aidun_bridge_c.git`
