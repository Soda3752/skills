#!/usr/bin/env python3
"""把問題 JSON 套進 template.html，產出可直接用瀏覽器開的本地表單。

用法：
  python3 build_form.py <questions.json> [--out <輸出.html>] [--no-open]

沒給 --out 時存到 ./.claude/questions/YYYY_MM_DD/HHMMSS_<標題>.html。
成功時 stdout 只印一行輸出檔的絕對路徑。
"""
import argparse
import datetime as dt
import html
import json
import re
import subprocess
import sys
from pathlib import Path

TEMPLATE = Path(__file__).resolve().parent.parent / "assets" / "template.html"
MAX_OPTIONS = 26


def fail(msg):
    print(f"[build_form] {msg}", file=sys.stderr)
    sys.exit(1)


def validate(data):
    if not isinstance(data, dict):
        fail("最外層必須是物件 {title, intro?, questions: [...]}")
    qs = data.get("questions")
    if not isinstance(qs, list) or not qs:
        fail("questions 必須是非空陣列")
    for i, q in enumerate(qs, 1):
        if not isinstance(q, dict) or not str(q.get("question", "")).strip():
            fail(f"Q{i} 缺少 question 文字")
        opts = q.get("options", [])
        if not isinstance(opts, list):
            fail(f"Q{i} 的 options 必須是陣列")
        if len(opts) > MAX_OPTIONS:
            fail(f"Q{i} 選項超過 {MAX_OPTIONS} 個")
        for j, o in enumerate(opts, 1):
            if not isinstance(o, dict) or not str(o.get("label", "")).strip():
                fail(f"Q{i} 第 {j} 個選項缺少 label")
            missing = [k for k in ("effect", "cost") if not str(o.get(k, "")).strip()]
            if missing:
                print(f"[build_form] 警告：Q{i} 選項「{o['label']}」沒寫 {'/'.join(missing)}", file=sys.stderr)
        if not q.get("multi") and sum(1 for o in opts if o.get("recommended")) > 1:
            print(f"[build_form] 警告：Q{i} 是單選題卻標了多個推薦", file=sys.stderr)


def slugify(title):
    s = re.sub(r"[\\/:*?\"<>|\s]+", "_", title).strip("_")
    return s[:40] or "questions"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("json_path")
    ap.add_argument("--out")
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()

    try:
        data = json.loads(Path(args.json_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        fail(f"讀不到或解析不了 JSON：{e}")
    validate(data)

    title = str(data.get("title") or "問題清單")
    now = dt.datetime.now()
    out = Path(args.out) if args.out else (
        Path.cwd() / ".claude" / "questions" / now.strftime("%Y_%m_%d")
        / f"{now.strftime('%H%M%S')}_{slugify(title)}.html"
    )
    out.parent.mkdir(parents=True, exist_ok=True)

    # </script> 會提早關閉 JSON 區塊，所以把 "</" 轉義
    payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    page = (TEMPLATE.read_text(encoding="utf-8")
            .replace("__TITLE__", html.escape(title))
            .replace("__FORM_JSON__", payload))
    out.write_text(page, encoding="utf-8")

    print(out.resolve())
    if not args.no_open and sys.platform == "darwin":
        subprocess.run(["open", str(out)], check=False)


if __name__ == "__main__":
    main()
