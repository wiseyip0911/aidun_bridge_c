"""aidun-chat: 本机消息时间线 + 发送 CLI。

本工具复用 `bridge-c-core` 的 `messages_log`(由守护进程和 `KqPoolClient` 自动
追加),把"已发 / 已收"以同一条时间线展示出来,并提供发送 / 查询实例名单两
个能力。它不是聊天会话:**没有多轮上下文,只是 timeline + send**。

子命令
======

    aidun-chat peers                       # 拉服务端的实例名单(directory)
    aidun-chat send -t <peer> "<文本>"      # 默认 channel=lookup
    aidun-chat send -t <peer> -c chat "<txt>"   # 纯闲聊显式指定 chat
    aidun-chat send -t <peer> --json '<json>'   # 自定义 payload_json
    aidun-chat log                         # 展示全部时间线(最新 50 条)
    aidun-chat log --peer yeweizhi_mobile  # 只看与某实例的往来
    aidun-chat log --limit 200             # 调最近条数
    aidun-chat log --follow                # 实时跟新行(类似 tail -F)
    aidun-chat log --json                  # 给程序消费的 JSON 数组

设计要点
========

- `aidun-chat` 完全不和服务端"轮询":新消息全靠守护进程写 messages.jsonl,
  这边只读文件 / 调 client.submit_to。
- 默认 messages.jsonl 路径与守护进程对齐(env `KQ_POOL_MESSAGE_LOG_PATH`
  没设时回退到 `<repo>/data/messages.jsonl`)。
- 退出码:0 成功;2 参数错;1 内部错。
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


# Windows 终端中文不乱码
try:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    sys.stderr.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
except Exception:
    pass


# ---------------------------------------------------------------------------
# .env / 路径
# ---------------------------------------------------------------------------

def _candidate_dirs() -> list[Path]:
    seen: set[Path] = set()
    out: list[Path] = []
    for base in [Path.cwd(), Path(__file__).resolve().parent]:
        for parent in [base, *base.parents]:
            if parent in seen:
                continue
            seen.add(parent)
            out.append(parent)
    return out


def _autoload_dotenv() -> None:
    try:
        from dotenv import load_dotenv  # type: ignore

        for parent in _candidate_dirs():
            cand = parent / ".env"
            if cand.exists():
                load_dotenv(cand, override=False)
                return
        return
    except Exception:
        pass
    for parent in _candidate_dirs():
        cand = parent / ".env"
        if not cand.exists():
            continue
        try:
            for raw in cand.read_text("utf-8").splitlines():
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


def resolve_message_log_path() -> Path:
    """与守护进程对齐的消息总账文件路径(绝对路径)。"""
    return _resolve_log_path()


def read_message_log_rows(log_path: Path | None = None) -> list[dict[str, Any]]:
    """读取 ``messages.jsonl`` 全部行并解析为 dict 列表。"""
    p = log_path or _resolve_log_path()
    return _read_rows(p)


def _resolve_log_path() -> Path:
    """与守护进程对齐的总账位置。"""
    _autoload_dotenv()
    env_v = os.environ.get("KQ_POOL_MESSAGE_LOG_PATH", "").strip()
    if env_v:
        p = Path(env_v)
        return p if p.is_absolute() else (Path.cwd() / p).resolve()
    cwd_default = Path.cwd() / "data" / "messages.jsonl"
    if cwd_default.exists():
        return cwd_default
    repo_root = Path(__file__).resolve().parents[2]
    return repo_root / "data" / "messages.jsonl"


# ---------------------------------------------------------------------------
# Client 构造
# ---------------------------------------------------------------------------

def _load_client():
    _autoload_dotenv()
    try:
        from aidun_bridge_c import KqPoolClient  # type: ignore
    except Exception as e:
        sys.stderr.write(f"[ERR] 导入 aidun_bridge_c 失败,先 pip install -e .: {e}\n")
        sys.exit(1)
    try:
        return KqPoolClient()
    except ValueError as e:
        sys.stderr.write(f"[ERR] KqPoolClient 构造失败(常见原因:KQ_POOL_API_KEY 未设): {e}\n")
        sys.exit(1)


def _self_instance_id() -> str:
    return os.environ.get("KQ_POOL_INSTANCE_ID", "").strip()


# ---------------------------------------------------------------------------
# 时间线读取
# ---------------------------------------------------------------------------

def _read_rows(log_path: Path) -> list[dict[str, Any]]:
    if not log_path.exists():
        return []
    out: list[dict[str, Any]] = []
    try:
        text = log_path.read_text("utf-8")
    except OSError as e:
        sys.stderr.write(f"[WARN] 读消息总账失败: {e}\n")
        return []
    for raw in text.splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            out.append(json.loads(raw))
        except json.JSONDecodeError:
            continue
    return out


def _ts_local(iso_ts: str) -> str:
    if not iso_ts:
        return ""
    raw = iso_ts.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(raw)
    except ValueError:
        return iso_ts
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone().strftime("%Y-%m-%d %H:%M:%S")


def _arrow(direction: str) -> str:
    return "→" if direction == "outbound" else "←"


def _format_row(row: dict[str, Any]) -> str:
    ts = _ts_local(row.get("ts", ""))
    direction = row.get("direction", "?")
    peer = row.get("peer_instance_id") or "?"
    channel = row.get("channel") or ""
    rtype = row.get("record_type") or ""
    text = row.get("text") or ""
    if len(text) > 200:
        text = text[:197] + "..."
    parts = [
        f"[{ts}]",
        f"{_arrow(direction)} {peer:<22s}",
        f"{(channel or '-'):<8s}",
        f"{(rtype or '-'):<8s}",
        text,
    ]
    return " ".join(parts)


def _filter_rows(
    rows: list[dict[str, Any]],
    *,
    peer: str | None = None,
    direction: str | None = None,
) -> list[dict[str, Any]]:
    out = []
    for r in rows:
        if peer and (r.get("peer_instance_id") or "") != peer:
            continue
        if direction and (r.get("direction") or "") != direction:
            continue
        out.append(r)
    return out


# ---------------------------------------------------------------------------
# 子命令:peers
# ---------------------------------------------------------------------------

def cmd_peers(args: argparse.Namespace) -> int:
    client = _load_client()
    try:
        resp = client.directory()
    except Exception as e:
        sys.stderr.write(f"[ERR] directory() 失败: {e}\n")
        return 1
    finally:
        client.close()

    items = resp.get("items") or []
    if args.json:
        print(json.dumps(items, ensure_ascii=False, indent=2))
        return 0
    if not items:
        print("(服务端 directory 为空)")
        return 0

    me = _self_instance_id()
    print(f"实例名单(共 {len(items)} 个,本机={me or '<未配置>'})")
    print("-" * 78)
    for it in items:
        mark = " *" if it.get("instance_id") == me else "  "
        iid = it.get("instance_id", "")
        label = it.get("display_name") or it.get("name") or ""
        print(f"{mark} {iid:<24s} {label}")
    print()
    print(f"用法: aidun-chat send -t <instance_id> \"<文本>\"")
    return 0


# ---------------------------------------------------------------------------
# 子命令:send
# ---------------------------------------------------------------------------

def cmd_send(args: argparse.Namespace) -> int:
    text = (args.text or "").strip()
    payload_json_arg = args.json_payload
    if not text and not payload_json_arg:
        sys.stderr.write("[ERR] 必须给 <text> 或 --json '<payload>'。\n")
        return 2

    if payload_json_arg:
        raw = payload_json_arg
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
            sys.stderr.write("[ERR] payload 必须是 JSON 对象。\n")
            return 2
    else:
        payload = {
            "channel": args.channel or "lookup",
            "input_text": text,
        }
        if args.channel:
            payload["channel"] = args.channel
        me = _self_instance_id()
        if me:
            payload.setdefault("source", me)

    cid = args.correlation_id or f"msg-{uuid.uuid4().hex[:8]}"

    body = {
        "to_instance_id": args.to,
        "correlation_id": cid,
        "record_type": args.record_type,
        "payload_json": payload,
    }

    client = _load_client()
    try:
        resp = client.submit_to(body)
    except Exception as e:
        sys.stderr.write(f"[ERR] submit_to 失败: {e}\n")
        return 1
    finally:
        client.close()

    rid = resp.get("record_id", "?")
    if args.json_out:
        print(json.dumps({"record_id": rid, "correlation_id": cid, "response": resp}, ensure_ascii=False, indent=2))
    else:
        print(f"[OK] 已发到 {args.to} (record_id={rid}, correlation_id={cid})")
    return 0


# ---------------------------------------------------------------------------
# 子命令:log
# ---------------------------------------------------------------------------

def cmd_log(args: argparse.Namespace) -> int:
    log_path = _resolve_log_path()
    if not log_path.exists():
        sys.stderr.write(
            f"[INFO] 消息总账还不存在: {log_path}\n"
            "       守护进程拉到第一条消息、或本机发一条 aidun-chat send 后会自动创建。\n"
        )
        return 0 if not args.follow else _follow(log_path, args)

    rows = _read_rows(log_path)
    rows = _filter_rows(rows, peer=args.peer, direction=args.direction)

    if args.json:
        # 默认整段输出;limit 仍生效
        if args.limit and args.limit > 0:
            rows = rows[-args.limit:]
        print(json.dumps(rows, ensure_ascii=False, indent=2))
        return 0 if not args.follow else _follow(log_path, args)

    limit = args.limit if args.limit and args.limit > 0 else 50
    tail_rows = rows[-limit:]
    if not tail_rows:
        print(f"(无匹配记录) log={log_path}")
        return 0 if not args.follow else _follow(log_path, args)

    me = _self_instance_id()
    print(f"消息时间线  log={log_path}  本机={me or '<未配置>'}  显示 {len(tail_rows)}/{len(rows)}")
    print("-" * 100)
    for row in tail_rows:
        print(_format_row(row))

    if args.follow:
        return _follow(log_path, args)
    return 0


def _follow(log_path: Path, args: argparse.Namespace) -> int:
    """tail -F 模式:打印新追加的行(支持文件被重新创建)。"""
    print()
    print("[follow] 实时跟新行,Ctrl+C 退出...")
    sys.stdout.flush()

    inode_ref = None
    fh = None
    pos = 0
    if log_path.exists():
        fh = log_path.open("r", encoding="utf-8")
        fh.seek(0, 2)
        pos = fh.tell()
        try:
            inode_ref = log_path.stat().st_ino
        except OSError:
            inode_ref = None

    try:
        while True:
            if log_path.exists():
                cur_inode = None
                try:
                    cur_inode = log_path.stat().st_ino
                except OSError:
                    cur_inode = None
                rotated = (inode_ref is not None and cur_inode is not None and cur_inode != inode_ref)
                if fh is None or rotated:
                    if fh is not None:
                        try:
                            fh.close()
                        except Exception:
                            pass
                    fh = log_path.open("r", encoding="utf-8")
                    fh.seek(0)
                    pos = 0
                    inode_ref = cur_inode
                fh.seek(pos)
                for raw in fh:
                    raw = raw.strip()
                    if not raw:
                        continue
                    try:
                        row = json.loads(raw)
                    except json.JSONDecodeError:
                        continue
                    if args.peer and (row.get("peer_instance_id") or "") != args.peer:
                        continue
                    if args.direction and (row.get("direction") or "") != args.direction:
                        continue
                    if args.json:
                        print(json.dumps(row, ensure_ascii=False))
                    else:
                        print(_format_row(row))
                    sys.stdout.flush()
                pos = fh.tell()
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[follow] 已退出。")
        return 0
    finally:
        if fh is not None:
            try:
                fh.close()
            except Exception:
                pass


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="aidun-chat",
        description="Aidun 桥消息时间线 + 发送 CLI(已发/已收同一条时间线)。",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    pp = sub.add_parser("peers", help="拉服务端实例名单")
    pp.add_argument("--json", action="store_true", help="以 JSON 输出")
    pp.set_defaults(func=cmd_peers)

    ps = sub.add_parser("send", help="给某实例发一条消息")
    ps.add_argument("-t", "--to", required=True, help="接收方 instance_id")
    ps.add_argument(
        "-c", "--channel", default="lookup",
        help="payload_json.channel,默认 lookup(查询/走工具);纯闲聊选 chat",
    )
    ps.add_argument(
        "--record-type", default="task",
        help="record_type,默认 task(回投时一般用 result)",
    )
    ps.add_argument(
        "--correlation-id", default="",
        help="可选;不传则自动生成 msg-<hex8>",
    )
    ps.add_argument(
        "--json", dest="json_payload", default="",
        help='可选;直接指定 payload_json(JSON 字符串或 @path/to.json),与 <text> 二选一',
    )
    ps.add_argument(
        "--json-out", action="store_true",
        help="以 JSON 输出发送结果(给脚本消费)",
    )
    ps.add_argument(
        "text", nargs="?", default="",
        help="要发的文本(被填到 payload_json.input_text)",
    )
    ps.set_defaults(func=cmd_send)

    pl = sub.add_parser("log", help="展示已发 / 已收消息时间线")
    pl.add_argument("--peer", default="", help="只看与该 instance_id 的往来")
    pl.add_argument(
        "--direction", choices=["inbound", "outbound"], default="",
        help="只看 inbound 或 outbound",
    )
    pl.add_argument(
        "--limit", type=int, default=50,
        help="显示最近 N 条,默认 50;<=0 表示不限",
    )
    pl.add_argument("--json", action="store_true", help="以 JSON 数组输出")
    pl.add_argument(
        "-f", "--follow", action="store_true",
        help="跟随新行(类似 tail -F),Ctrl+C 退出",
    )
    pl.set_defaults(func=cmd_log)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args) or 0)


if __name__ == "__main__":
    raise SystemExit(main())
