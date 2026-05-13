# aidun_bridge_c

Aidun **实例池 (kq-pool)** 的 C 端薄适配器。

内核共享自 [`bridge-c-core`](https://github.com/wiseyip0911/bridge_c_core)(同一份代码用于 `yujia_bridge_c` / `aidun_bridge_c` / 未来其他公司的 `*_bridge_c`),本仓库**只负责声明本公司协议差异点**:

| 差异点 | 本仓库声明           |
|---|---|
| URL 前缀     | `/kq-pool/v1`               |
| 实例 header  | `X-Kq-Pool-Instance-Id`     |
| 环境变量前缀 | `KQ_POOL_`                   |

整个适配层(`client.py` + `__main__.py` + `__init__.py`)合计不到 50 行。

## 运行(末端机器最简流程)

> 前置条件:客户机能访问 `github.com`(因为安装时会从 GitHub 拉取核心包 `bridge-c-core`)。

```bash
# 1) 克隆本仓库
git clone https://github.com/wiseyip0911/aidun_bridge_c.git
cd aidun_bridge_c

# 2) 安装(pip 会自动从 github 拉取 bridge-c-core@v0.1.1)
python -m pip install .

# 3) 仅配 API_KEY(BASE_URL 已内置在仓库)
export KQ_POOL_API_KEY=你的apikey

# 4a) 守护轮询
python -m aidun_bridge_c

# 4b) 仅做连通性检查(请求一次 /kq-pool/v1/directory)
python -m aidun_bridge_c --once

# 4c) 无 TTY 部署
python -m aidun_bridge_c --no-interactive
```

## 环境变量

| 变量                          | 必填 | 默认值                          | 说明                              |
|-----------------------------|----|--------------------------------|---------------------------------|
| `KQ_POOL_API_KEY`             | 是* | -                              | 管理页生成,TTY 下可交互输入           |
| `KQ_POOL_BASE_URL`            | 否  | `http://c.aidunkouqiang.com`    | 仅在对端域名/协议临时变化时覆盖        |
| `KQ_POOL_INSTANCE_ID`         | 否  | -                              | 与凭证一致时建议设置                  |
| `KQ_POOL_POLL_INTERVAL_SEC`   | 否  | `5`                            | 轮询间隔秒                          |
| `KQ_POOL_PULL_LIMIT`          | 否  | `10`                           | 每次拉取上限                         |
| `KQ_POOL_LOCAL_POOL_DIR`      | 否  | `data/pending`                 | 本地落盘目录                         |
| `KQ_POOL_HTTP_TIMEOUT_SEC`    | 否  | `60`                           | HTTP 超时秒                         |

## 库用法

```python
from aidun_bridge_c import KqPoolClient

with KqPoolClient(
    base_url="http://127.0.0.1:8000",
    api_key="...",
    instance_id="my-device",
) as c:
    print(c.directory())
    c.submit({"input_text": "hi", "payload_json": {}})
```

`KqPoolClient` 自带 strict / relaxed 两种风格的全部方法(`inbox_pull` / `inbox_pull_relaxed` / `inbox_ack` / ...),详见 `bridge_c_core.BaseClient`。

## Git 远程

`git@github.com:wiseyip0911/aidun_bridge_c.git`
