#!/usr/bin/env bash
# 公開前掃一遍：即將被 push 的檔案裡有沒有殘留內部資訊。
#
# 掃描對象是 git 追蹤／已 staged 的檔案，不是整個工作目錄。理由是這支要回答的
# 問題是「push 出去會洩漏什麼」，而不是「硬碟上有什麼」——用目錄走訪會同時
# 產生兩種錯：掃到根本不會上傳的本機檔（假警報），以及漏掉被 --exclude-dir
# 排除、但其實有進版控的檔（假綠燈，比假警報危險得多）。
#
# 專案專屬的樣式（真實站台、project key、公司網域）放在 scripts/.anonymize-map.json，
# 該檔不進版控。這支自己不含任何真實值，所以不需要把自己排除在掃描之外。
#
# 這是輔助不是保證——它只找得到列出來的樣式。

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPO="$REPO" python3 <<'PY'
import json
import os
import re
import subprocess
import sys
from pathlib import Path

repo = Path(os.environ["REPO"])

# 通用樣式：任何 repo 都該擋的東西
PATTERNS = [
    (r"sk-ant-[A-Za-z0-9_-]{20,}", "Anthropic API key"),
    (r"sk-[A-Za-z0-9]{20,}", "OpenAI 式 API key"),
    (r"ATATT[A-Za-z0-9_\-=]{20,}", "Atlassian API token"),
    (r"ghp_[A-Za-z0-9]{20,}", "GitHub token（舊式）"),
    (r"github_pat_[A-Za-z0-9_]{20,}", "GitHub PAT（新式）"),
    (r"xox[baprs]-[A-Za-z0-9-]{10,}", "Slack token"),
    (r"AKIA[0-9A-Z]{16}", "AWS access key"),
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "私鑰"),
    (r"/Users/[a-z0-9._-]+/", "本機絕對路徑"),
    # Windows 側的等價物。原本只擋 /Users/ 形式，所以 D:\Users\... 一路漏過去。
    (r"[A-Za-z]:\\\\Users\\\\[A-Za-z0-9._-]+", "本機絕對路徑（Windows）"),
    (r"[A-Za-z]:/Users/[A-Za-z0-9._-]+", "本機絕對路徑（Windows，正斜線）"),
    # Email：真實信箱不該出現在公開 repo。ALLOWLIST 已放行 example.com/org，
    # 套件命名空間（@modelcontextprotocol 之類）沒有點分網域，不會誤判。
    (r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}", "疑似真實 email"),
    # 任何看起來像 Jira 票號、但不是我們的匿名代號的字串。
    # 這條是為了擋「本機把 project key 換掉、對照表卻沒跟著更新」——
    # 那種情況下寫死代號的樣式會漏，這條還攔得住。
    # 例外清單裡除了匿名代號，還有一批「長得像票號的技術名詞」——
    # ISO-8601、GPT-5、UTF-8、SHA-256 這種。它們每次都命中、每次都要人工放行，
    # 而反覆出現的假警報會訓練出「掃出來的東西可以跳過」的習慣，
    # 那比漏掃一條樣式更危險。
    (
        r"\b(?!PROJ\b|ACME\b|API\b|CI\b|UI\b|ISO\b|GPT\b|UTF\b|SHA\b|RFC\b|HTTP\b|IPV\b)"
        r"[A-Z]{2,6}-[0-9]+\b",
        "疑似未匿名的票號",
    ),
]

# 刻意留在 repo 裡的佔位符
ALLOWLIST = re.compile(
    r"your-site\.atlassian\.net|example\.(com|org)|<PROJECT_ROOT>|"
    r"your-real-site\.atlassian\.net|your-company\.com|"
    r"\b(REALKEY|OTHERKEY)\b|"
    # 廠商公用的 no-reply 位址：Codex 產生的 commit 要掛 Co-Authored-By，
    # 這是官方指定值，不是誰的信箱。
    r"noreply@(openai|anthropic)\.com"
)

# 專案專屬樣式（不進版控）
map_path = repo / "scripts/.anonymize-map.json"
if map_path.is_file():
    cfg = json.loads(map_path.read_text(encoding="utf-8"))
    for pat in cfg.get("secret_patterns", []):
        PATTERNS.append((pat, "專案內部識別字"))
else:
    print(f"⚠️  找不到 {map_path.name}，只跑通用樣式；專案專屬的真實值不會被偵測")

# 只看會被 push 的檔案：git 追蹤的 + 已 staged 的
try:
    tracked = subprocess.run(
        ["git", "-C", str(repo), "ls-files", "-c", "-o", "--exclude-standard"],
        capture_output=True, text=True, check=True,
    ).stdout.split("\n")
except subprocess.CalledProcessError:
    print("❌ 這裡不是 git repo，無法判斷哪些檔案會被 push")
    sys.exit(1)

files = [repo / f for f in tracked if f.strip()]

hits = []
for path in files:
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue  # 二進位檔跳過
    for lineno, line in enumerate(text.split("\n"), 1):
        for pat, label in PATTERNS:
            for m in re.finditer(pat, line):
                # 逐一比對命中的字串本身，不是整行。
                # 用整行過濾的話，「真值與佔位符同一行」會讓真值跟著被丟掉。
                if ALLOWLIST.fullmatch(m.group(0)) or ALLOWLIST.search(m.group(0)):
                    continue
                rel = path.relative_to(repo)
                hits.append((str(rel), lineno, label, m.group(0), line.strip()[:120]))

if hits:
    for rel, lineno, label, matched, context in hits:
        print(f"── {label}：{matched}")
        print(f"   {rel}:{lineno}  {context}")
        print()
    print(f"❌ {len(hits)} 處要處理掉才能公開")
    sys.exit(1)

print(f"✅ 掃過 {len(files)} 個會被 push 的檔案，沒有命中已知樣式")
PY
