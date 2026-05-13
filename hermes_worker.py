"""Hermes 任务收件箱 / 回复发件箱(Aidun C 端专用)。

设计目标:让 Hermes 在不写任何代码的前提下,通过 4 个简单命令完成
「收任务 -> 处理 -> 回投结果」的闭环。

使用方法
========

前置:本机 `aidun_bridge_c` 守护进程已在运行,正在把任务文件写到
`data/pending/<record_id>.json`。

Hermes 只需要记住下面 4 个子命令:

    python hermes_worker.py list                       # 列出当前待处理任务
    python hermes_worker.py show <rid>                 # 看某条任务的完整 JSON
    python hermes_worker.py reply <rid> "<回复文本>"   # 把文本结果回投给请求方
    python hermes_worker.py done <rid>                 # 不回复,只把这条任务从本地丢掉

`rid` 支持只写前 8 位(或更长前缀),会自动匹配唯一文件。

进阶用法(很少用到):

    python hermes_worker.py reply-json <rid> '<json>'  # 用任意 JSON 作为 payload 回复
    python hermes_worker.py list --channel chat        # 只列 channel=chat 的任务
    python hermes_worker.py list --json                # 以 JSON 数组输出(给程序消费)

退出码:0 成功,2 参数/匹配错误,1 内部错误。
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# 配置
# ---------------------------------------------------------------------------

POOL_DIR = Path("data/pending")

# Windows 终端中文不乱码
try:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    sys.stderr.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
except Exception:
    pass


# ---------------------------------------------------------------------------
# 加载本机适配仓的 client(自动读 .env 里的 KQ_POOL_API_KEY)
# ---------------------------------------------------------------------------

def _autoload_dotenv() -> None:
    """在当前工作目录及其父目录里找 `.env` 并加载到 os.environ。

    与 `python -m aidun_bridge_c` 的行为对齐:先用 python-dotenv,再退化到
    简单手解析,缺包/缺文件都安静跳过。
    """
    import os

    # 先尝试用 python-dotenv(bridge-c-core 已经把它列成依赖)
    try:
        from dotenv import load_dotenv  # type: ignore

        for parent in [Path.cwd(), *Path.cwd().parents]:
            candidate = parent / ".env"
            if candidate.exists():
                load_dotenv(candidate, override=False)
                return
        return
    except Exception:
        pass

    # 退化路径:手工解析,只支持最简单的 KEY=VALUE
    for parent in [Path.cwd(), *Path.cwd().parents]:
        candidate = parent / ".env"
        if not candidate.exists():
            continue
        try:
            for raw in candidate.read_text("utf-8").splitlines():
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                k = k.strip()
                v = v.strip().strip('"').strip("'")
                if k and k not in os.environ:
                    os.environ[k] = v
        except Exception:
            pass
        return


def _load_client():
    """延迟导入,避免 list/show/done 这种不需要联网的命令也强依赖网络栈。"""
    _autoload_dotenv()
    try:
        from aidun_bridge_c import KqPoolClient  # type: ignore
    except Exception as e:
        sys.stderr.write(
            f"[ERR] 无法导入 aidun_bridge_c。请确认本仓库已 `pip install .`。详情: {e}\n"
        )
        sys.exit(1)

    try:
        return KqPoolClient()
    except ValueError as e:
        sys.stderr.write(
            f"[ERR] KqPoolClient 构造失败(多半是 KQ_POOL_API_KEY 没配): {e}\n"
        )
        sys.exit(1)


# ---------------------------------------------------------------------------
# 工具:读 / 匹配 / 格式化
# ---------------------------------------------------------------------------

def _load_record(path: Path) -> dict:
    return json.loads(path.read_text("utf-8"))


def _list_files() -> list[Path]:
    if not POOL_DIR.exists():
        return []
    return sorted(POOL_DIR.glob("*.json"))


def _match_rid(rid_prefix: str) -> Path:
    """根据 `rid_prefix` 在 pending 目录里找唯一匹配的文件。

    支持完整 rid 或前缀(>=4 位即可,只要能唯一匹配)。
    匹配不到或多个匹配都 sys.exit(2)。
    """
    prefix = (rid_prefix or "").strip()
    if not prefix:
        sys.stderr.write("[ERR] 必须提供 record_id 或它的前缀。\n")
        sys.exit(2)

    files = _list_files()
    hits = [fp for fp in files if fp.stem.startswith(prefix)]
    if not hits:
        sys.stderr.write(f"[ERR] 找不到匹配的任务,前缀 = {prefix!r}\n")
        if files:
            sys.stderr.write("  当前 pending:\n")
            for fp in files:
                sys.stderr.write(f"    {fp.stem}\n")
        sys.exit(2)
    if len(hits) > 1:
        sys.stderr.write(
            f"[ERR] 前缀 {prefix!r} 匹配到 {len(hits)} 条,请再多输几位:\n"
        )
        for fp in hits:
            sys.stderr.write(f"    {fp.stem}\n")
        sys.exit(2)
    return hits[0]


def _channel_of(record: dict) -> str:
    return str(record.get("payload_json", {}).get("channel") or "(未声明)")


def _from_of(record: dict) -> str:
    return str(record.get("payload_json", {}).get("_from_instance_id") or "(未知)")


def _age_str(created_at: str) -> str:
    if not created_at:
        return "?"
    raw = str(created_at).replace("Z", "+00:00")
    try:
        ts = datetime.fromisoformat(raw)
    except ValueError:
        return "?"
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    delta = datetime.now(timezone.utc) - ts
    sec = int(delta.total_seconds())
    if sec < 60:
        return f"{sec}s"
    if sec < 3600:
        return f"{sec // 60}m"
    if sec < 86400:
        return f"{sec // 3600}h"
    return f"{sec // 86400}d"


# ---------------------------------------------------------------------------
# 子命令:list
# ---------------------------------------------------------------------------

def cmd_list(args: argparse.Namespace) -> int:
    files = _list_files()
    records: list[tuple[Path, dict]] = []
    for fp in files:
        try:
            rec = _load_record(fp)
        except Exception as e:
            sys.stderr.write(f"[WARN] 跳过损坏文件 {fp.name}: {e}\n")
            continue
        if args.channel and _channel_of(rec) != args.channel:
            continue
        records.append((fp, rec))

    if args.json:
        out = []
        for fp, rec in records:
            out.append(
                {
                    "rid": rec.get("record_id", fp.stem),
                    "file": str(fp),
                    "channel": _channel_of(rec),
                    "from": _from_of(rec),
                    "record_type": rec.get("record_type", ""),
                    "correlation_id": rec.get("correlation_id", ""),
                    "created_at": rec.get("created_at", ""),
                    "input_text": rec.get("payload_json", {}).get("input_text", ""),
                }
            )
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return 0

    if not records:
        print("(待处理任务:0)")
        return 0

    print(f"待处理任务:{len(records)}")
    print("-" * 78)
    for idx, (fp, rec) in enumerate(records, start=1):
        rid = rec.get("record_id", fp.stem)
        text = rec.get("payload_json", {}).get("input_text", "")
        if len(text) > 80:
            text = text[:77] + "..."
        print(
            f"[{idx}] rid={rid[:8]}…  "
            f"channel={_channel_of(rec):<10s} "
            f"from={_from_of(rec):<22s} "
            f"age={_age_str(rec.get('created_at', '')):>4s}"
        )
        print(f"     type={rec.get('record_type', ''):<8s} "
              f"cid={rec.get('correlation_id', '')}")
        if text:
            print(f"     内容: {text}")
        print()
    return 0


# ---------------------------------------------------------------------------
# 子命令:show
# ---------------------------------------------------------------------------

def cmd_show(args: argparse.Namespace) -> int:
    fp = _match_rid(args.rid)
    rec = _load_record(fp)
    print(json.dumps(rec, ensure_ascii=False, indent=2))
    return 0


# ---------------------------------------------------------------------------
# 子命令:reply
# ---------------------------------------------------------------------------

def _do_reply(rid_prefix: str, payload_json: dict, *, mark_done: bool = True) -> int:
    fp = _match_rid(rid_prefix)
    rec = _load_record(fp)

    to_instance_id = rec.get("payload_json", {}).get("_from_instance_id")
    correlation_id = rec.get("correlation_id", "")
    if not to_instance_id:
        sys.stderr.write(
            f"[ERR] 任务 {fp.stem} 的 payload_json 里没有 _from_instance_id,无法回投。\n"
            "  这通常说明发送方走的不是 submit_to(协议要求 S 端在 submit_to 时注入此字段)。\n"
            "  请用 `done` 命令把这条任务标记完成,或自行处理。\n"
        )
        return 2

    client = _load_client()
    try:
        body = {
            "to_instance_id": to_instance_id,
            "correlation_id": correlation_id,
            "record_type": "result",
            "payload_json": payload_json,
        }
        resp = client.submit_to(body)
    except Exception as e:
        sys.stderr.write(f"[ERR] submit_to 失败,任务文件保留以便重试: {e}\n")
        return 1
    finally:
        client.close()

    print(
        f"[OK] 已回投到 {to_instance_id} "
        f"(record_id={resp.get('record_id', '?')}, "
        f"correlation_id={correlation_id})"
    )

    if mark_done:
        try:
            fp.unlink()
            print(f"[OK] 已清理本地任务文件 {fp.name}")
        except OSError as e:
            sys.stderr.write(f"[WARN] 删除任务文件失败,可手动清理: {e}\n")
    return 0


def cmd_reply(args: argparse.Namespace) -> int:
    text = args.text or ""
    if not text.strip():
        sys.stderr.write("[ERR] 回复文本不能为空。\n")
        return 2
    payload = {
        "status": "ok",
        "result_text": text,
        "answered_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "answered_by": "hermes",
    }
    return _do_reply(args.rid, payload)


def cmd_reply_json(args: argparse.Namespace) -> int:
    raw = args.payload
    if raw.startswith("@"):
        try:
            raw = Path(raw[1:]).read_text("utf-8")
        except OSError as e:
            sys.stderr.write(f"[ERR] 读 payload 文件失败: {e}\n")
            return 2
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.stderr.write(f"[ERR] payload 不是合法 JSON: {e}\n")
        return 2
    if not isinstance(payload, dict):
        sys.stderr.write("[ERR] payload 必须是 JSON 对象(顶层 {})。\n")
        return 2
    payload.setdefault(
        "answered_at",
        datetime.now(timezone.utc).isoformat(timespec="seconds"),
    )
    payload.setdefault("answered_by", "hermes")
    return _do_reply(args.rid, payload)


# ---------------------------------------------------------------------------
# 子命令:watch
# ---------------------------------------------------------------------------

def _summarize(rec: dict, fp: Path) -> str:
    rid = rec.get("record_id", fp.stem)
    pj = rec.get("payload_json", {}) or {}
    channel = pj.get("channel") or "(未声明)"
    sender = pj.get("_from_instance_id") or "(未知)"
    cid = rec.get("correlation_id", "")
    text = pj.get("input_text", "") or ""
    if len(text) > 120:
        text = text[:117] + "..."
    lines = [
        f"  rid       = {rid}",
        f"  channel   = {channel}",
        f"  from      = {sender}",
        f"  cid       = {cid}",
    ]
    if text:
        lines.append(f"  内容      = {text}")
    lines.append(
        f"  → 处理后运行: python hermes_worker.py reply {rid[:8]} \"<回复文本>\""
    )
    return "\n".join(lines)


def cmd_watch(args: argparse.Namespace) -> int:
    interval = max(1, int(args.interval))
    once = bool(args.once)
    quiet = bool(args.quiet)

    POOL_DIR.mkdir(parents=True, exist_ok=True)

    seen: set[str] = set()
    # 启动时把当前已存在的任务也"播报"一次,免得 Hermes 起来时漏掉旧货
    if not once and not quiet:
        print(
            f"[watch] 监听 {POOL_DIR.resolve()}, 每 {interval}s 扫描一次。"
            " 按 Ctrl+C 退出。"
        )

    first_pass = True
    try:
        while True:
            current: set[str] = set()
            new_records: list[tuple[Path, dict]] = []
            for fp in _list_files():
                current.add(fp.stem)
                if fp.stem in seen:
                    continue
                try:
                    rec = _load_record(fp)
                except Exception as e:
                    sys.stderr.write(f"[watch] 跳过损坏文件 {fp.name}: {e}\n")
                    seen.add(fp.stem)
                    continue
                new_records.append((fp, rec))
                seen.add(fp.stem)

            # 文件被 reply/done 清掉之后,把 rid 从 seen 移除,
            # 这样如果以后服务端真的再下发同 rid(理论上不会),也还能再次提醒
            for stale in list(seen):
                if stale not in current:
                    seen.discard(stale)

            for fp, rec in new_records:
                ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                kind = "积压任务" if first_pass else "新任务"
                print(f"[{ts}] {kind} ↓\n{_summarize(rec, fp)}")
                sys.stdout.flush()

            if new_records:
                # 总结一下队列长度,提示 Hermes 处理顺序
                remaining = len(current)
                print(f"[watch] 当前 pending 总数 = {remaining}")
                sys.stdout.flush()

            if once:
                return 0

            first_pass = False
            time.sleep(interval)
    except KeyboardInterrupt:
        if not quiet:
            print("\n[watch] 已退出。")
        return 0


# ---------------------------------------------------------------------------
# 子命令:done
# ---------------------------------------------------------------------------

def cmd_done(args: argparse.Namespace) -> int:
    fp = _match_rid(args.rid)
    try:
        fp.unlink()
    except OSError as e:
        sys.stderr.write(f"[ERR] 删除任务文件失败: {e}\n")
        return 1
    print(f"[OK] 已标记完成(未回投): {fp.name}")
    return 0


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="hermes_worker",
        description="Aidun bridge_c 本机 Hermes 任务处理工具。",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    pl = sub.add_parser("list", help="列出当前待处理任务")
    pl.add_argument("--channel", help="只列指定 channel 的任务")
    pl.add_argument("--json", action="store_true", help="以 JSON 数组输出")
    pl.set_defaults(func=cmd_list)

    ps = sub.add_parser("show", help="显示某条任务完整 JSON")
    ps.add_argument("rid", help="record_id(或前缀)")
    ps.set_defaults(func=cmd_show)

    pr = sub.add_parser("reply", help="给某条任务回投文本结果(成功后自动清理本地文件)")
    pr.add_argument("rid", help="record_id(或前缀)")
    pr.add_argument("text", help="回复文本")
    pr.set_defaults(func=cmd_reply)

    prj = sub.add_parser(
        "reply-json",
        help="给某条任务回投自定义 JSON payload(payload 可以用 @path/to/file.json 读文件)",
    )
    prj.add_argument("rid", help="record_id(或前缀)")
    prj.add_argument("payload", help='JSON 字符串,或 @文件路径')
    prj.set_defaults(func=cmd_reply_json)

    pd = sub.add_parser("done", help="不回投,只把任务从本地标记完成")
    pd.add_argument("rid", help="record_id(或前缀)")
    pd.set_defaults(func=cmd_done)

    pw = sub.add_parser(
        "watch",
        help="盯着 data/pending/,有新任务就在 stdout 打印提示行(前台长跑)",
    )
    pw.add_argument(
        "--interval", type=int, default=5, help="扫描间隔(秒),默认 5"
    )
    pw.add_argument(
        "--once", action="store_true", help="只扫一次后退出(用于诊断)"
    )
    pw.add_argument(
        "--quiet", action="store_true", help="静默模式,不打启动横幅"
    )
    pw.set_defaults(func=cmd_watch)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args) or 0)


if __name__ == "__main__":
    raise SystemExit(main())
