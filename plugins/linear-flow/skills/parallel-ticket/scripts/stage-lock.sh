#!/bin/bash
# stage-lock.sh —— 階段配額鎖。取代原 workflow 的 JS semaphore。
#
# 為什麼需要它：原本 quotas（test:2、review:3）是主腳本用 JS semaphore 強制的。
# 改成 Herdr pane 之後，5 個實作 pane 各自跑完整條流水線，沒有任何人協調它們。
# 這台機器 12 核 24GB，test 階段每票要 build + wrangler dev + chromium，
# 5 個同時跑會互搶到「單票反而變慢」（parallel-loop.json 的實測註解）。
#
# 為什麼用 mkdir 而不是 flock：這台機器沒有 flock（已實查）。
# mkdir 在 POSIX 上是原子的，而且鎖看得見 —— `ls locks/` 就知道現在誰在跑。
#
# 用法：
#   stage-lock.sh acquire <stage> <slots> <holder> [--stale-min 45] [--wait-min 90]
#   stage-lock.sh release <stage> <holder>
#   stage-lock.sh status  <stage>
#
# 例：
#   stage-lock.sh acquire test 2 PROJ-93
#   ... 跑 playwright ...
#   stage-lock.sh release test PROJ-93
#
# 離開碼：0 成功｜2 等不到（wait-min 用完）｜64 參數錯

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
set -uo pipefail

STATE_DIR="${PARALLEL_LOOP_STATE:-}"
if [ -z "$STATE_DIR" ]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  # worktree 裡的 --show-toplevel 會回 worktree 自己，鎖必須放**共用的主 repo**，
  # 否則每個 worktree 各鎖各的，配額形同虛設。--path-format=absolute 取 common dir。
  COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  if [ -n "$COMMON" ]; then
    REPO_ROOT="$(dirname "$COMMON")"
  fi
  STATE_DIR="$REPO_ROOT/.claude/parallel-loop-state"
fi
LOCK_ROOT="$STATE_DIR/locks"

CMD="${1:-}"; shift || true

now() { date +%s; }

case "$CMD" in
  status)
    STAGE="${1:?stage required}"
    ls -d "$LOCK_ROOT/$STAGE".* 2>/dev/null | while read -r d; do
      printf '%s\t%s\n' "$(basename "$d")" "$(cat "$d/holder" 2>/dev/null)"
    done
    exit 0
    ;;

  release)
    STAGE="${1:?stage required}"
    HOLDER="${2:?holder required}"
    for d in "$LOCK_ROOT/$STAGE".*; do
      [ -d "$d" ] || continue
      if grep -q "^$HOLDER\$" "$d/ticket" 2>/dev/null; then
        rm -f "$d/holder" "$d/ticket"
        rmdir "$d" 2>/dev/null
        echo "released $d"
        exit 0
      fi
    done
    # 沒找到自己的鎖不是錯 —— 可能被 stale 回收了。照實講，不要靜默。
    echo "warn: $HOLDER 沒有持有 $STAGE 的鎖（可能已被 stale 回收）" >&2
    exit 0
    ;;

  acquire) ;;
  *) echo "用法: stage-lock.sh acquire|release|status ..." >&2; exit 64 ;;
esac

STAGE="${1:?stage required}"
SLOTS="${2:?slots required}"
HOLDER="${3:?holder required}"
shift 3

STALE_MIN=45
WAIT_MIN=90
while [ $# -gt 0 ]; do
  case "$1" in
    --stale-min) STALE_MIN="$2"; shift 2 ;;
    --wait-min)  WAIT_MIN="$2";  shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

mkdir -p "$LOCK_ROOT"
DEADLINE=$(( $(now) + WAIT_MIN * 60 ))

while :; do
  i=1
  while [ "$i" -le "$SLOTS" ]; do
    D="$LOCK_ROOT/$STAGE.$i"

    # mkdir 不加 -p —— 目錄已存在時失敗，這個失敗就是我們要的原子性。
    if mkdir "$D" 2>/dev/null; then
      echo "$HOLDER" > "$D/ticket"
      printf '%s\t%s\t%s\n' "$HOLDER" "$(now)" "$(date '+%Y-%m-%d %H:%M:%S')" > "$D/holder"
      echo "acquired $D"
      exit 0
    fi

    # 搶不到 → 檢查是不是孤兒鎖。
    #
    # ⚠️ 這段是必要的，不是保險。pane 崩掉／被使用者關掉會留下鎖，
    # 之後所有 pane 永遠搶不到名額，loop 靜默卡死 —— 那會是下一個 PROJ-81 等級的死鎖。
    TS="$(cut -f2 "$D/holder" 2>/dev/null)"
    OWNER="$(cut -f1 "$D/holder" 2>/dev/null)"
    if [ -n "$TS" ] && [ "$TS" -eq "$TS" ] 2>/dev/null; then
      AGE_MIN=$(( ( $(now) - TS ) / 60 ))
      if [ "$AGE_MIN" -ge "$STALE_MIN" ]; then
        echo "reclaim: $D 由 ${OWNER:-?} 持有 ${AGE_MIN} 分鐘，超過 ${STALE_MIN} 判為孤兒，強制回收" >&2
        rm -f "$D/holder" "$D/ticket"
        rmdir "$D" 2>/dev/null
        continue   # 不遞增 i，立刻重搶同一格
      fi
    else
      # 有目錄但沒有合法的 holder 檔 —— 半建立狀態，同樣視為孤兒。
      echo "reclaim: $D 沒有合法 holder 檔，判為半建立狀態，回收" >&2
      rm -rf "$D"
      continue
    fi

    i=$(( i + 1 ))
  done

  if [ "$(now)" -ge "$DEADLINE" ]; then
    echo "等不到 $STAGE 的名額（$WAIT_MIN 分鐘）。目前持有者：" >&2
    "$0" status "$STAGE" >&2
    exit 2
  fi

  sleep 20
done
