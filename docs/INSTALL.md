# aidun_bridge_c 安装与部署

> 这份文档**只讲一件事**:在一台新机器上把 `aidun_bridge_c` 守护进程跑起来。
> 装完之后怎么投递、怎么消费,看 [USAGE.md](USAGE.md)。

---

## 1. 准备

- **Python ≥ 3.10**(`python3 --version` 或 Windows 上 `py -3 --version`)
- 客户机能访问 `c.aidunkouqiang.com`(`curl -I http://c.aidunkouqiang.com` 应有响应)
- 客户机能访问 `github.com`(`pip install` 时会从 GitHub 拉核心库 `bridge-c-core`)
- **一个 `api_key`**(由对端管理员事先在 Aidun 后台为你这台机器开好;只会出现一次,丢了找管理员重发)

---

## 2. 安装

```bash
git clone https://github.com/wiseyip0911/aidun_bridge_c.git
cd aidun_bridge_c
git checkout v0.2.8
python -m pip install .
```

强烈建议用虚拟环境,避免污染系统 Python:

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

## 3. 配置(一行就够)

```bash
cp .env.example .env
# Windows PowerShell: copy .env.example .env
```

打开 `.env`,只需要填这一行:

```
KQ_POOL_API_KEY=<管理页给你的 apikey>
```

其他变量都有默认值,**不要动**,除非你知道自己在干什么。

> 进程启动时会自动加载 `.env`。如果同时设了系统环境变量,**系统环境变量优先**。

---

## 4. 自检(必做)

```bash
python -m aidun_bridge_c --once
```

期望输出:

```
... GET http://c.aidunkouqiang.com/kq-pool/v1/directory "HTTP/1.1 200 OK"
{
  "success": true,
  "items": [ ... ],
  "count": ...
}
```

**自检不过就不要往下走。** 排错见本文件 §7。

---

## 5. 启动守护(日常运行)

```bash
python -m aidun_bridge_c
```

会一直跑,直到 Ctrl+C。看到周期性的 `HTTP/1.1 200 OK` 就是健康。

### 5.1 可选:让"新任务到达"实时触发本机 Agent (webhook hook)

默认守护只把任务落到 `data/pending/`,Agent 自己来查。如果你想"任务一落地就立刻
被处理",可以让守护**额外**把整条记录 POST 给本机一个 webhook。

在 `.env` 里加一行:

```bash
KQ_POOL_NOTIFY_WEBHOOK_URL=http://127.0.0.1:8644/webhooks/bridge-task
```

可选加 HMAC secret(对端开启签名校验时必填,本机 loopback 调试可用
`INSECURE_NO_AUTH` 占位):

```bash
KQ_POOL_NOTIFY_WEBHOOK_SECRET=INSECURE_NO_AUTH
```

行为约定:

- **可选,默认禁用**:不设 `KQ_POOL_NOTIFY_WEBHOOK_URL` 就是老行为,完全向后兼容
- **POST 失败不影响主循环**:任务文件已经原子落盘,Agent 仍可用 `ls data/pending/`
  兜底,绝不会因 webhook 网络抖动而丢消息
- **HMAC 签名兼容 GitHub 协议**:secret 非空时,自动在 `X-Hub-Signature-256`
  头填 `sha256=<hex>`,可以直接对接 hermes gateway / GitHub Webhook 风格的接收方
- **幂等**:每次 POST 携带 `X-Request-ID` = `record_id`,接收方据此去重

> 典型搭配 hermes:
> ```
> hermes webhook subscribe bridge-task --secret INSECURE_NO_AUTH --prompt "..."
> hermes gateway run
> ```
> 然后把生成的 URL 写到上面的 env。完整搭法见 `docs/HERMES.md`。

### 5.2 本机消息看板 Web UI

若已在 `.env` 开启 `KQ_POOL_MESSAGE_LOG_PATH=data/messages.jsonl`(推荐),可启动
本机 Web 看板:左侧联系人列表、右侧与该联系人的收发气泡、底部发送框;前端
每 1.5 秒轮询刷新。

```bash
aidun-chat-web
# 浏览器访问 http://127.0.0.1:8645/
```

默认仅监听 `127.0.0.1`,无鉴权(仅供本机浏览器)。改端口:`aidun-chat-web --port 9000`。

---

## 6. 后台运行(systemd / Windows 计划任务)

### Linux:systemd

```ini
# /etc/systemd/system/aidun-bridge-c.service
[Unit]
Description=Aidun Bridge C
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/aidun_bridge_c
ExecStart=/opt/aidun_bridge_c/.venv/bin/python -m aidun_bridge_c --no-interactive
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

`WorkingDirectory` 下要有 `.env`,守护启动后会自动读。

启用:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now aidun-bridge-c
sudo journalctl -u aidun-bridge-c -f
```

> `--no-interactive` 是给无 TTY 环境的硬开关:没读到 `api_key` 直接 `exit 2`,而不是停在那儿等输入。

### Windows:任务计划程序

- 程序:`C:\path\to\.venv\Scripts\python.exe`
- 参数:`-m aidun_bridge_c --no-interactive`
- 起始位置:`C:\path\to\aidun_bridge_c`(`.env` 要在这里)
- 触发器:"启动时"
- 用户账户:勾选"不管用户是否登录都要运行"

---

## 7. 装不上时的排错

| 现象 | 多半原因 | 怎么办 |
|---|---|---|
| `pip install` 报错 `Could not find a version` / `Repository not found` | 客户机没法访问 github.com | 网管放行 github.com,或挂代理 |
| `--once` 卡住几十秒后超时 | 客户机访问不了对端 | `curl -I http://c.aidunkouqiang.com` 自查 |
| 启动时提示**回显输入密钥** | 没建 `.env`,也没 `export KQ_POOL_API_KEY` | 回到 §3 建 `.env` |
| 启动直接 `请设置环境变量 KQ_POOL_API_KEY` 退出 | 同上,且加了 `--no-interactive` 或在 systemd 里 | 同上;systemd 下 `.env` 要放在 `WorkingDirectory` |
| HTTP 401 | api_key 错 / 被禁用 / 复制时带了空格 | 找对端管理员确认;`cat .env` 检查那一行尾部是否多了空格 |
| HTTP 404 在所有路径上 | 对端 nginx 还没把 `/kq-pool/` 反代到 9001 | 找对端运维确认,或临时 `KQ_POOL_BASE_URL=http://c.aidunkouqiang.com:9001` 直连绕过 |
| TLS 报错 / 证书时间错 | 客户机系统时间错乱 | Linux `timedatectl status` / Windows `w32tm /query /status` |

---

## 8. 升级

```bash
cd aidun_bridge_c
git pull
git checkout <新 tag>
python -m pip install -U .
sudo systemctl restart aidun-bridge-c   # 如果用 systemd
```

venv 里跑同样命令即可。

---

## 9. 卸载

```bash
sudo systemctl stop aidun-bridge-c
sudo systemctl disable aidun-bridge-c
rm -rf /opt/aidun_bridge_c
```

> ⚠ `data/pending/` 里如果还有 `.json`,**说明本机 Agent 还没消费完**。直接删等于丢任务。删之前先确认。
