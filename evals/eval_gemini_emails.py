#!/usr/bin/env python3
"""使用 Gemini Decisions API 与本地确定性状态机评测 Sift 邮件分类策略。

用法：
    python3 evals/eval_gemini_emails.py run \
        --dataset evals/datasets/open-inbox-v1/emails.json \
        --gold evals/datasets/open-inbox-v1/gold-hydrogen-v1.json \
        --output evals/runs/open-inbox-v1-run01

只使用 Python 标准库，不依赖应用运行时，不修改任何邮箱。
参考标签（gold）不会放入 API 请求；每封邮件仅调用一次正交信号接口。
"""

import argparse
from collections import Counter, deque
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
from http.client import HTTPException
import json
import math
from pathlib import Path
import re
import statistics
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from email_rules import (
    ACTIONS,
    CATEGORIES,
    build_request,
    clean_body_text,
    is_boilerplate_stub,
    load_policy,
    resolve_decision,
)
from try_gemini_decision import read_api_key


MODEL = "gemini-decision-1"
ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/decisions"
DEFAULT_POLICY = Path(__file__).with_name("email_classification_policy.json")
RETRY_DELAY_RE = re.compile(r"retry in (\d+(?:\.\d+)?)s", re.IGNORECASE)


def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    path.chmod(0o600)


class EmailText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.chunks = []
        self.hidden = 0
        self.images = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "head"):
            self.hidden += 1
        elif not self.hidden:
            if tag in ("p", "div", "br", "tr", "li", "h1", "h2", "h3"):
                self.chunks.append("\n")
            if tag == "img":
                self.images += 1
                alt = dict(attrs).get("alt", "")
                if alt:
                    self.chunks.append(f" [image alt: {alt}] ")

    def handle_endtag(self, tag):
        if tag in ("script", "style", "head"):
            self.hidden = max(0, self.hidden - 1)
        elif not self.hidden and tag in ("p", "div", "tr", "li"):
            self.chunks.append("\n")

    def handle_data(self, data):
        if not self.hidden:
            self.chunks.append(data)


def extract_html_text(html_parts):
    parser = EmailText()
    for part in html_parts:
        parser.feed(part)
    parser.close()
    return clean_body_text("".join(parser.chunks)).strip(), parser.images


def prepare(source):
    exported = json.loads(source.read_text(encoding="utf-8"))
    samples = []
    for index, message in enumerate(exported["messages"], 1):
        headers = {h["name"].lower(): h["value"] for h in message["headers"]}
        parts = message["body_parts"]
        plain = [p["content"] for p in parts if p["mime_type"] == "text/plain"]
        html = [p["content"] for p in parts if p["mime_type"] == "text/html"]
        images = 0
        if plain:
            body = clean_body_text("\n".join(plain)).strip()
            representation = "full_plain_text"
        elif html:
            body, images = extract_html_text(html)
            representation = "text_extracted_from_full_html_with_image_alt"
        else:
            raise ValueError(f"邮件 {message['id']} 缺少文本或 HTML 正文。")
        samples.append({
            "id": f"email-{index:02d}",
            "gmail_id": message["id"],
            "source_url": message["source_url"],
            "email": {
                "from": headers.get("from", ""),
                "to": headers.get("to", ""),
                "subject": headers.get("subject", ""),
                "date": headers.get("date", ""),
                "body": body,
                "body_representation": representation,
                "has_attachments": message["has_attachments"],
                "unloaded_html_images": images,
                "body_is_image_only": (images > 0 and len(re.sub(r"\s", "", body)) < 150) or is_boilerplate_stub(body),
                "conversation_context_available": False,
                "truncated": False,
            },
        })
    path = source.with_name("emails.json")
    if path.exists():
        raise ValueError(f"样本已存在，拒绝覆盖：{path}")
    save_json(path, {"selection": exported["selection"], "samples": samples})
    print(json.dumps({
        "dataset": str(path),
        "count": len(samples),
        "body_characters": sum(len(s["email"]["body"]) for s in samples),
    }, ensure_ascii=False))


def summarize(rows):
    valid = [r for r in rows if "decision" in r]
    action_confusion = {gold: {pred: 0 for pred in ACTIONS} for gold in ACTIONS}
    for row in valid:
        action_confusion[row["gold"]["action"]][row["decision"]["action"]] += 1

    has_gold_categories = all(r["gold"].get("category") in CATEGORIES for r in rows)
    category_summary = None
    if has_gold_categories:
        cat_confusion = {gold: {pred: 0 for pred in CATEGORIES} for gold in CATEGORIES}
        for row in valid:
            cat_confusion[row["gold"]["category"]][row["decision"]["category"]] += 1
        category_summary = {
            "reference_distribution": dict(Counter(r["gold"]["category"] for r in rows)),
            "raw_category_agreement": {
                "correct": sum(r["decision"]["suggested_category"] == r["gold"]["category"] for r in valid),
                "total": len(rows),
            },
            "final_category_agreement": {
                "correct": sum(r["decision"]["category"] == r["gold"]["category"] for r in valid),
                "total": len(rows),
            },
            "confusion_reference_rows_final_columns": cat_confusion,
        }

    tokens = sum(r.get("response", {}).get("usage", {}).get("total_input_tokens", 0) for r in rows)
    result = {
        "total": len(rows),
        "completed": len(valid),
        "errors": len(rows) - len(valid),
        "reference_action_distribution": dict(Counter(r["gold"]["action"] for r in rows)),
        "raw_action_agreement": {
            "correct": sum(r["decision"]["suggested_action"] == r["gold"]["action"] for r in valid),
            "total": len(rows),
        },
        "final_action_agreement": {
            "correct": sum(r["decision"]["action"] == r["gold"]["action"] for r in valid),
            "total": len(rows),
        },
        "rule_override_count": sum(r["decision"]["action"] != r["decision"]["suggested_action"] for r in valid),
        "unsafe_trash_ids": [
            r["id"] for r in valid if r["decision"]["action"] == "trash" and r["gold"]["action"] != "trash"
        ],
        "action_confusion_reference_rows_final_columns": action_confusion,
        "category_evaluation": category_summary,
        "disagreements": [
            {
                "id": r["id"],
                "subject": r["subject"],
                "gold_action": r["gold"]["action"],
                "pred_action": r["decision"]["action"],
                "gold_category": r["gold"].get("category"),
                "pred_category": r["decision"]["category"],
                "review_reason": r["decision"].get("review_reason"),
            }
            for r in valid
            if r["decision"]["action"] != r["gold"]["action"]
            or (has_gold_categories and r["decision"]["category"] != r["gold"]["category"])
        ],
        "input_tokens": tokens,
        "output_tokens": sum(r.get("response", {}).get("usage", {}).get("total_output_tokens", 0) for r in rows),
        "equivalent_paid_cost_usd_at_0_10_per_million": round(tokens / 1_000_000 * 0.10, 6),
        "observed_median_seconds": round(statistics.median(r["elapsed_seconds"] for r in valid), 4) if valid else None,
    }
    return result


def write_report(output, rows, policy, annotator):
    summary = summarize(rows)
    save_json(output / "summary.json", summary)
    lines = [
        "# Sift 邮件分类评测报告（Superhuman 7 类 + 本地安全护栏）",
        "",
        f"- 策略版本：`{policy['version']}`",
        f"- 参考标注来源：`{annotator}`",
        "- 评测方式：每封邮件单次请求 `gemini-decision-1` 正交客观信号，由本地 Python 确定性状态机合成最终 `action` 与 `category`。",
        "",
        "```json",
        json.dumps(summary, ensure_ascii=False, indent=2),
        "```",
        "",
        "| 样本 | 主题 | 参考动作 | 预测动作 | 参考分类 | 预测分类 | 复核原因 | 话题标签 |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for row in rows:
        decision = row.get("decision", {})
        subject = row["subject"].replace("|", "\\|").replace("\n", " ")
        topics = "、".join(policy["topics"][key]["label"] for key in decision.get("topics", []))
        lines.append(
            f"| {row['id']} | {subject} | {row['gold']['action']} | {decision.get('action', 'ERROR')} "
            f"| {row['gold'].get('category', '-')} | {decision.get('category', 'ERROR')} "
            f"| {decision.get('review_reason') or '-'} | {topics} |"
        )
    lines += [
        "",
        "注：门槛为策略超参数，费用仅按官方输入单价估算，未查询实际账单。",
    ]
    (output / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (output / "report.md").chmod(0o600)
    return summary


def estimate_payload_tokens(payload):
    return max(1000, len(json.dumps(payload, ensure_ascii=False)) // 3)


def pace_for_tpm(window, estimated_tokens, max_tpm):
    if max_tpm <= 0:
        return
    while window:
        now = time.monotonic()
        while window and now - window[0][0] >= 61.0:
            window.popleft()
        used = sum(tokens for _, tokens in window)
        if not window or used + estimated_tokens <= max_tpm:
            break
        wait = max(0.5, 61.0 - (now - window[0][0]))
        time.sleep(wait)


def post_with_rate_limit_retry(payload, api_key, max_retries=4):
    encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    for attempt in range(max_retries + 1):
        request = Request(
            ENDPOINT,
            data=encoded,
            headers={"x-goog-api-key": api_key, "Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urlopen(request, timeout=45) as response:
                return json.load(response)
        except HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace").replace(api_key, "[REDACTED]")
            if error.code in (429, 502, 503, 504) and attempt < max_retries:
                match = RETRY_DELAY_RE.search(detail)
                if match:
                    delay = min(65.0, float(match.group(1)) + 2.0)
                elif error.code == 429:
                    delay = 61.0
                else:
                    delay = min(16.0, 2.0 * (2**attempt))
                time.sleep(delay)
                continue
            raise RuntimeError(f"HTTP {error.code}: {detail}") from None
        except (URLError, TimeoutError, HTTPException) as error:
            detail = str(error).replace(api_key, "[REDACTED]")
            if attempt < max_retries:
                time.sleep(min(16.0, 2.0 * (2**attempt)))
                continue
            raise RuntimeError(f"Network error: {detail}") from None


def run(args):
    dataset_bytes = args.dataset.read_bytes()
    gold_bytes = args.gold.read_bytes()
    policy_bytes = args.policy.read_bytes()
    dataset_doc = json.loads(dataset_bytes)
    samples = dataset_doc["samples"]
    gold_doc = json.loads(gold_bytes)
    annotator = gold_doc.get("_metadata", {}).get("annotator", "Reference labels") if isinstance(gold_doc, dict) else "Reference labels"
    annotations = gold_doc["annotations"] if isinstance(gold_doc, dict) and "annotations" in gold_doc else gold_doc
    policy = load_policy(args.policy)

    if len({s["id"] for s in samples}) != len(samples) or {s["id"] for s in samples} != set(annotations):
        raise ValueError("样本 ID 必须唯一，且与参考标签一一对应。")
    for sample_id, label in annotations.items():
        if label.get("action") not in ACTIONS:
            raise ValueError(f"{sample_id} 参考标签需要合法 action: {'/'.join(ACTIONS)}。")
        if "category" in label and label["category"] not in CATEGORIES:
            raise ValueError(f"{sample_id} 参考标签包含未知 category: {label['category']}。")

    for sample in samples:
        build_request(sample["email"], policy, MODEL, sample.get("conversation", []))

    env_file = getattr(args, "env_file", None)
    api_key = read_api_key(env_file)
    if not api_key:
        raise ValueError("请在项目根目录 .env 设置 gemini_decision_api_key，或传入 --env-file / GEMINI_API_KEY。")

    args.output.mkdir(parents=True, mode=0o700, exist_ok=False)
    rules_path = Path(__file__).with_name("email_rules.py")
    max_tpm = getattr(args, "max_tpm", 42000)
    manifest = {
        "started_at": datetime.now(timezone.utc).isoformat(),
        "model": MODEL,
        "dataset_sha256": hashlib.sha256(dataset_bytes).hexdigest(),
        "gold_sha256": hashlib.sha256(gold_bytes).hexdigest(),
        "policy_sha256": hashlib.sha256(policy_bytes).hexdigest(),
        "rules_sha256": hashlib.sha256(rules_path.read_bytes()).hexdigest(),
        "policy_version": policy["version"],
        "reference_annotator": annotator,
        "model_requests_per_email": 1,
        "local_rules": "standalone Python deterministic state machine; no application dependency",
        "mailbox_actions": "none; read-only offline evaluation",
        "gold_sent_to_model": False,
        "minimum_request_interval_seconds": args.interval,
        "max_input_tokens_per_minute": max_tpm,
    }
    save_json(args.output / "manifest.json", manifest)
    save_json(args.output / "policy.json", policy)
    (args.output / "email_rules.py.txt").write_bytes(rules_path.read_bytes())
    (args.output / "email_rules.py.txt").chmod(0o600)

    rows = []
    last_started = None
    token_window = deque()
    for sample in samples:
        email = sample["email"]
        conversation = sample.get("conversation", [])
        payload = build_request(email, policy, MODEL, conversation)
        save_json(args.output / f"{sample['id']}.request.json", payload)
        if last_started is not None:
            time.sleep(max(0, args.interval - (time.monotonic() - last_started)))
        pace_for_tpm(token_window, estimate_payload_tokens(payload), max_tpm)
        row = {"id": sample["id"], "subject": email.get("subject", ""), "gold": annotations[sample["id"]]}
        started = time.monotonic()
        last_started = started
        try:
            row["response"] = post_with_rate_limit_retry(payload, api_key)
            used_tokens = row["response"].get("usage", {}).get("total_input_tokens", estimate_payload_tokens(payload))
            token_window.append((started, used_tokens))
            row["decision"] = resolve_decision(row["response"], email, policy, conversation)
        except (OSError, HTTPException, UnicodeError, ValueError, KeyError, TypeError, RuntimeError) as error:
            row["error"] = str(error).replace(api_key, "[REDACTED]")
        row["elapsed_seconds"] = round(time.monotonic() - started, 4)
        rows.append(row)
        save_json(args.output / "results.json", rows)
        dec = row.get("decision", {})
        print(
            f"{sample['id']}: action={dec.get('action', 'ERROR')} category={dec.get('category', 'ERROR')} "
            f"(gold: {row['gold']['action']}/{row['gold'].get('category', '-')})",
            flush=True,
        )
    summary = write_report(args.output, rows, policy, annotator)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 1 if summary["errors"] else 0


def reevaluate_saved_run(args):
    """不重发网络请求，直接用最新本地规则/策略重新合成已有 results.json 并输出新报告。"""
    saved_rows = json.loads(args.results.read_text(encoding="utf-8"))
    samples = {s["id"]: s for s in json.loads(args.dataset.read_text(encoding="utf-8"))["samples"]}
    gold_doc = json.loads(args.gold.read_text(encoding="utf-8"))
    annotator = gold_doc.get("_metadata", {}).get("annotator", "Reference labels") if isinstance(gold_doc, dict) else "Reference labels"
    annotations = gold_doc["annotations"] if isinstance(gold_doc, dict) and "annotations" in gold_doc else gold_doc
    policy = load_policy(args.policy)

    args.output.mkdir(parents=True, mode=0o700, exist_ok=False)
    recomputed = []
    for old_row in saved_rows:
        sample = samples[old_row["id"]]
        new_row = {
            "id": old_row["id"],
            "subject": sample["email"].get("subject", ""),
            "gold": annotations[old_row["id"]],
            "response": old_row["response"],
            "elapsed_seconds": old_row.get("elapsed_seconds", 0.0),
        }
        new_row["decision"] = resolve_decision(
            old_row["response"], sample["email"], policy, sample.get("conversation", [])
        )
        recomputed.append(new_row)
    save_json(args.output / "results.json", recomputed)
    save_json(args.output / "policy.json", policy)
    summary = write_report(args.output, recomputed, policy, annotator)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    prep = commands.add_parser("prepare", help="整理连接器导出的邮件正文")
    prep.add_argument("--source", type=Path, required=True)

    evaluate = commands.add_parser("run", help="一次模型调用 + 本地 Python 合成规则评测")
    evaluate.add_argument("--dataset", type=Path, required=True)
    evaluate.add_argument("--gold", type=Path, required=True)
    evaluate.add_argument("--policy", type=Path, default=DEFAULT_POLICY)
    evaluate.add_argument("--env-file", type=Path, default=None, help="可选 .env 文件路径")
    evaluate.add_argument("--interval", type=float, default=4.0, help="请求最小间隔秒数，默认 4")
    evaluate.add_argument("--max-tpm", type=int, default=42000, help="每分钟输入 token 预算上限，默认 42000")
    evaluate.add_argument("--output", type=Path, required=True, help="尚不存在的新结果目录")

    replay = commands.add_parser("replay", help="不调用 API，基于已有 results.json 重跑本地状态机与偏好组合")
    replay.add_argument("--results", type=Path, required=True)
    replay.add_argument("--dataset", type=Path, required=True)
    replay.add_argument("--gold", type=Path, required=True)
    replay.add_argument("--policy", type=Path, default=DEFAULT_POLICY)
    replay.add_argument("--output", type=Path, required=True)

    args = parser.parse_args()
    if args.command == "run" and (not math.isfinite(args.interval) or not 0 <= args.interval <= 60):
        parser.error("--interval 必须在 0 到 60 秒之间。")
    try:
        if args.command == "prepare":
            prepare(args.source)
            return 0
        if args.command == "replay":
            return reevaluate_saved_run(args)
        return run(args)
    except (OSError, UnicodeError, ValueError, KeyError, TypeError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    sys.exit(main())
