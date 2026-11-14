#!/usr/bin/env python3
"""用 Python 标准库试用 Gemini Decision 1，无需安装第三方依赖。

用法：
    在项目根目录 .env 中设置 gemini_decision_api_key=你的_API_Key（或设置 GEMINI_API_KEY）
    python3 evals/try_gemini_decision.py
    python3 evals/try_gemini_decision.py --text '收到的杯子碎了' --question '商品是否损坏？'

官方教程：https://aistudio.google.com/docs/decisions-api#quickstart
"""

import argparse
import json
import os
from pathlib import Path
import shlex
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def read_api_key(env_file=None):
    api_key = os.environ.get("GEMINI_API_KEY", "").strip()
    if api_key:
        return api_key

    explicit_env = env_file or os.environ.get("SIFT_ENV_FILE", "").strip()
    env_path = Path(explicit_env).expanduser().resolve() if explicit_env else Path(__file__).resolve().parent.parent / ".env"
    if not env_path.is_file():
        return ""
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        name, separator, value = line.partition("=")
        if separator and name.strip() in ("gemini_decision_api_key", "GEMINI_API_KEY"):
            values = shlex.split(value, comments=True)
            if len(values) != 1 or not values[0].strip():
                raise ValueError(".env 中的 Gemini API Key 必须是单个非空值。")
            return values[0].strip()
    return ""


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--text",
        default="The blue mug I ordered on Monday arrived cracked on Wednesday.",
        help="需要判断的文本",
    )
    parser.add_argument(
        "--question", default="Did the item arrive damaged?", help="一个是非问题"
    )
    parser.add_argument(
        "--env-file", type=Path, default=None, help="可选 .env 路径（默认读取仓库根目录 .env）"
    )
    args = parser.parse_args()
    if not args.text.strip() or not args.question.strip():
        parser.error("--text 和 --question 不能为空。")

    try:
        api_key = read_api_key(args.env_file)
    except (OSError, UnicodeError, ValueError) as error:
        parser.error(f"读取 .env 失败：{error}")
    if not api_key:
        parser.error("请在项目根目录 .env 设置 gemini_decision_api_key，或设置环境变量 GEMINI_API_KEY。")

    payload = {
        "model": "gemini-decision-1",
        "input": args.text,
        "questions": {
            "check": {"type": "noul", "instructions": args.question},
        },
    }
    request = Request(
        "https://generativelanguage.googleapis.com/v1beta/decisions",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
        method="POST",
    )
    try:
        with urlopen(request, timeout=30) as response:
            result = json.load(response)
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        print(
            f"API 请求失败（HTTP {error.code}）：\n{detail.replace(api_key, '[REDACTED]')}",
            file=sys.stderr,
        )
        return 1
    except (URLError, TimeoutError, UnicodeError, json.JSONDecodeError) as error:
        print(
            f"请求或响应解析失败：{str(error).replace(api_key, '[REDACTED]')}",
            file=sys.stderr,
        )
        return 1

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
