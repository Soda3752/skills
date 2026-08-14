#!/bin/bash
# wait-any.sh —— 阻塞到「任一實作 pane 離開 working」為止，然後 exit。
#
# 這支腳本是主 Agent 的喚醒機制，等價於原 workflow 的 Promise.race(inFlight)。
# 主 Agent 用 run_in_background 跑它；腳本 exit 時 harness 會自動 re-invoke 主 Agent。
# 等待期間主 Agent 完全不在場，不消耗 context，也沒有 Bash 前景 10 分鐘的上限。
#
# 用法：
#   wait-any.sh --worktree-root <絕對路徑> [--timeout-min 45] [--poll 10]
#
# 離開碼：
#   0  有 pane 離開 working（或消失）。stdout 是一行 JSON，說明是誰、什麼狀態。
#   2  逾時。完全沒有任何狀態變化 —— 代表出事了（全卡在權限提示、機器當掉、herdr server 掛了）。
#   3  沒有任何實作 pane 可等。主 Agent 不該在這種狀態下呼叫本腳本。
#   4  herdr 呼叫失敗。
#
# ⚠️ PATH：背景 bash 不繼承互動 shell 的 PATH，herdr / python3 / sleep 都會找不到，
#    而症狀是靜默失敗（腳本立刻 exit，主 Agent 被叫醒卻什麼也沒發生，變成 busy loop）。
#    所以這裡明確補齊 PATH，不要移除下面這行。
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

set -uo pipefail

WORKTREE_ROOT=""
TIMEOUT_MIN=45
POLL_SEC=10

while [ $# -gt 0 ]; do
  case "$1" in
    --worktree-root) WORKTREE_ROOT="$2"; shift 2 ;;
    --timeout-min)   TIMEOUT_MIN="$2";   shift 2 ;;
    --poll)          POLL_SEC="$2";      shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

if [ -z "$WORKTREE_ROOT" ]; then
  echo "--worktree-root is required" >&2
  exit 64
fi

# 相對路徑會在背景行程裡解析到別的地方去，先正規化成絕對路徑。
WORKTREE_ROOT="$(cd "$WORKTREE_ROOT" 2>/dev/null && pwd || echo "$WORKTREE_ROOT")"

DEADLINE=$(( $(date +%s) + TIMEOUT_MIN * 60 ))

# 實作 pane 的辨識方式：它的 cwd 落在 worktreeRoot 底下。
#
# 為什麼不用 agent 名字：名字是 `herdr agent start` 當下取的，若那一步失敗、
# 或使用者手動在 workspace 裡開了 agent，名字就對不上。而 cwd 是行程的實際狀態，
# 且 worktree 目錄名就是票號 —— 這符合零記憶紀律：從現實推導，不從記憶。
snapshot() {
  herdr agent list 2>/dev/null | python3 -c '
import json, sys, os
root = os.environ["WT_ROOT"].rstrip("/")
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(4)
for a in data.get("result", {}).get("agents", []):
    cwd = (a.get("foreground_cwd") or a.get("cwd") or "").rstrip("/")
    if cwd == root or not cwd.startswith(root + "/"):
        continue
    # worktreeRoot 底下的第一層目錄名就是票號
    rel = cwd[len(root) + 1:]
    ticket = rel.split("/")[0]
    print("%s\t%s\t%s\t%s" % (ticket, a.get("agent_status", "unknown"), a.get("pane_id", ""), a.get("workspace_id", "")))
'
}

emit() {
  # $1=ticket $2=status $3=pane $4=workspace $5=reason
  printf '{"woke":true,"ticket":"%s","status":"%s","pane_id":"%s","workspace_id":"%s","reason":"%s","at":"%s"}\n' \
    "$1" "$2" "$3" "$4" "$5" "$(date '+%Y-%m-%d %H:%M:%S')"
}

WT_ROOT="$WORKTREE_ROOT"
export WT_ROOT

# 先確認 herdr 真的答得出話。
#
# 不先驗這件事的話，herdr 掛掉／PATH 沒解析到會讓 snapshot 回傳空字串，
# 而空字串在下面被解讀成「沒有實作 pane」（exit 3）——主 Agent 會以為看板收斂了而收工。
# 把「工具壞掉」誤報成「工作做完了」是最糟的失敗模式，所以這一步不能省。
if ! herdr agent list >/dev/null 2>&1; then
  echo '{"woke":false,"error":"herdr agent list 呼叫失敗（herdr server 沒起來，或 PATH 沒解析到）"}' >&2
  exit 4
fi

BASELINE="$(snapshot)"

if [ -z "$BASELINE" ]; then
  echo '{"woke":false,"error":"worktreeRoot 底下沒有任何實作 pane"}' >&2
  exit 3
fi

# 開場就有非 working 的 pane —— 直接叫醒，不要等。
# 這種情況真的會發生：主 Agent 在 ff merge 期間，另一個 pane 剛好做完了。
while IFS=$'\t' read -r ticket status pane ws; do
  [ -z "$ticket" ] && continue
  if [ "$status" != "working" ]; then
    emit "$ticket" "$status" "$pane" "$ws" "啟動時已非 working"
    exit 0
  fi
done <<< "$BASELINE"

BASE_TICKETS="$(echo "$BASELINE" | cut -f1 | sort)"

while :; do
  sleep "$POLL_SEC"

  NOW="$(snapshot)"

  if [ -n "$NOW" ]; then
    while IFS=$'\t' read -r ticket status pane ws; do
      [ -z "$ticket" ] && continue
      if [ "$status" != "working" ]; then
        # idle / done  → 這一輪講完話了，主 Agent 去讀結果檔判斷是真做完還是撞牆
        # blocked      → 卡在權限提示或提問，主 Agent 要去看一眼（Q11 的安全網）
        # unknown      → 認不出來，**不代表完成**，同樣要主 Agent 判斷
        emit "$ticket" "$status" "$pane" "$ws" "離開 working"
        exit 0
      fi
    done <<< "$NOW"
  fi

  # pane 整個消失（使用者關掉、agent 崩了、Herdr 重啟）也是喚醒理由。
  # 不處理的話那張票的 slot 永遠不回收，loop 會慢慢餓死。
  NOW_TICKETS="$(echo "$NOW" | cut -f1 | sort)"
  GONE="$(comm -23 <(echo "$BASE_TICKETS") <(echo "$NOW_TICKETS") | head -1)"
  if [ -n "$GONE" ]; then
    emit "$GONE" "gone" "" "" "pane 已消失"
    exit 0
  fi

  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    printf '{"woke":false,"reason":"逾時 %s 分鐘完全沒有狀態變化","at":"%s"}\n' \
      "$TIMEOUT_MIN" "$(date '+%Y-%m-%d %H:%M:%S')" >&2
    exit 2
  fi
done
