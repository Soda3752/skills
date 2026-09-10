#!/usr/bin/env bash
# close-self.sh —— 交接的最後一步：查證接手方 → 切焦點 → 關掉自己這個 pane。
#
# 用法：
#   close-self.sh --agent <name> --tab <新 tab id> [--pane <自己的 pane id>] [--accept-idle] [--dry-run]
#
# 為什麼是腳本而不是讓 LLM 自己跑三行指令：
#   「驗證沒過就不准關自己」這條規則，交給 LLM 判斷就有機會被跳過，
#   而這一步的失敗是不可逆的（脈絡兩邊都丟）。所以把 gate 寫成程式：
#   狀態不對就 exit 非 0 且**完全不會**執行 pane close。
#
# exit code：
#   0  已切焦點並關掉自己（本行之後這個 pane 就不存在了）
#   2  參數不對
#   3  接手方狀態不合格 —— 沒有關任何東西
#   4  接手方畫面是空的／撈不到 —— 沒有關任何東西
#   5  tab focus 失敗 —— 沒有關任何東西
set -uo pipefail

AGENT="" ; TAB="" ; PANE="${HERDR_PANE_ID:-}" ; ACCEPT_IDLE=0 ; DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="${2:-}"; shift 2 ;;
    --tab) TAB="${2:-}"; shift 2 ;;
    --pane) PANE="${2:-}"; shift 2 ;;
    --accept-idle) ACCEPT_IDLE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "close-self: 未知參數 $1" >&2; exit 2 ;;
  esac
done

[ -n "$AGENT" ] || { echo "close-self: 缺 --agent" >&2; exit 2; }
[ -n "$TAB" ]   || { echo "close-self: 缺 --tab" >&2; exit 2; }
[ -n "$PANE" ]  || { echo "close-self: 缺 --pane，且環境沒有 HERDR_PANE_ID" >&2; exit 2; }

# ---- gate 1：接手方的 agent_status ----
STATUS="$(herdr agent get "$AGENT" 2>/dev/null \
  | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print("unparsable"); raise SystemExit
# 實測回傳是 {"result":{"agent":{"agent_status":...}}}，容錯多走幾層
node=d.get("result",d)
if isinstance(node,dict) and isinstance(node.get("agent"),dict):
    node=node["agent"]
for k in ("agent_status","status"):
    if isinstance(node,dict) and node.get(k):
        print(node[k]); raise SystemExit
print("unknown")' 2>/dev/null)"
STATUS="${STATUS:-unparsable}"
echo "close-self: agent=$AGENT status=$STATUS"

case "$STATUS" in
  # working：接手了正在做事。done：接手了、回報完就停下來等使用者（第 4 步叫它「回報完就停」時的正常終態）。
  # 兩者都算接手成功；真正要擋的是 blocked / idle / unknown / unparsable。
  working|done) : ;;
  idle)
    if [ "$ACCEPT_IDLE" -ne 1 ]; then
      echo "close-self: idle 可疑（prompt 可能沒送到）。先讀畫面確認它真的在講這份工作，" >&2
      echo "            確認過了才加 --accept-idle 重跑。沒有關掉任何 pane。" >&2
      exit 3
    fi
    echo "close-self: idle 但呼叫方已人工確認過畫面（--accept-idle）"
    ;;
  *)
    echo "close-self: 狀態 $STATUS 不合格，交接未完成。沒有關掉任何 pane。" >&2
    echo "            自己這格保留著，照 skill「驗證沒過怎麼回報」那段回報使用者。" >&2
    exit 3
    ;;
esac

# ---- gate 2：接手方畫面上真的有東西 ----
SCREEN="$(herdr agent read "$AGENT" --source recent-unwrapped --lines 40 2>/dev/null | tr -d '[:space:]')"
if [ "${#SCREEN}" -lt 40 ]; then
  echo "close-self: 接手方畫面幾乎是空的（${#SCREEN} 個非空白字元），prompt 可能沒生效。" >&2
  echo "            沒有關掉任何 pane。" >&2
  exit 4
fi
echo "close-self: 接手方畫面有 ${#SCREEN} 個非空白字元，判定 prompt 已生效"

# ---- 先切焦點，再關自己（順序不能反）----
if [ "$DRY_RUN" -eq 1 ]; then
  echo "close-self: [dry-run] 會執行 herdr tab focus $TAB && herdr pane close $PANE"
  exit 0
fi

if ! herdr tab focus "$TAB" >/dev/null 2>&1; then
  echo "close-self: tab focus $TAB 失敗，使用者的視線還在舊 pane，不關自己。" >&2
  exit 5
fi
echo "close-self: 焦點已切到 $TAB，接著關閉 $PANE"

exec herdr pane close "$PANE"
