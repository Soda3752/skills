#!/usr/bin/env bash
# 把 repo 內刻意與本機分岔的部分改回匿名版。
#
# 為什麼需要這支：本機的 jira-workflow-init 用的是真實站台與 project key
# （那是它日常要能跑的前提），但 repo 是公開的。sync-from-local.sh 用
# rsync --delete 單向覆蓋，所以每次同步後都會把真值帶回來——這支就在
# 同步的最後一步自動抹掉，避免哪次忘了手動改就 push 出去。
#
# 真實值放在 scripts/.anonymize-map.json，該檔不進版控。理由很直接：
# 對照表就是解碼表，把它 commit 上公開 repo，等於附一份還原說明書。
#
# 這支是冪等的，重複跑沒有副作用。sync-from-local.sh 會自動呼叫，
# 也可以單獨執行。

set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MAP="${REPO}/scripts/.anonymize-map.json"
if [[ ! -f "$MAP" ]]; then
  echo "❌ 找不到 ${MAP}"
  echo "   複製 scripts/.anonymize-map.example.json 成 .anonymize-map.json 並填入真實值。"
  echo "   在沒有對照表的情況下繼續，等於把未匿名的內容留在工作區。"
  exit 1
fi

REPO="$REPO" MAP="$MAP" python3 <<'PY'
import json
import os
import re
from pathlib import Path

repo = Path(os.environ["REPO"])
jira = repo / "plugins/workflow-init/skills/jira-workflow-init"
if not jira.is_dir():
    raise SystemExit(0)

cfg = json.loads(Path(os.environ["MAP"]).read_text(encoding="utf-8"))
subs = [(re.compile(pat), rep) for pat, rep in cfg["substitutions"]]

# 走訪整個目錄，不是寫死幾個檔名。
# rsync 會把上游新增的檔案一起搬進來，寫死清單的話新檔會靜默漏掉。
TEXT_SUFFIXES = {".md", ".env", ".json", ".txt", ".yaml", ".yml", ".toml"}
touched = 0
for path in sorted(jira.rglob("*")):
    if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
        continue
    text = original = path.read_text(encoding="utf-8")
    for pat, rep in subs:
        text = pat.sub(rep, text)
    if text != original:
        path.write_text(text, encoding="utf-8")
        touched += 1

# 匿名化之後語意會跑掉的句子，逐句改寫
env_path = jira / "config/defaults.env"
env = env_path.read_text(encoding="utf-8")
env = env.replace(
    "# 注意：下面這六個值是 PROJ 這個 project 的，不是站台通用值。",
    "# 注意：下面這六個值是某一個實際 project（以下稱 PROJ）的，不是站台通用值。",
)
env = env.replace(
    "# 換 project 不只是「可能不同」——實測 ACME 的",
    "# 換 project 不只是「可能不同」——實測另一個 project（ACME）的",
)
env = env.replace("（例如 PROJ 的 PENDING）", "（實例：PROJ 有一欄 PENDING）")

# 檔頭警語：不存在才插入
if "這份檔案裡的值都是範例" not in env:
    anchor = "# 要改已設定專案，直接編輯該專案的 .claude/jira-workflow.json。\n"
    notice = (
        "#\n"
        "# ⚠️ 這份檔案裡的值都是範例。第一次使用請至少改掉 JIRA_SITE 與\n"
        "#    DEFAULT_PROJECT_KEY；transition id 不改也沒關係，init 會實查校正。\n"
    )
    if anchor not in env:
        raise SystemExit("anonymize: defaults.env 找不到警語錨點，請檢查上游檔案是否改過")
    env = env.replace(anchor, anchor + notice, 1)

env_path.write_text(env, encoding="utf-8")

# SKILL.md 代號說明：不存在才插入
skill_path = jira / "SKILL.md"
skill = skill_path.read_text(encoding="utf-8")
if "是兩個真實專案的匿名代號" not in skill:
    anchor = "這是**機械式 SOP**"
    notice = (
        "> 文中的 `PROJ` 與 `ACME` 是兩個真實專案的匿名代號。那些實例保留下來是因為"
        "它們解釋了「為什麼要有這條規則」——規則本身看起來都很像過度謹慎，"
        "直到你知道它是踩過哪個坑才長出來的。\n\n"
    )
    if anchor not in skill:
        raise SystemExit("anonymize: SKILL.md 找不到代號說明錨點，請檢查上游檔案是否改過")
    skill = skill.replace(anchor, notice + anchor, 1)
    skill_path.write_text(skill, encoding="utf-8")

print(f"✅ jira-workflow-init 已匿名化（改寫 {touched} 個檔案）")
PY
