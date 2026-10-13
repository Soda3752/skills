---
name: ask-html
description: 當 Claude 有大量問題要問使用者（超過 4 題，AskUserQuestion 一次塞不下）時，改把所有問題產成一個本地 HTML 表單並用瀏覽器打開：每題列出 A/B/C 選項卡片，每個選項有一句說明，有不明顯的後果或代價時才另外補充「選了之後／代價」（預設收起，點右上角展開），標出推薦選項，支援複選題、作答進度條、暫存作答，每題底下都有輸入框，頁面底部一顆「複製所有答案」按鈕，使用者複製後貼回 Claude Code 即可。Use this whenever you need to ask the user more than 4 questions at once — spec confirmation, requirement interviews, design decisions, migration choices — instead of splitting them into several AskUserQuestion rounds. Also use when the user explicitly asks for a form. Triggers: "問題太多用表單", "開個網頁讓我填", "用 HTML 問我", "做一份問卷給我選", "把問題整理成表單", "一次問完", "question form", "make me a form to answer these", "ask me with an html page", "too many questions, put them in a page"。4 題以內照舊用 AskUserQuestion。
---

# 大量問題 → 本地 HTML 表單

## 什麼時候用

| 狀況 | 做法 |
|---|---|
| 要問的問題 ≤ 4 題 | 照舊用 AskUserQuestion，**不要**開這支 |
| 要問的問題 > 4 題 | 用這支，一次全部列出 |
| 使用者明講「用表單／網頁問我」 | 不論題數都用這支 |

判斷題數時把「本來要分兩三輪 AskUserQuestion 問的」都算進去。寧可一次問完，不要讓使用者來回切換五輪。

## 流程

### 1. 整理問題

先把所有要問的事列出來，去掉可以從程式碼、文件、慣例自己查到的。剩下的才是真正要問的。

每題決定：

- **單選或複選**：選項互斥 → 單選；可以同時成立 → `multi: true`。
- **有沒有選項**：命名、自由描述這類開放題，`options` 給空陣列，變成純輸入題。
- **推薦哪一個**：每題標一個 `recommended: true`。使用者不確定時會直接選它。
- **每個選項的 desc**：一句話讓人看懂這個選項，必寫。
- **effect 與 cost**：選了之後有不明顯的後果、或有真實代價時才寫，沒有就省略，寫法見 `references/schema.md`。

題目排序：會影響後面題目的決策放前面，細節放後面。

### 2. 寫 JSON

寫到 scratchpad（沒有 scratchpad 就用 `/tmp`），格式見 `references/schema.md`：

```bash
cat > "<scratchpad>/questions.json" <<'EOF'
{ "title": "...", "intro": "...", "questions": [ ... ] }
EOF
```

### 3. 產生並打開表單

```bash
python3 "<這支 skill 的 base directory>/scripts/build_form.py" "<scratchpad>/questions.json"
```

`<這支 skill 的 base directory>` 是載入這支 skill 時系統告訴你的路徑。**不要用 `$CLAUDE_PLUGIN_ROOT`**，它在主 session 是空的。找不到時：

```bash
SCRIPT=$(find ~/.claude/plugins -path '*/ask-html/scripts/build_form.py' | sort | tail -1)
python3 "${SCRIPT}" "<scratchpad>/questions.json"
```

腳本會：

1. 檢查 JSON（缺 `question`／`label` 直接失敗；單選題標了多個推薦印警告）。
2. 存到 `./.claude/questions/YYYY_MM_DD/HHMMSS_<標題>.html`。
3. 在 macOS 上自動 `open`。
4. stdout 印出 HTML 絕對路徑。

有警告就回頭修正 JSON 再跑一次。

### 4. 告訴使用者，然後停下來等

回覆只需要三件事：

```
表單已開在瀏覽器：<路徑>
共 N 題，有「推薦」標籤的是我的建議。
填完按底部「複製所有答案」，貼回這裡。
```

**這一輪到此結束**，不要繼續做任何假設性的實作。

### 5. 解析貼回來的答案

格式與解析規則見 `references/schema.md` 的「複製結果長這樣」。重點：

- `答：（未選選項，見補充）` → 使用者不接受任何選項，照補充文字做。
- `答：（未作答）` → 採用推薦選項，回覆時明講「Q3 沒答，我採用推薦的 B」。
- 補充文字跟選項衝突 → 以補充文字為準，有疑慮只針對那一題用 AskUserQuestion 追問。

解析完先用一個表格回顯「題目 → 你的決定」，再開始實作。

## 常見翻車點

- **effect／cost 寫成選項名稱的同義詞**：「選 Redis → 使用 Redis」等於沒寫。要寫選了之後具體會變怎樣、要花多少。
- **只靠 effect／cost 說清楚選項**：表單預設把「選了之後／代價」收起，使用者第一眼只看到 `label` 和 `desc`。`desc` 要能單獨讓人看懂這個選項在做什麼。
- **為了填滿欄位硬寫 effect／cost**：「比較彈性」「需要一點時間」這種廢話會稀釋真正重要的代價。沒有具體內容就省略。
- **推薦選項明明有代價卻省略 cost**：使用者會以為零成本，實作後才發現要改一堆東西。省略只限「真的沒有值得說的代價」。
- **單選題的選項其實可以並存**：使用者想兩個都要卻只能選一個，就會全寫在補充欄，解析變麻煩。可並存就設 `multi: true`。
- **題目裡塞兩個問題**：「要不要加快取？用哪種？」拆成兩題，否則答案對不上。
- **JSON 字串裡的英文雙引號沒轉義**：文字中要出現 `"` 就寫成 `\"`，或改用「」。heredoc 要用 `<<'EOF'`（有單引號），否則 `$VAR` 會被 shell 展開。
- **產完表單接著自己往下做**：使用者還沒填，任何實作都是猜的。產完就停。
- **把 HTML 存進專案根目錄**：預設路徑在 `.claude/questions/` 底下，不要用 `--out` 存到會被 commit 的位置。
- **未作答的題目默默套推薦**：一定要在回覆裡講出來，讓使用者有機會反對。

## References

- `references/schema.md`：JSON 欄位定義、完整範例、effect／cost 好壞寫法對照、複製結果格式與解析規則。寫 JSON 前必讀。
- `assets/template.html`：表單樣板（純 HTML + JS，無外部相依）。改外觀才需要動。
- `scripts/build_form.py`：把 JSON 套進樣板、驗證欄位、存檔並打開。
