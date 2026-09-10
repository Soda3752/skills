#!/usr/bin/env bash
# 檢查 screen-api-wiki 產出的 Obsidian vault。
#
# 用法：validate-vault.sh <vault 路徑>
# 離開碼：0 = 全過，1 = 有問題（問題會逐條印出來）
#
# 檢查四件事，都是「用眼睛看很痛苦、用腳本查很便宜」的那種：
#   1. 斷鏈       [[某頁]] 指向不存在的 .md
#   2. 缺 anchor  [[某頁#某標題]] 的標題不存在（改標題最常造成）
#   3. 缺圖       ![[某圖.png]] 在 attachments/ 找不到
#   4. 分欄不配對 start / column-break / end 數量不一致，或 ID 重複

set -uo pipefail

VAULT="${1:-vault}"
[ -d "$VAULT" ] || { echo "❌ 找不到 vault：$VAULT"; exit 1; }
cd "$VAULT" || exit 1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0

find . -name "*.md" | sed 's|.*/||; s|\.md$||' | sort > "$TMP/notes"

echo "── 1/4 斷鏈"
# 去掉 #anchor 與 |alias（|280 這種圖片尺寸也在內），排除圖片嵌入
grep -rho '\[\[[^]|\\]*' --include='*.md' . 2>/dev/null \
  | sed 's|\[\[||; s|#.*||' | grep -v '\.png' | grep -v '^$' | sort -u > "$TMP/links"
BROKEN=$(comm -13 "$TMP/notes" "$TMP/links")
if [ -n "$BROKEN" ]; then
  FAIL=1
  echo "$BROKEN" | while read -r l; do
    echo "  ❌ [[$l]] 沒有對應頁面"
    grep -rn "\[\[$l" --include='*.md' . | head -3 | sed 's/^/       /'
  done
else
  echo "  ✅"
fi

echo "── 2/4 缺 anchor"
MISS=0
grep -rho '\[\[[^]|]*#[^]|]*' --include='*.md' . 2>/dev/null \
  | sed 's|\[\[||' | grep -v '^#' | sort -u > "$TMP/anchors"
while IFS='#' read -r note anchor; do
  [ -z "$note" ] && continue
  f=$(find . -name "$note.md" | head -1)
  if [ -z "$f" ]; then
    echo "  ❌ [[$note#$anchor]]：頁面不存在"; MISS=1; continue
  fi
  grep -q "^#\{1,6\} $anchor\$" "$f" || { echo "  ❌ [[$note#$anchor]]：$note 裡沒有這個標題"; MISS=1; }
done < "$TMP/anchors"
[ "$MISS" = 0 ] && echo "  ✅" || FAIL=1

echo "── 3/4 缺圖"
MISS=0
grep -rho '!\[\[[^]|]*' --include='*.md' . 2>/dev/null | sed 's|!\[\[||' | sort -u \
  | while read -r img; do [ -f "attachments/$img" ] || echo "  ❌ $img"; done > "$TMP/img"
if [ -s "$TMP/img" ]; then cat "$TMP/img"; FAIL=1; else echo "  ✅"; fi

echo "── 4/4 分欄區塊"
MISS=0
while IFS= read -r f; do
  s=$(grep -c '^--- start-multi-column' "$f")
  b=$(grep -c '^--- column-break ---' "$f")
  e=$(grep -c '^--- end-multi-column' "$f")
  [ "$s" = 0 ] && [ "$b" = 0 ] && [ "$e" = 0 ] && continue
  if [ "$s" != "$b" ] || [ "$s" != "$e" ]; then
    echo "  ❌ ${f}：start=$s break=$b end=$e"; MISS=1
  fi
done < <(find . -name "*.md")
DUP=$(grep -rh '^--- start-multi-column:' --include='*.md' . 2>/dev/null | sort | uniq -d)
if [ -n "$DUP" ]; then echo "  ❌ 區塊 ID 重複（後者不會渲染）："; echo "$DUP" | sed 's/^/       /'; MISS=1; fi
BADH=$(grep -rn '^#\{1,6\} .*\[\[' --include='*.md' . 2>/dev/null)
if [ -n "$BADH" ]; then
  echo "  ⚠ 標題裡有 wiki link，指向它的 anchor 會失效："
  echo "$BADH" | sed 's/^/       /'
fi
[ "$MISS" = 0 ] && echo "  ✅" || FAIL=1

echo
if [ "$FAIL" = 0 ]; then
  echo "✅ 全過（$(find . -name '*.md' | wc -l | tr -d ' ') 頁，$(ls attachments 2>/dev/null | wc -l | tr -d ' ') 張圖）"
else
  echo "❌ 有問題，見上方"
fi
exit $FAIL
