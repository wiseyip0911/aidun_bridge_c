# aidun_bridge_c 安装与部署

> 这份文档**只讲一件事**:在一台新机器上把 `aidun_bridge_c` 守护进程跑起来。
> 装完之后怎么投递、怎么消费,看 [USAGE.md](USAGE.md)。

---

## 1. 准备

- **Python ≥ 3.10**(`python3 --version` 或 Windows 上 `py -3 --version`)
- 客户机能访问 `c.aidunkouqiang.com`（`curl -I https://c.aidunkouqiang.com` 应有响应）
- 客户机能访问 `github.com`(`pip install` 时会从 GitHub 拉核心库 `bridge-c-core`)
- **一个 `api_key`**(由对端管理员事先在 Aidun 后台为你这台机器开好;只会出现一次,丢了找管理员重发)

---

## 2. 安装

```bash
git clone https://github.com/wiseyip0911/aidun_bridge_c.git
cd aidun_bridge_c
git checkout v0.2.24
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
... GET https://c.aidunkouqiang.com/kq-pool/v1/directory "HTTP/1.1 200 OK"
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

若已在 `.env` 开启 `KQ_POOL_MESSAGE_LOG_PATH=...`(推荐**绝对路径**),可启动
本机 Web 看板:左侧联系人列表、右侧与该联系人的收发气泡、底部发送框;前端
每 1.5 秒轮询刷新。发送时可在底部选择 **channel**(默认 `lookup` 查询/走工具,
纯闲聊选 `chat`,长文摘要选 `summarize`),与 [HERMES.md](HERMES.md) §3 约定一致。
`aidun-chat-web` 使用 **V-Teeth卫齿士** 品牌皮肤(主色 CMYK 0/60/100/0 → 屏显橙 `#ff6600`)。

```bash
aidun-chat-web
# 浏览器访问 http://127.0.0.1:8645/
```

默认仅监听 `127.0.0.1`,无鉴权(仅供本机浏览器)。改端口:`aidun-chat-web --port 9000`。

### 5.3 Windows 一键:桥 + 看板 + 浏览器(双击)

仓库内 **`scripts/windows/Start-桥与看板.bat`**(同目录另有英文名 **`Start-Bridge-And-Dashboard.bat`**,功能相同):双击后会

- **`-RecycleAll -HermesLaunchMode auto`**:先结束本机栈上旧进程(**`hermes_worker watch`**、**`py -m aidun_bridge_c --no-interactive`**、在 **`WebPort`** 上监听的 **`chat_webapp`/`aidun-chat-web`**、以及命令行可识别的 **Hermes** 相关进程),再按顺序拉起。若 **`auto`** 且未找到 Hermes 启动器,则新开窗口运行仓库内 **`scripts/windows/Install-VTeethHermes.ps1`**(原 V-Teeth Windows 装机脚本),**本启动器立即 exit 0 退出**(不在此等待安装完成);安装结束后再双击本脚本。不需要此行为时传 **`-SkipHermesInstall`**(将退回仅桥/看板,且 Hermes 仍为缺失)。安装脚本要求 **D: 盘** 与可访问 **`raw.githubusercontent.com`**。
- **Hermes(`auto`)**:若存在启动器,会先在本机 Hermes 目录写入 **`WEBHOOK_ENABLED=true`** / **`WEBHOOK_PORT=8644`** 与 **`bridge-task`** 路由(否则 gateway 进程在跑但 **8644 不会监听**),再最小化启动 **`hermes gateway run --replace`** 并等待 **8644** 就绪(默认最多 **90s** + **15s** 宽限;探测 TCP 与 **`/health`**)。**不再**默认先开 TUI。需要 TUI 时加 **`-WithHermesTui`**。若仍要「先 TUI 后 gateway」,显式传 **`-HermesLaunchMode tui_then_gateway`**。
- 然后**最小化**启动桥 **`py -3 -m aidun_bridge_c --no-interactive`**。
- 再检测 **`hermes_worker watch`**;没有则**最小化**拉起(默认 `--interval 5`)。不需要时可传 **`-NoHermesWorker`**。
- 检测本机 **`ListenHost:WebPort`** 是否已有监听;没有则启动 `aidun-chat-web`(或 `python -m aidun_bridge_c.chat_webapp` 兜底)。
- 最后**打开默认浏览器**到看板 URL。
- 看板进程启动后**最多等待约 45s** 检测端口;若仍未监听,**不会**打开浏览器,脚本以退出码 1 结束,`.bat` 会 **`pause`** 方便阅读报错(同时可查上述日志)。
- 脚本开头会从注册表合并 Machine/User **PATH**,减轻「终端里能跑 `py`、资源管理器双击却找不到」的情况。
- 启动器 `.ps1` 使用 **UTF-8 BOM**;日志以英文为主,少数面向用户的提示为中文,避免 Windows PowerShell 5.1 在中文区域下把无 BOM UTF-8 误当成系统编码解析导致**整脚本语法报错**。

若**未**使用 `-RecycleAll`,则仍按「缺什么补什么」:已有桥/看板/worker 则跳过对应启动;若 **`HermesGatewayPort`** 已有监听则跳过 Hermes。**Hermes** 在仅运行 `.ps1` 时默认 **`HermesLaunchMode none`**;需要本机 Hermes 时传 **`-HermesLaunchMode auto`**(或与 bat 相同参数)。看板与 Hermes 网关端口是否就绪,由 **`Get-NetTCPConnection` 在该端口是否有 `Listen`** 判断(不限制 `LocalAddress`,避免 Windows 上 **`::1`** 等绑定被漏检)。

高级用法(自定义端口,PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\start_bridge_and_dashboard.ps1 -WebPort 9000
powershell -ExecutionPolicy Bypass -File .\scripts\windows\start_bridge_and_dashboard.ps1 -NoHermesWorker
powershell -ExecutionPolicy Bypass -File .\scripts\windows\start_bridge_and_dashboard.ps1 -HermesWatchIntervalSec 10
# 与 bat 相同:全量杀掉再起 + Hermes(auto=tui 控制台 + gateway)
powershell -ExecutionPolicy Bypass -File .\scripts\windows\start_bridge_and_dashboard.ps1 -RecycleAll -HermesLaunchMode auto
# 指定 Hermes 启动器、网关端口、TUI 等待秒数
powershell -ExecutionPolicy Bypass -File .\scripts\windows\start_bridge_and_dashboard.ps1 -RecycleAll -HermesLaunchMode tui_then_gateway -HermesCmdPath "D:\vteeth\hermes\bin\hermes.cmd" -HermesGatewayPort 8644 -HermesTuiWarmupMaxSec 180 -HermesTuiWarmupMinSec 10 -HermesTuiPollIntervalSec 2
```

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
| `--once` 卡住几十秒后超时 | 客户机访问不了对端 | `curl -I https://c.aidunkouqiang.com` 自查 |
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
