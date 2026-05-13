# aidun_bridge_c 使用与运维手册

> 本手册写给在 Aidun 客户机上**部署、运维、排错**的工程师。
> 部署本质就一件事:让本机长期跑一个守护进程,从 `c.aidunkouqiang.com` 拉任务到本地 `data/pending/`。

---

## 1. 准备

- **Python ≥ 3.10**(`python3 --version` 或 Windows 上 `py -3 --version`)
- 客户机能访问 `c.aidunkouqiang.com`(`curl -I http://c.aidunkouqiang.com` 应有响应)
- 客户机能访问 `github.com`(`pip install` 时会从 GitHub 拉依赖)
- **一个 `api_key`**(由对端管理员事先在 Aidun 后台为你这台机器开好;只会出现一次,丢了找管理员重发)

---

## 2. 安装

```bash
git clone https://github.com/wiseyip0911/aidun_bridge_c.git
cd aidun_bridge_c
python -m pip install .
```

强烈建议在虚拟环境里装,避免污染系统 Python:

```bash
# Linux / Mac
python3 -m venv .venv && source .venv/bin/activate
python -m pip install .

# Windows
py -3 -m venv .venv
.venv\Scripts\activate
python -m pip install .
```

---

## 3. 配置(最简只需 1 个环境变量)

推荐用 `.env` 文件,守护进程启动时会自动加载,**不需要**每次手动 `export`:

```bash
cp .env.example .env
# 用任意编辑器把 KQ_POOL_API_KEY=<你拿到的 apikey> 填上,保存
```

也支持直接走环境变量(适合 systemd 把 key 放到 unit 里):

```bash
export KQ_POOL_API_KEY=<你拿到的 apikey>
```

> 两种方式同时存在时,**进程环境变量优先**(`.env` 不会覆盖已设置的变量)。

这就够了。其他变量都有默认值,需要调时再设。

### 完整环境变量清单

| 变量                          | 必填 | 默认值                          | 何时改                          |
|-----------------------------|----|--------------------------------|--------------------------------|
| `KQ_POOL_API_KEY`             | 是  | -                              | 必填                            |
| `KQ_POOL_BASE_URL`            | 否  | `http://c.aidunkouqiang.com`    | 对端域名/协议临时变化时覆盖         |
| `KQ_POOL_INSTANCE_ID`         | 否  | -                              | 服务端要求与凭证分开展示实例时设置   |
| `KQ_POOL_POLL_INTERVAL_SEC`   | 否  | `5`                            | 想拉得更快或更慢                  |
| `KQ_POOL_PULL_LIMIT`          | 否  | `10`                           | 单次拉取条数上限(1..100)        |
| `KQ_POOL_LOCAL_POOL_DIR`      | 否  | `data/pending`                 | 想把任务文件放到别处               |
| `KQ_POOL_HTTP_TIMEOUT_SEC`    | 否  | `60`                           | 网络慢/对端慢时调大                |

---

## 4. 三种运行方式

### 4.1 连通性自检(部署第一步必做)

```bash
python -m aidun_bridge_c --once
```

期望输出一份 JSON,列出当前服务端所有已启用实例,例如:

```json
{
  "success": true,
  "items": [
    {
      "instance_id": "yeweizhi",
      "remark": "",
      "created_at": "2026-05-12T23:10:49"
    }
  ],
  "count": 1
}
```

**如果这一步就出错,先解决再说,不要直接上守护进程。** 常见错误见 §6。

### 4.2 守护轮询(日常运行)

```bash
python -m aidun_bridge_c
```

会一直跑,直到 Ctrl+C。日志走 stderr,长这样:

```
2026-05-13 12:33:17,579 INFO ... daemon starting base=http://c.aidunkouqiang.com pool=.../data/pending interval=5.0s
2026-05-13 12:33:17,627 INFO httpx HTTP Request: GET http://c.aidunkouqiang.com/kq-pool/v1/inbox/pull?limit=10 "HTTP/1.1 200 OK"
2026-05-13 12:33:17,631 INFO ... 已写入本地池 4825814a-1976-47d1-975d-560bd2a9b456.json
```

### 4.3 无 TTY 部署(systemd / supervisor / Windows 计划任务)

```bash
python -m aidun_bridge_c --no-interactive
```

`--no-interactive` 防止在没有终端的环境下试图交互输入密钥而卡住。**必须提前把 `KQ_POOL_API_KEY` 设到环境里**,否则进程 `exit 2`。

#### systemd 单元示例(Linux)

```ini
# /etc/systemd/system/aidun-bridge-c.service
[Unit]
Description=Aidun Bridge C
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/aidun_bridge_c
Environment=KQ_POOL_API_KEY=<your-key>
ExecStart=/opt/aidun_bridge_c/.venv/bin/python -m aidun_bridge_c --no-interactive
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

启用:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now aidun-bridge-c
sudo journalctl -u aidun-bridge-c -f   # 看日志
```

#### Windows 任务计划程序

- 程序:`C:\path\to\.venv\Scripts\python.exe`
- 参数:`-m aidun_bridge_c --no-interactive`
- 起始位置:`C:\path\to\aidun_bridge_c`
- 触发器:"启动时"
- 用户账户:勾选"不管用户是否登录都要运行"
- 环境变量在系统属性里全局设(否则计划任务读不到)

---

## 5. 任务文件与本机 Agent 的接口

### 5.1 文件长什么样

每条任务落到 `data/pending/<record_id>.json`,例如:

```json
{
  "record_id": "721dddd0-ef10-4d3b-8e67-2908de3b4b7d",
  "instance_id": "yeweizhi",
  "correlation_id": "调用方提交时给的 id",
  "record_type": "task",
  "payload_json": {
    "input_text": "用户原始输入",
    "其他业务字段": "..."
  },
  "created_at": "2026-05-13T11:35:18Z"
}
```

### 5.2 本机 Agent 怎么消费

最朴素的方式:**轮询目录**。

```python
from pathlib import Path
import json, time

POOL = Path("data/pending")

while True:
    for fp in sorted(POOL.glob("*.json")):
        record = json.loads(fp.read_text("utf-8"))
        try:
            handle(record)              # 你自己的业务处理
        except Exception:
            continue                     # 不删,下次重试
        else:
            fp.unlink()                  # 成功才删
    time.sleep(1)
```

### 5.3 保证与注意

- **同一 `record_id` 守护进程绝不会写两次**(基于 record_id 去重)。
- **守护进程绝不会写半截 JSON**(临时文件 + 原子改名)。Agent 看到的要么是完整文件,要么文件根本没出现。
- **多 Agent 并发消费同一目录**时需要自己做互斥:简单做法是把 `*.json` 重命名为 `*.processing.<pid>` 再处理。
- **守护进程崩溃 / Agent 崩溃**:文件还在,下次启动还能看到。不会丢已经落盘的任务。

---

## 6. 投递消息(C 端作为发送方)

C 端不只能"收",也能"发"。在本机的 Python 代码里:

### 6.1 向自己的收件箱投递

```python
from aidun_bridge_c import KqPoolClient

with KqPoolClient() as c:                 # 自动从 env 读 API_KEY + base_url
    r = c.submit({
        "correlation_id": "any-id",
        "input_text": "hi",
        "payload_json": {"foo": "bar"},
        "record_type": "task",
    })
    print(r)
# {'success': True, 'record_id': '...', 'correlation_id': 'any-id',
#  'instance_id': '...', 'message': 'accepted'}
```

### 6.2 向指定接收方投递(跨实例)

```python
with KqPoolClient() as c:
    # 先列出所有实例,确认对方实例代号
    print(c.directory())

    c.submit_to({
        "to_instance_id": "对方实例代号",
        "correlation_id": "xyz",
        "input_text": "...",
        "payload_json": {"...": "..."},
    })
```

**注意:`Bearer` 仍然是发送方自己的 api_key,服务端凭 `to_instance_id` 路由。** 你不需要、也不应该知道对方的 api_key。

---

## 7. 排错

| 现象 | 多半原因 | 怎么办 |
|---|---|---|
| `--once` 卡住,无响应 | 客户机访问不了对端 / 防火墙 | `curl -I http://c.aidunkouqiang.com` 看是否通;必要时改 `KQ_POOL_BASE_URL` 临时覆盖 |
| 启动时提示输入密钥(交互回显) | 没建 `.env` 文件,且没 `export KQ_POOL_API_KEY` | `cp .env.example .env`,把 api_key 填进去 |
| `请设置环境变量 KQ_POOL_API_KEY` 然后退出 | 同上,且无 TTY(`--no-interactive` 或 systemd) | 建 `.env` 或在 systemd unit 里 `Environment=KQ_POOL_API_KEY=...` |
| HTTP 401 | api_key 错 / 被禁用 / 复制时多了空格 | 找对端管理员确认状态,必要时重新生成 |
| HTTP 401 但你**确认 key 是对的** | `.env` 里那行末尾有空格、或注释里的 `#` 被当成值的一部分 | `cat .env` 自查;value 含特殊字符时用双引号包起来 |
| HTTP 404 + 日志提示"可能尚未部署 /inbox/pull" | 对端路径前缀不对 / 没配 nginx 反代 | 跟对端确认;或临时 `KQ_POOL_BASE_URL=http://c.aidunkouqiang.com:9001` 直连绕过 nginx |
| `data/pending/` 一直没有文件 | 服务端 inbox 是空的 | 正常现象,等真有人投递任务时才会出现;或自己 `c.submit({...})` 投一条测试 |
| `--once` 看 `directory` 里没有自己 | 实例没注册 / api_key 关联了别的实例 | 找管理员确认 |
| 日志反复"轮询失败" | 对端临时抽风 / 证书问题 | 守护进程会自动重试,等几分钟;持续异常查对端日志 |
| 客户机时间错乱导致 TLS 失败 | 系统时间不准 | `systemctl status systemd-timesyncd` / `w32tm /query /status` 校时 |
| `pip install` 时报错 "Could not find a version" 之类 | 客户机没法访问 github.com | 网管放行 / 用代理 |

### 7.1 看更详细的日志

把日志级别调到 DEBUG,可以看到每个 HTTP 请求/响应细节:

```python
# 在启动守护前先注入 DEBUG 级别:
import logging
logging.basicConfig(level=logging.DEBUG)

# 然后再:
from aidun_bridge_c.__main__ import main
import sys; sys.exit(main())
```

或者用一行临时:

```bash
python -c "import logging; logging.basicConfig(level=logging.DEBUG); from aidun_bridge_c.__main__ import main; main()"
```

### 7.2 看本地池堆积

```bash
ls -la data/pending/        # 看积压
ls data/pending/ | wc -l    # 数量
```

如果堆得很多,说明 Agent 处理跟不上,或者 Agent 没在跑。

---

## 8. 升级

```bash
cd aidun_bridge_c
git pull
python -m pip install -U .
sudo systemctl restart aidun-bridge-c   # 如果用 systemd
```

如果你跑在 venv 里,`pip install -U .` 在 venv 内执行即可。

---

## 9. 卸载 / 重装

```bash
sudo systemctl stop aidun-bridge-c       # 如果用 systemd
sudo systemctl disable aidun-bridge-c
rm -rf /opt/aidun_bridge_c               # 含 data/pending 里未处理的任务,慎删!
```

`data/pending/` 里如果还有任务文件,**删除前先确认是不是已经被 Agent 处理过**。已写入但未消费的任务在删除后**无法找回**(对端可能已经认为消费完毕)。
