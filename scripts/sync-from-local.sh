#!/usr/bin/env bash
# 把本機 ~/.claude/skills 底下的 skill 搬進這個 repo 的對應 plugin。
#
# 用法：
#   ./scripts/sync-from-local.sh            # 依 SKILL_MAP 全量同步
#   ./scripts/sync-from-local.sh pm_report  # 只同步指定 skill
#
# 收錄清單就是下面的 SKILL_MAP。要收錄新 skill 就加一行；
# 不想收錄的直接註解掉，不要留在表上——這張表是唯一的真實來源。

set -euo pipefail

SRC="${HOME}/.claude/skills"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 格式：<skill 目錄名>:<plugin 名>
SKILL_MAP=(
  # workflow-init
  "jira-workflow-init:workflow-init"
  "obsidian-init:workflow-init"
  "gitnexus-init:workflow-init"

  # report-tools
  "pm_report:report-tools"
  "whats-new:report-tools"

  # kmp-architecture
  "kmp-mvvm-architecture:kmp-architecture"

  # 刻意未收錄：
  #   gitnexus-cli / guide / exploring / debugging / impact-analysis /
  #   refactoring / pr-review  → 疑似 GitNexus 專案隨附，著作歸屬未確認
  #   rtk-reference            → 依賴本機 hook，對外無法運作
  #   init_telegram_agent      → 見下方說明，公開版與本機版是不同的東西
)

# init_telegram_agent（plugins/agent-fleet）不走這條同步線，原因有兩個：
#
#   1. 它不住在 ${HOME}/.claude/skills，而是 project scope 的
#      ~/agent/.claude/skills，這支腳本的 SRC 掃不到。
#   2. 更根本的是，公開版與本機版在「結構」上就不同，不只是值不同：
#      本機版有 hosts/<真實主機>.md，記著各機器的 agent 名冊、工具絕對路徑、
#      bot handle——那是一台停用權限確認在跑 agent 的機器的完整配置圖。
#      發布的是 hosts/EXAMPLE-host.md 骨架。
#
# anonymize.sh 處理的是「同一份檔案裡的值要換掉」，這裡的問題是「整個目錄不該存在」；
# 用 rsync --delete 同步只會把真實 hosts/ 帶回來。所以公開版由人工維護，改動時兩邊都要動。

filter="${1:-}"
count=0

for entry in "${SKILL_MAP[@]}"; do
  skill="${entry%%:*}"
  plugin="${entry##*:}"

  [[ -n "$filter" && "$filter" != "$skill" ]] && continue

  if [[ -L "${SRC}/${skill}" ]]; then
    echo "⚠️  略過 ${skill}：這是 symlink（第三方 skill），不該收進 repo"
    continue
  fi

  if [[ ! -d "${SRC}/${skill}" ]]; then
    echo "❌ 找不到 ${SRC}/${skill}"
    continue
  fi

  dest="${REPO}/plugins/${plugin}/skills/${skill}"
  mkdir -p "$dest"
  rsync -a --delete --exclude '.DS_Store' "${SRC}/${skill}/" "${dest}/"
  echo "✅ ${skill} → plugins/${plugin}/skills/"
  count=$((count + 1))
done

echo
echo "同步完成：${count} 個 skill"

# rsync 會把本機的真實站台 / project key 帶回來，這裡再抹一次。
# 抹不掉就必須大聲講：此刻工作區裡躺的是真值，順手 git add -A 就會 staged。
if ! "${REPO}/scripts/anonymize.sh"; then
  echo
  echo "🚨 匿名化失敗——工作區現在含有未匿名的真實站台與 project key。"
  echo "   在修好之前不要 git add / commit。"
  echo "   修完重跑 ./scripts/anonymize.sh 即可，不需要重新同步。"
  exit 1
fi

echo "下一步：跑 ./scripts/check-secrets.sh，再 git diff 人眼複查。"
