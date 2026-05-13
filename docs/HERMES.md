# Hermes 任务处理速查

> 给运行在本机的 Hermes Agent 看的"操作手册"。**只描述你需要做什么,不描述任何代码细节。**

本机有一个 `aidun_bridge_c` 守护进程,会不停把外部机器发来的任务写到
`data/pending/<record_id>.json`。你的工作是:**读这些任务,处理,回投结果**。

工具只有一个:`python hermes_worker.py`。它支持 5 个子命令。

> **首次接班时,先在前台跑一条命令(下面 §0)**,它会持续打印新任务提示行,
> 你看到提示就处理。**不要假装自己在监控**——必须真的让这条命令跑起来,
> 它是你"发现新任务"的**唯一**可靠来源。

---

## 0. 持续监听新任务(开局必做)

```
python hermes_worker.py watch --interval 5
```

它会每 5 秒扫一次 `data/pending/`,**只在出现新任务时**打印一段提示:

```
[2026-05-14 00:59:34] 新任务 ↓
  rid       = 6cbe5ecf-9e7a-4512-9006-dd6089ebb093
  channel   = chat
  from      = yeweizhi_mobile
  cid       = cli-11998e20
  内容      = 你好 Hermes,请用一句话回复我。
  → 处理后运行: python hermes_worker.py reply 6cbe5ecf "<回复文本>"
[watch] 当前 pending 总数 = 1
```

**看到这种提示行,就按 §3 的 channel 规则处理,然后用提示行最下面那条 `reply`
命令回投。**没有提示行就保持等待,不要打扰用户。

启动时它会先把当前池里**已有的积压任务**全部播报一次(标记为「积压任务」),
所以即使你刚接班,也不会漏旧货。

如果只想看一眼当前状态、不想长跑:`python hermes_worker.py watch --once`。

---

## 1. 看看现在有没有新任务(临时查询)

```
python hermes_worker.py list
```

输出形如:

```
待处理任务:2
[1] rid=06a3951d…  channel=chat       from=yeweizhi_mobile    age=12s
     type=task     cid=cli-20260513-001
     内容: 你好,今天北京天气怎么样?
[2] rid=761cd58e…  channel=shell      from=ops-laptop         age=5s
     type=task     cid=ops-cron-7788
     内容: ...
```

字段含义:

| 字段 | 说明 |
|---|---|
| `rid` | 任务的唯一 ID(前 8 位即可索引,本工具支持前缀匹配) |
| `channel` | **路由用的渠道名**。请按 channel 决定怎么处理(见 §3) |
| `from` | 谁发来的(对方机器的 instance_id) |
| `age` | 任务在本机存在多久了 |
| `cid` | correlation_id,**回投时会被原样带回**,对方靠它认领结果 |
| `内容` | `payload_json.input_text`(如有) |

如果想看某条任务的完整原文(包括所有自定义字段):

```
python hermes_worker.py show 06a3951d
```

---

## 2. 处理完,把结果发回去

```
python hermes_worker.py reply <rid> "<你的回复文本>"
```

例:

```
python hermes_worker.py reply 06a3951d "北京今天晴,气温 18-26℃,适合出行。"
```

成功后:

- 自动把回复发回**发起方那台机器**(脚本会从 `payload_json._from_instance_id` 取地址,你不用关心)
- 自动带上原 `correlation_id`,对方能精确匹配上自己的请求
- 本地任务文件自动清理掉

如果失败(网络抖动等),任务文件**保留**,直接重跑 `reply` 即可重试。

> 需要回投结构化结果(不是纯文本)?用 `reply-json <rid> '<JSON>'`,或
> `reply-json <rid> @result.json` 从文件读。脚本会自动补上 `answered_at` /
> `answered_by` 元数据。

---

## 3. 不同 channel 的处理策略(可扩展)

你拿到一条任务后,先看它的 `channel`。**目前约定如下,以后可继续扩**:

| channel | 含义 | 你的处理方式 |
|---|---|---|
| `chat` 或缺省 | 自然语言对话/问答 | 直接用对话能力生成答案,`reply` 回投 |
| `summarize` | 需要总结 | 读 `payload_json.input_text` 给出摘要 |
| `lookup` | 信息查询 | 用工具/记忆库找答案 |
| 其他未知值 | 不认识的渠道 | 把任务交还(见下) |

### `chat` + 用户要「讲笑话」

若 Hermes 的 `bridge-task` webhook 已加载 skill **`devops/basketball-jokes`**
(见 Hermes 仓库 `skills/devops/basketball-jokes/SKILL.md`),则讲笑话时**只许篮球题材**,
一条即可;不要编程序员等与篮球无关的笑话。配置方式:本机
`webhook_subscriptions.json` 里为 `bridge-task` 设置
`"skills": ["devops/basketball-jokes"]`(gateway 会热加载)。

**遇到不认识的 channel 或你判断无法处理**:

```
python hermes_worker.py reply <rid> "暂不支持此 channel: <名字>"
```

或者直接丢弃,不回投(慎用,对方会一直收不到结果):

```
python hermes_worker.py done <rid>
```

---

## 4. 常见问题

**Q: `list` 总是空,但守护进程日志里看到"已写入本地池"。**
A: 大概率是你或者别人开了多个消费者(比如 `consume_pool.py`)在抢任务。检查:
```
Get-CimInstance Win32_Process -Filter "Name like '%python%'" | Select ProcessId, CommandLine
```

**Q: `reply` 报 `_from_instance_id 不存在,无法回投`。**
A: 说明这条任务是通过普通 `submit`(广播投)而不是 `submit_to`(点对点投)进来的,
没有"发件人地址"。你可以 `done` 标记完成,或者询问发送方让他改用 `submit_to`。

**Q: `reply` 报 `submit_to 失败`,网络问题。**
A: 任务文件保留着,稍后重跑同一条 `reply` 命令即可。**不要**手动删文件。

**Q: 任务积压很多,想批量处理?**
A: `python hermes_worker.py list --json` 输出 JSON 数组,你可以遍历后逐条
`reply`。不过更推荐**人工/Hermes 逐条看内容**,机器堆积本身就该报警。

---

## 5. 整套数据流(只读,辅助理解)

```
[请求方机器 A]
    │  对 S 端 POST /submit_to (to_instance_id = 本机)
    ▼
[S 端服务器]
    │  在 payload_json 里塞 _from_instance_id = A
    │  排队等本机 pull
    ▼
[本机 aidun_bridge_c 守护进程]
    │  GET /inbox/pull → 拉到任务 → 写到 data/pending/<rid>.json
    ▼
[Hermes(你)]
    │  hermes_worker.py list  →  看到任务
    │  → 处理 → 
    │  hermes_worker.py reply <rid> "<结果>"
    ▼
[hermes_worker.py]
    │  POST /submit_to (to_instance_id = A, correlation_id = 原 cid)
    │  → 删本地文件
    ▼
[A 机器的守护进程]
    │  → 拉到结果 → 业务消费
```

要点:**你只需要会用 `list` / `show` / `reply` / `done` 这 4 个命令。**
其他所有事情(找回投地址、保留 correlation_id、清理本地文件)都由
`hermes_worker.py` 替你处理。
