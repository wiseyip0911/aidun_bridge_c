# aidun_bridge_c

Aidun **实例池 (kq-pool)** 客户机守护进程。在本机长期运行,周期性从 Aidun 服务端拉取本实例的待处理任务,把每条任务写入本地 `data/pending/` 目录,供本机 Agent 消费。

> 📘 完整使用规则与排错见 **[docs/USAGE.md](docs/USAGE.md)**。

---

## 快速开始(末端机器 3 步)

> 前置:Python ≥ 3.10,客户机能访问 `github.com`。

```bash
# 1) 克隆本仓库
git clone https://github.com/wiseyip0911/aidun_bridge_c.git
cd aidun_bridge_c

# 2) 安装
python -m pip install .

# 3) 配 API_KEY 并启动守护(BASE_URL 已内置)
export KQ_POOL_API_KEY=<你的 apikey>
python -m aidun_bridge_c
```

### 部署第一步:连通性自检

正式启动守护进程前,先跑一次自检,确认 api_key 和网络通:

```bash
python -m aidun_bridge_c --once
```

期望输出一份 JSON,列出当前服务端的所有实例。详细排错见 [USAGE.md §6](docs/USAGE.md#6-排错)。

---

## 环境变量

| 变量                          | 必填 | 默认值                          | 说明                              |
|-----------------------------|----|--------------------------------|---------------------------------|
| `KQ_POOL_API_KEY`             | 是  | -                              | 由对端管理页生成,**末端唯一必须配的项** |
| `KQ_POOL_BASE_URL`            | 否  | `http://c.aidunkouqiang.com`    | 应急覆盖:对端域名/协议临时变化时使用    |
| `KQ_POOL_INSTANCE_ID`         | 否  | -                              | 服务端要求与凭证分开展示实例时设置      |
| `KQ_POOL_POLL_INTERVAL_SEC`   | 否  | `5`                            | 轮询间隔秒                          |
| `KQ_POOL_PULL_LIMIT`          | 否  | `10`                           | 单次拉取上限                         |
| `KQ_POOL_LOCAL_POOL_DIR`      | 否  | `data/pending`                 | 本地落盘目录                         |
| `KQ_POOL_HTTP_TIMEOUT_SEC`    | 否  | `60`                           | HTTP 超时秒                         |

---

## 任务文件长什么样

每条任务作为一个 JSON 文件落到 `data/pending/<record_id>.json`:

```json
{
  "record_id": "721dddd0-ef10-4d3b-8e67-2908de3b4b7d",
  "instance_id": "your-instance-id",
  "correlation_id": "调用方提交时给的 id",
  "record_type": "task",
  "payload_json": { "...": "..." },
  "created_at": "2026-05-13T11:35:18Z"
}
```

本机 Agent 读取这个目录、处理任务、处理成功后删文件即可。完整 Agent 接入示例与多 Agent 互斥建议见 [USAGE.md §4](docs/USAGE.md#4-任务文件与本机-agent-的接口)。

---

## 库用法(在你自己的 Python 代码里投递消息)

```python
from aidun_bridge_c import KqPoolClient

with KqPoolClient() as c:                 # 自动从 env 读 API_KEY + 默认 base_url
    print(c.directory())                  # 列出所有实例
    c.submit({                            # 向自己的收件箱投递
        "correlation_id": "any-id",
        "input_text": "hi",
        "payload_json": {"foo": "bar"},
        "record_type": "task",
    })
```

详见 [USAGE.md §5](docs/USAGE.md#5-投递消息c-端作为发送方)。

---

## 升级

```bash
cd aidun_bridge_c
git pull
python -m pip install -U .
```

---

## 仓库

`git@github.com:wiseyip0911/aidun_bridge_c.git`
