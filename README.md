# aidun_bridge_c

Aidun **实例池 (kq-pool)** 客户机守护进程。在本机长期运行,周期性从 Aidun 服务端拉取本实例的待处理任务,把每条任务写入本地 `data/pending/` 目录,供本机 Agent(hermes、爱 d 等)消费。

---

## 文档导航

只看一份的话,按你是哪类人选:

| 你是谁 | 看哪份 |
|---|---|
| **第一次在新机器上装这个东西的人**(运维 / 工程师) | [docs/INSTALL.md](docs/INSTALL.md) |
| **已经装好了,准备把它接入自家应用的人**(agent 开发者) | [docs/USAGE.md](docs/USAGE.md) |
| **本机的 Hermes Agent,需要充当"任务执行者"** | [docs/HERMES.md](docs/HERMES.md)(开局必跑 `python hermes_worker.py watch`) |

三份文档**互不重叠**。装的事在 INSTALL,接入开发的事在 USAGE,Hermes 当执行者的事在 HERMES。

---

## 快速开始(末端机器 4 步)

> 前置:Python ≥ 3.10,客户机能访问 `github.com` 与 `c.aidunkouqiang.com`。

```bash
# 1) 克隆本仓库(指定 tag,避免拉到调试中的 main)
git clone https://github.com/wiseyip0911/aidun_bridge_c.git
cd aidun_bridge_c
git checkout v0.2.5

# 2) 安装(会自动从 GitHub 拉取核心库 bridge-c-core)
python -m pip install .

# 3) 配 api_key(.env 自动加载,只需要这一行)
cp .env.example .env
# 编辑 .env,填好 KQ_POOL_API_KEY=<管理页给你的 apikey>

# 4) 自检 + 守护
python -m aidun_bridge_c --once    # 看到 200 + 实例列表 = 通了
python -m aidun_bridge_c           # 然后启动守护
```

装不上 / 跑不通 → [docs/INSTALL.md §7 排错](docs/INSTALL.md#7-装不上时的排错)
跑通了但接入有疑问 → [docs/USAGE.md §3 排错](docs/USAGE.md#3-用起来后的排错)

---

## 仓库

`git@github.com:wiseyip0911/aidun_bridge_c.git`
