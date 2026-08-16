---
name: codex-wave
description: "Claude 指揮、Codex 開發：把 Linear 票拆進獨立 git worktree，用 codex-companion 的背景 job 讓 Codex CLI 實作並自驗到綠燈，Claude 只負責盤點派工、審碼把關、rebase + fast-forward 整合、以及全部的 Linear 狀態與註解（狀態與整合註解一律由 Claude 寫，不交給 Codex）。Use this whenever the user wants Codex to do the actual coding while Claude orchestrates, mentions handing tickets or implementation work to Codex, wants GPT-5 doing dev work under Claude's supervision, or asks to compare Codex-as-implementer against Claude subagents. Triggers: \"讓 Codex 開發\", \"Claude 指揮 Codex\", \"用 Codex 做這幾張票\", \"codex 實作\", \"派給 codex\", \"codex 跑票\", \"用 codex 平行開發\", \"have codex implement these tickets\", \"claude orchestrates codex\", \"delegate the implementation to codex\", \"run these issues through codex\". 需要 codex CLI 與 openai-codex plugin；若使用者要的是 Claude subagent 實作，改用 parallel-wave。"
---

# Codex Wave —— Claude 指揮、Codex 開發

分工的理由很簡單：Codex 是能自己跑建置、讀錯誤、改到綠的完整 agent，適合悶頭把一張票做完；但它**看不到 Linear、不知道你的票券工作流、也不會幫你決定哪些票能同時做**。所以你（Claude）留在上面做判斷與整合，把「寫程式並驗到綠」整包丟給它。

與 `parallel-wave` 的差別只有實作者：那個用 Claude subagent，這個用 Codex。**盤點、審碼、整合的原則兩邊一致**，本檔不重複，需要時讀 `~/.claude/skills/parallel-wave/SKILL.md` 的第 1、2、4 步。本檔專注在 Codex 特有的部分。

**若環境有 `HERDR_ENV=1`，先考慮 `herdr-codex-wave`。** 那個版本把 Codex 開在可見、可 attach、可中途插話的 Herdr pane 裡，狀態靠 `herdr agent wait` 而非輪詢，也沒有本檔第 2 步那個「job 狀態以 repo 為單位」的併發疑慮（每個 pane 是獨立程序、獨立 cwd）。本檔的背景 job 版適合「只要結果、不需要看過程」的場合。

---

## 0. 三個一定要先知道的差異

這三點是本 skill 存在的理由，也是最容易出錯的地方。

**1. Codex 可能寫不了 Linear——先實查，不要假設。** 開工前讀 `~/.codex/config.toml` 的 `[mcp_servers]`。

- **沒有 linear**：所有 Linear 操作——推狀態、寫實作紀錄、解鎖下游——**全部由你做**，實作紀錄要由你從 Codex 的回傳結果加上實際 diff 重建。**這是本 skill 最大的失真風險**：你很容易把 Codex 說的話當成已驗證的事實寫進票裡。防呆規則見第 4 步。
- **有 linear**（實查過確實會有）：讓 Codex 自己 `get_issue` 讀票與 `list_comments` 讀解鎖註解，省你的 context 且票是唯一權威。但**仍要明令它不准改票券狀態、不准留言**——看板正確性是你的責任。

無論哪種，推狀態與整合註解都由你寫。

**2. Codex 不知道你的專案慣例。** 它沒讀過 `CLAUDE.md`、不知道 commit 訊息風格、不知道哪些驗收條件本機驗不到、不知道有哪些既有元件可以用。**該講的全部要寫進 prompt**，講漏了它就自己發明一套。

**3. 不要走 `codex:codex-rescue` 那條路。** 那個 subagent 的契約明確寫著它是「一次性轉發器」，禁止編排、禁止輪詢狀態、禁止取結果。本 skill 要的是編排，所以**直接從 Bash 呼叫 `codex-companion.mjs`**。指令契約見 `references/codex-runtime.md`（已實查驗證過）。

---

## 1. 盤點與派工前置

依賴關係與共用檔衝突的判斷方式**與 `parallel-wave` 完全相同**，讀那份的第 1 步。同樣要做的前置：base 分支乾淨、**先跑一次基準建置暖快取**、建 worktree、複製被 gitignore 的本機設定檔、整批推 `states.inProgress`。

Codex 版額外要做的一件事：**確認 Codex CLI 可用且已認證**。

```bash
codex --version
```

跑不起來或要求登入就停下來告訴使用者——**登入必須由使用者自己做**，你不要代為輸入任何憑證。可以建議他們在對話框輸入 `! codex login`，輸出會直接回到對話裡。

---

## 2. ⚠️ 並發關卡：第一次跑一定要先驗證兩張

`codex-companion` 的 job 狀態是**以 repository 為單位**追蹤的，而多個 worktree 共用同一個 `.git`。多張票各跑一個背景 job 時，job 之間會不會互相干擾（尤其 `--resume-last` 挑到別人的 thread、`status` 分不清誰是誰）**尚未經過實測**。

所以：

> **第一次在某個 repo 用本 skill 時，先只派兩張票**，確認以下三件事都成立，才可以放大到 N 張：
>
> 1. 兩個 job 各自拿到**不同的 job id**，`status --all` 能同時看到兩者
> 2. 兩個 worktree 的改動**沒有互相污染**——各自 `git status` 只有自己該有的檔案
> 3. `result <job-id>` 取回的是**對應那張票**的結果，不是另一張的
>
> 三項有任何一項不成立，就退回一次一張串行，並把實測結果回報給使用者、寫進記憶，之後不必再驗。

驗證通過後，把結論記下來（哪個 repo、幾張並發沒問題），後續直接放大。**不要每次都重跑這個關卡**，但也不要在沒驗過的 repo 上直接開 N 張——在最不好除錯的地方出併發問題，代價很高。

---

## 3. 派工：一票一個背景 job

每張票在自己的 worktree 裡起一個背景 job：

```bash
cd <worktree> && node "<pluginRoot>/scripts/codex-companion.mjs" task --background --write "<prompt>"
```

`--write` 是必要的（沒有它 Codex 只能讀不能改）。`--model` 與 `--effort` **預設不要給**，除非使用者明確要求——plugin 的指引是先把 prompt 契約寫緊，而不是先加推理強度。

**prompt 怎麼寫是本 skill 的核心技藝**，見 `references/task-prompt.md`。要點：Codex 吃 XML 區塊結構，把它當操作員而不是協作者，一次一個明確任務，並且**明講「完成長什麼樣」**——它不會自己推斷你要的終態。

記下每張票的 job id。接著輪詢：

```bash
node "<pluginRoot>/scripts/codex-companion.mjs" status --all
node "<pluginRoot>/scripts/codex-companion.mjs" status <job-id> --wait --timeout-ms <ms>
node "<pluginRoot>/scripts/codex-companion.mjs" result <job-id>
```

先回來的先整合，不要等全部——後面的 rebase 一下就好。

---

## 4. 回收：審碼，然後重建實作紀錄

### 審碼的標準比 Claude subagent 版更嚴

理由很實際：Claude subagent 與你共享同一套規範意識，Codex 沒有。它更可能**超出票券範圍順手重構**、**用自己習慣的 commit 訊息風格**、**把不該進版控的檔案 commit 進去**。

`parallel-wave` 第 4 步那四項檢查照做（看 diff 本身、看建置 log 結尾、確認測試真的執行、確認 gitignored 檔沒被 commit），Codex 版再加兩項：

5. **檢查 commit 是否只含預期路徑**：`git show --stat <hash>`。有些 harness 在 commit 前會做 `git add`，把未追蹤檔一併帶進去。發現多餘檔案就在 worktree 裡改掉再合併，不要帶進 base 分支。
6. **檢查有沒有範圍外改動**：Codex 的 `action_safety` 若沒寫進 prompt，它很容易「順手」改掉它覺得不對的東西。超出票券範圍的改動要退回或自行剔除。

### 重建實作紀錄：只寫你真的驗證過的

Codex 寫不了 Linear，所以這則註解由你寫。格式照 `.claude/linear-workflow.md` 的「註解怎麼寫」（正文給人看 + `<details>` 摺疊的 YAML 區）。

**這裡最容易出現失真**——把 Codex 的自述當成事實。用這條界線：

| 來源 | 怎麼寫 |
| --- | --- |
| 你在 diff / log / 測試結果檔裡**親眼看到**的 | 直接寫成事實 |
| Codex 回報但你**沒有獨立驗證**的 | 明確標「Codex 回報，未獨立驗證」 |
| 票券要求但本機**驗不到**的（實機、視覺、跨平台） | 標「未驗證」，不要因為 Codex 說完成就升級成通過 |

**寧可寫少，不要寫得像驗過。** 註解是給未來的人看的，寫錯比留白傷害大。

這條界線在 YAML 區也要守住：Codex 說跑過但你沒親眼看到結果的驗證，`result` 寫 `unverified`，`note` 寫「Codex 回報，未獨立驗證」。**不要因為它回報成功就填 `pass`**——那個欄位日後會被別的 agent 當成事實直接採用。

### 整合

`rebase` → `merge --ff-only` → **在 base 分支上重跑驗證** → 寫整合註解（含 rebase 前後兩個 hash）→ 推 `states.done` → 照 `.claude/linear-workflow.md` 檢查下游解鎖 → **移除 worktree**。細節與 `parallel-wave` 第 4 步相同。

---

## 5. Codex 卡住時

背景 job 有三種不健康的樣子，處理方式不同：

| 症狀 | 處理 |
| --- | --- |
| 逾時未完成，但 `status` 顯示仍在跑 | 先看 `status <id>` 的 phase 與 summary。真的在推進就再等；原地打轉就 `cancel <id>` 重下更緊的 prompt |
| 完成了但沒達標（測試沒過、範圍不對） | `task --resume-last` 送**只有差異的指令**，不要整段重述。這是 plugin 建議的作法，能保留同一個 thread 的脈絡 |
| 完全失敗或環境問題 | `cancel`，自己在 worktree 查清楚原因（通常是缺 gitignored 設定檔、或建置指令給錯），修好前置後重派 |

**同一張票重下兩次仍不達標就停下來問使用者**，不要無限重試。多半是票券規格本身有歧義，那是人要決定的事。

---

## 6. 收工回報

與 `parallel-wave` 相同，額外加兩項 Codex 特有的：

- **哪些結論是 Codex 自述、你沒獨立驗證的**——讓使用者知道信心邊界在哪
- **並發關卡的結果**（若這次是第一次跑）——幾張並發實測沒問題，寫進記憶供下次參考

---

## 反模式

| 別做 | 為什麼 |
| --- | --- |
| 走 `codex:codex-rescue` 做編排 | 它的契約禁止輪詢與取結果，硬用會得到殘缺行為 |
| 沒驗過並發就直接開 N 張 | job 狀態以 repo 為單位，worktree 共用 `.git`，出事時極難除錯 |
| 把 Codex 的自述直接寫進 Linear | 你沒驗證過的東西一旦寫成事實，未來會有人據此決策 |
| prompt 裡沒寫專案慣例 | Codex 沒讀過 CLAUDE.md，會自己發明 commit 風格與驗證方式 |
| 預設就加 `--effort high` | plugin 明確建議先緊 prompt 契約再談推理強度 |
| 代替使用者登入 Codex | 憑證只能由使用者自己輸入 |
| 合併前不看 `git show --stat` | Codex 的 commit 可能夾帶未追蹤檔 |

---

## 參考檔

- `references/codex-runtime.md` —— 已實查的 CLI 契約、並發關卡細節、已知未知
- `references/task-prompt.md` —— Codex task prompt 的 XML 區塊寫法與完整範例
- `~/.claude/skills/parallel-wave/SKILL.md` —— 共用的盤點、前置、整合原則
- `~/.claude/skills/herdr-codex-wave/SKILL.md` —— 同樣是 Claude 指揮 Codex，但開在可見、可 attach 的 Herdr pane 裡；有 `HERDR_ENV=1` 時優先考慮那個
