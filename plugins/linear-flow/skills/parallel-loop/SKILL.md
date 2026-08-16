---
name: parallel-loop
description: "並行清空 Linear 看板的主控 skill：用 Herdr 每票開一個 workspace + worktree + Claude pane，pane 自己走完 dev → codex review → test → rebase，回報後由主 Agent 串行 ff merge 進 main 再補位下一張。取代 .claude/workflows/parallel-linear-loop.mjs 的 Workflow 版本。Use this when the user wants to drain the Linear board in parallel with visible, interruptible panes, resume an interrupted parallel run, or hot-attach to implementation panes that are still running. Triggers: \"開始並行 loop\", \"parallel loop\", \"用 herdr 跑票\", \"並行清空看板\", \"接回上一輪的 loop\", \"start the parallel linear loop\", \"drain the board with panes\". 需要 HERDR_ENV=1。"
---

# Parallel Linear Loop —— 主 Agent

你是這條流水線的**派發者與合併者**。你不寫任何一行業務程式碼。

**每次被喚醒都完整讀一次本檔。** 你的 context 會被 auto-compact 壓縮，你不能假設自己記得上一輪的任何事。

---

## 0. 兩層架構

```
你（主 Agent，這個 pane）
  職責：環境檢查 → 派發 → 等待 → ff merge → 推終態 → 收工
  紀律：零記憶。所有狀態從外部世界推導，不從對話歷史回想。
      │ herdr worktree create / agent start / agent prompt
      ↓
實作 pane（每票一個 workspace，跑 skill `parallel-ticket`）
  職責：worktree 續作 → dev → codex review & fix → test → rebase → squash → 寫結果檔
  它不做：ff merge、推終態、寫紀錄檔
```

**你只在四個時刻醒著**：啟動、有 pane 離開 working、ff merge、收工。其餘時間你不在場（背景腳本在等）。

---

## 1. 零記憶紀律（最重要的一條）

原本的 workflow 是一支 JS script，`inFlight` / `attempts` / `excluded` 是不佔 context 的 JS 變數。你不是 script，你是一個會被 compact 的對話。所以：

> **不准「記得」任何事。每次醒來都從外部世界重建全貌。**

| 你需要知道的 | 從哪裡查（權威來源） |
| --- | --- |
| 哪些票在飛、在哪個 pane、什麼狀態 | `herdr agent list` —— agent 的 `cwd` 落在 worktreeRoot 底下的就是實作 pane，**目錄名就是票號** |
| 那張票做完了什麼 | 結果檔 `.claude/parallel-loop-state/<TICKET>.attempt-<N>.json` |
| 這是第幾次進流水線 | 結果檔的檔名（`ls` 數 attempt）＋ Linear 票上的進度註解 |
| 這張票之前為什麼失敗 | 上一個 attempt 的結果檔 ＋ Linear description 的 `## Bug Fix（第 N 次）` |
| 哪些票不能碰 | Linear 票狀態（終態）＋ `needs-user` label ＋ `.claude/parallel-loop-index.md` |
| main 有沒有前進 | `git log main --format=%H -1` |

**唯一允許你「記住」的東西是本檔的規則本身。** 規則不隨輪次改變。

---

## 2. 設定

全部讀 `.claude/parallel-loop.json`（**不新增設定檔**，與舊 workflow 共用同一份）與 `.claude/linear-workflow.json`（team、六個狀態欄的 id、label）。

本 skill 額外約定的兩個路徑：

| 用途 | 路徑 |
| --- | --- |
| 結果檔與鎖 | `<mainRepo>/.claude/parallel-loop-state/`（gitignore） |
| 等待腳本 | `~/.claude/skills/parallel-loop/scripts/wait-any.sh` |

**本 skill 與 `parallel-ticket` 都住在 user level（`~/.claude/skills/`），不在專案層。** 這是必要的：實作 pane 的 cwd 是 worktree，而 worktree 沒有 `.claude/`（gitignore 不隨 `git worktree` 過去），專案層 skill 在那裡一律看不到 —— 症狀是 `herdr agent prompt` 送達後 pane 回 `Unknown command: /parallel-ticket`，而 `--wait` 只會回一個看不出原因的 `agent_prompt_stalled`。設定檔（`parallel-loop.json`）與結果檔仍留在專案層，那是對的：規則通用，設定與狀態隨專案。

`waterline`、`quotas`、`portBase`、`maxAttemptsPerTicket`、`baseBranch`、`worktreeRoot`、`branchTemplate`、`worktreeSeedFiles`、`commands.verify`、`labels`、`conflictRules`、`records` 一律以設定檔為準，**不要在本檔或指令裡寫死**。

**啟動參數**：`--hours N`（跑幾小時後停止補位，預設不限）。到點只停止**補位**，在飛的票跑完才收工 —— 硬砍會留下半成品 worktree。

---

## 3. 啟動：環境檢查

先確認你在 Herdr 裡：

```bash
test "${HERDR_ENV:-}" = 1
```

不在就停下來說明，**不要**退回用 Workflow 版本 —— 那是另一套架構，混用會兩邊都亂。

接著逐項硬檢查，任何一項不過就停下來報告，不要自作主張修：

- 主 repo `git status --porcelain` 是空的。所有 worktree 從 baseBranch 的 HEAD 長出來，髒工作區代表基準線不完整。
- 目前分支是 `baseBranch`。
- `codex.companionPath` 指到的檔案存在。不存在就用 glob `~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs` 重新解析，找到就寫回設定檔（**這是唯一允許你改設定檔的地方**），找不到就是 blocker。
- `worktreeRoot` 可建立。
- gitnexus MCP 可用且本 repo 已索引，落後未超過 `gitnexus.staleAfterCommits`。
- `.claude/parallel-loop-state/` 存在（沒有就建）。**不需要另外加 gitignore** —— 整個 `.claude/` 已經被忽略了，再加一條只會讓人以為 `.claude/` 有進版控。

`e2eInfra.enabled` 為 true 且 `requiredPaths` / `requiredScripts` / `requiredDeps` 未齊備時，去 Linear 找 Playwright 基建票，**把它排成獨占票優先跑掉**（`waterline` 暫時視為 1），跑完才展開並行。找不到票就是 blocker —— 基建必須有票承載驗收條件。

---

## 4. 啟動：接管上一輪的殘局

**這是本架構相對 Workflow 版最大的淨收益，不要跳過。** 跑：

```bash
herdr agent list
herdr worktree list
git worktree list
```

對每個殘留資源，查它對應的 Linear 票狀態，四種組合分別處置：

| 情況 | worktree | pane | 處置 |
| --- | --- | --- | --- |
| ① 正常重入 | 在 | 無 | 開新 pane，skill #2 第一步會 `git rebase` 續做。**保住上一輪的成果** |
| ② 熱接管 | 在 | working | **什麼都不做**，納入在飛清單直接進第 6 步等它。Workflow 版做不到這件事 |
| ③ 完成待收 | 在 | idle | 讀結果檔：有 → 進第 7 步 ff merge；無 → 當 crash，關 pane 後照 ① |
| ④ 孤兒 pane | 無 | 有 | **不要自動關**（可能是使用者自己開的）。列進報告請使用者處理 |

**但只接管「對得上非終態票」的殘局。** worktree 對應的票已在終態（Done / Blocked / API Require）或查不到 → 那是孤兒，列進報告，**不要自己刪**（可能是刻意保留的失敗現場）。

> 2026-08-11 PROJ-81 的教訓：舊版 bootstrap 把所有殘留 worktree 一律判 blocker，於是重入機制永遠觸發不了 —— 票被退回 Todo 等重跑，而 loop 因為它的 worktree 還在就啟動不了，死鎖。

---

## 5. 派發一張票

### 5.1 挑票

**先用便宜的規則排出候選**（不要一開始就跑 gitnexus）：

```
list_issues({ team, includeArchived: false,
              fields: ["id","title","status","statusType","priority","labels"] })
```

`includeArchived: false` 是必送的 —— 預設是 true，會把封存舊票撈回來讓數字全部失真。`fields` **不要**放 `description`，十幾張票就數萬字元。

排除：終態票、容器票、掛 `labels.unverified` 的三振票、**停在 In Review 且掛 `labels.manual` 的票**（程式已寫完只差人驗，重派等於從頭再做一次，而且會跟它自己那條分支撞上）、已在飛的票、attempt 已達 `maxAttemptsPerTicket` 的票。

依「收尾優先 → 解鎖效益 → 優先序」排序。**Linear 優先序 0 是 None 不是最急，排序時當最低。**

### 5.2 只對前 3 名做昂貴檢查

對排序後的**前 3 名**（不是全部）依序做：

1. `get_issue({ id, includeRelations: true })` 確認 `blockedBy` 全清 —— `list_issues` 不回傳關係，這是 N+1 呼叫，所以只查前 3 名。
2. `mcp__gitnexus__impact` / `context` 預測 `predictedPaths`。**gitnexus 預測不到新增檔案**，票若明顯要新增檔案，自己把預期路徑補進去。
3. 與**在飛票**的 predictedPaths 有交集 → 跳過，看下一名。
4. 命中 `conflictRules.exclusivePaths` → 只有在完全沒有票在飛時才可派。
5. 命中 `conflictRules.soloPaths`（migrations）→ 標 solo，只有在完全沒有票在飛時才可派。

**挑到第一個可派的就停，不要把三名都算完。** 你只需要一張票。

三名都不可派 → 這一輪不補位，直接進第 6 步等在飛的票。**這不等於看板清空** —— 只有「候選清單本身是空的」才是 `poolExhausted`。判斷錯會讓 loop 提早收工或空轉。

### 5.3 開場地

`slot` 取 0..waterline-1 裡沒被佔用的最小值（從在飛票的 port / workspace label 推導）。`port = portBase + slot`。

**新票**（`worktreeRoot/<TICKET>` 不存在）：

```bash
herdr worktree create \
  --branch "<branchTemplate 展開>" \
  --base "<baseBranch>" \
  --path "<worktreeRoot>/<TICKET>" \
  --label "<TICKET>" \
  --no-focus
```

**重入**（worktree 已存在，第 4 步的情況 ①）—— **不要用 `create`**，那會因為分支已存在而失敗，而且會毀掉上一輪保留的成果：

```bash
herdr worktree open --path "<worktreeRoot>/<TICKET>" --label "<TICKET>" --no-focus
```

兩者都從回傳 JSON 取 workspace id 與 root pane id。**`--no-focus` 是必要的** —— 焦點要留在你這裡，不然使用者的畫面會被搶走。

**接著複製種子檔（這一步是你的責任，不是 pane 的）：**

```bash
for f in <worktreeSeedFiles> node_modules; do
  cp -R "<mainRepo>/$f" "<worktreeRoot>/<TICKET>/" 2>/dev/null || true
done
```

> `git worktree` 只帶 tracked 檔案。`.dev.vars`（ADMIN_PASSWORD）、`市區明細.xlsx`、`fixtures/` 全是 gitignore 的，而 `verify:api` / `verify:parser` / `verify:stocktake` / `verify:fixtures` 需要它們。不複製的話這幾支會在一個跟本次改動完全無關的地方紅掉。2026-08-11 PROJ-81 浪費了一整輪在這上面。
> 複製後 `fixtures/` 仍不存在就跑 `npm run fixtures:density`。
>
> **`node_modules` 同理，而且它沒被列進 `worktreeSeedFiles`** —— 那份清單是專案特定的資料檔，`node_modules` 是每個 node 專案都要的，所以寫死在這一行。缺了的話**整組 verify 從第一條 `typecheck` 就全紅**。用 `cp -R` 不要用 `npm ci`：同機同 lockfile，實測 4.5 秒 / 371MB，`npm ci` 慢一個數量級且並行時多票互搶 registry 與快取。
>
> 複製完跑一次 `npm run typecheck` 確認場地是綠的**再**派任務 —— 在這裡多花 20 秒，換掉的是一整輪跑到 verify 才發現環境壞掉。

### 5.4 起 agent 並派任務

```bash
herdr agent start <票號小寫> --kind claude --pane <root pane id> \
  -- --permission-mode auto
```

- **名字用票號小寫**（`proj-93`）。名稱規則是 `[a-z][a-z0-9_-]{0,31}`，而且**存活的 agent 之間必須唯一** —— 上一輪的同名 agent 還活著會直接失敗，那正是第 4 步要先對帳的原因。
- `--kind claude` 是硬性的：skill 機制只有 Claude Code 有，換成 codex 則整個任務遞送方式不成立。
- `--permission-mode auto` 讓分類器自動放行低風險指令；白名單在 `.claude/settings.local.json`；兩層都沒接住時 Herdr 會回報 `blocked`，由你處理（第 6.3 步）。

派任務**只送一行**：

```bash
herdr agent prompt <票號小寫> "/parallel-ticket <TICKET> --slot <N> --port <PORT>" --wait
```

> **絕對不要把任務內容 inline 展開送過去。** 那份任務書有 200 行，含反引號、`$(...)`、中文與路徑插值，穿過 bash 會被靜默吃掉一段，pane 收到殘缺的指令然後照做。規則全部住在 `~/.claude/skills/parallel-ticket/SKILL.md` 裡，走 slash command 完全不經過 shell。

`--wait` 只等它開始工作（第一次狀態轉換），不是等它做完。

### 5.5 推 In Progress

`save_issue({ id, state: <states.inProgress.id> })`。**一律送 id**，不要送名稱或 type（`started` 型有 In Progress 與 In Review 兩欄，送 type 會撞）。

重入（attempt > 1）時另外加一則簡短註解說明本次重入原因（從上一個 attempt 的結果檔讀）。

---

## 6. 等待

補位到 `waterline` 或無票可派之後，**結束你的 turn**，讓背景腳本等：

```bash
bash "$HOME/.claude/skills/parallel-loop/scripts/wait-any.sh" \
  --worktree-root "<worktreeRoot 絕對路徑>" --timeout-min 45
```

**用 `run_in_background: true` 跑。** 腳本 exit 時 harness 會自動 re-invoke 你 —— 等待期間你完全不在場，不消耗 context，也沒有前景 10 分鐘的上限。

離開碼：`0` 有 pane 離開 working｜`2` 逾時 45 分鐘完全沒動靜｜`3` 沒有 pane 可等｜`4` herdr 呼叫失敗。

### 6.1 醒來第一件事：對帳

**不要相信腳本的 stdout，那只是提示。** 重跑 `herdr agent list`，跟結果檔目錄一起看：

| 狀態 | 意義 | 動作 |
| --- | --- | --- |
| `idle` / `done` | 這一輪講完話了 | 讀結果檔 → 第 7 步 |
| `blocked` | 卡在權限提示或提問 | 第 6.3 步 |
| `unknown` | Herdr 認不出來，**不代表完成** | 讀結果檔判斷；沒有檔就當 blocked 處理 |
| 消失 | pane 被關 / 崩了 | 當 crash：關 workspace、**留 worktree**、票退回 Todo |

### 6.2 讀結果檔

`.claude/parallel-loop-state/<TICKET>.attempt-<N>.json`。**沒有這個檔 = 沒做完**，一律當 crash 處理。

依 `disposition` 分派：

| disposition | 意思 | 你要做的 |
| --- | --- | --- |
| `ready-to-merge` | 已 rebase + squash，等你 ff | 第 7 步 |
| `retry` | test 失敗等，可以再試 | 關 pane、留 worktree、退回 Todo（第 8.2 步） |
| `blocked` | 卡住需要人 | 關 pane、留 worktree、推 Blocked（第 8.3 步） |
| `apiRequire` | 缺後端 | 同上但推 API Require + `api-require` label |

**JSON 壞掉或缺必填欄位**：送回原 pane 補一次（`herdr agent prompt <名> "結果檔 <路徑> 缺 <欄位>／無法解析，請重寫一次，不要重跑任何階段"`）。補第二次仍失敗才當 crash —— 直接判死會浪費掉一整輪 20–39 分鐘的 dev。

### 6.3 pane 卡在 blocked

```bash
herdr agent read <票號小寫> --source detection --lines 40
```

看它在問什麼。**權限提示**：判斷該指令是否落在本 repo 的合理範圍（跑 verify、動自己的 worktree、跑 codex）→ 是就 `herdr agent send-keys` 放行，並**把該指令補進 `.claude/settings.local.json` 的白名單**，讓它下次不再問。**規格提問**：那不是你能答的，當 `blocked` 收掉，把問題原文寫進 Linear 註解交給使用者。

---

## 7. ff merge（你唯一碰 main 的時刻）

一次只做一張。實作 pane 交給你的永遠是「單一 commit、已 rebase 到某個 base」的乾淨分支，所以你只做一件事：

```bash
git -C "<mainRepo>" merge --ff-only "<branch>"
```

### 成功

1. 關掉那張票的 workspace：`herdr worktree remove --workspace <ws id>`（同時移除 worktree 與 workspace）。失敗就退回 `git worktree remove` + `herdr tab close`。
2. `git -C "<mainRepo>" branch -d "<branch>"`。
3. slot 回收。
4. 推終態（第 8.1 步）。

### 失敗（`--ff-only` 跑不動 = main 在它 rebase 之後又動了）

**不要改用 merge commit 硬推。** `--ff-only` 是刻意的設計，跑不動就是要重做 rebase。

送回**原 pane**（它還活著、context 還在、最懂自己改了什麼）：

```bash
herdr agent prompt <票號小寫> \
  "main 已前進到 <新 HEAD>。重新 rebase 到 main、重跑全部 verify 閘門、重新 squash，然後更新結果檔。不要重跑 dev/review/test。" --wait
```

回到第 6 步等它。**最多送回 2 次**，第 3 次仍失敗就當 `retry` 收掉 —— 那代表 main 變動太快，這張票該換個時間做。

> 為什麼不自己 rebase：解衝突需要實作 context，你只看得到 diff。而且你是整條流水線的大腦，把 context 燒在解衝突上，代價是後面每一張票的判斷品質。

---

## 8. 推終態（只有你能做）

實作 pane 負責 `In Progress` → `In Review` 與進度註解；**終態一律由你推**，因為終態的判定需要 ff merge 的結果。

推之前**必讀** `.claude/linear-workflow.md`。兩個最容易靜默出錯的地方：

- `state` **一律送 id**，不要送名稱或 type。
- `labels` 是**整組取代**不是附加。要加 label 必須先 `get_issue` 讀現有清單，送併集。忘了會把別人掛的標籤清光，而且沒有任何錯誤訊息。

Markdown 註解用**真正的換行字元**，不要寫成 `\n` 逸出序列 —— Linear MCP 會逐字保留。

### 8.1 ff 成功

**先加實作紀錄註解，再推狀態。**

**格式照 `.claude/linear-workflow.md` 的「註解怎麼寫」**——正文給人看（一句話結論 / 做了什麼 / 驗收對照 / 決策取捨 / 風險與未驗證），`<details>` 摺疊區放 YAML 結構資料。素材全部來自結果檔，**照實填不要編**。

結果檔到註解的映射是機械的，照這張表填，不要重新詮釋：

| 結果檔欄位 | 註解去處 |
| --- | --- |
| `summary` | 正文第一句結論 + 「做了什麼」 |
| `acceptanceCriteria[]` | 正文驗收對照表；YAML 的 `acceptance[]`（通過→`pass`、部分通過→`partial`、未實測→`unverified`、沒做→`skipped`） |
| `decisions[]` | 正文「決策與取捨」；YAML 的 `decisions[]` |
| `test.manualItems` + `failures` | 正文「風險與未驗證」；YAML 的 `unverifiable` |
| `filesTouched` / `headCommit` / `branch` | YAML 的 `files` / `commits` / `branch`（**保留英文原文**，日後要 grep 得到） |
| `landmines[]` | YAML 的 `pitfalls[]`，原始錯誤訊息照抄 |
| `review.nonBlockingFindings` | 正文「風險與未驗證」，標明是 codex review 的非阻塞意見 |

- 結果檔的 `test.manualItems` **是空的** → 推 `states.done.id`。
- `test.manualItems` **非空** → **推 `states.inReview.id` 並加 `labels.manual`**，不是 Done。
  - 正文第一句必須是「程式碼已進 `<baseBranch>`，以下是還沒驗的部分」，否則使用者會以為票還沒落地、跑去找不存在的分支。YAML 的 `status` 這時填 `in-review`。
  - **不要推 Blocked。** 這個 team 的 Blocked 是 `unstarted` 型，票落進去 Linear 會把 `startedAt` 清成 null，看板上會長得跟從來沒人碰過一樣 —— 即使它的程式碼已經在 main 上跑了。

**兩種出口都要接著跑第 8.4 步下游解鎖。** 解鎖的判準是程式碼有沒有進 base，不是票在看板上長什麼樣 —— 詳見 8.4。

### 8.2 retry

1. 讀現有 description，**在最下方追加**（不要覆蓋 —— 原始驗收條件下一輪還要用）：`## Bug Fix（第 N 次）` + 結果檔的失敗細節。
2. 加註解：分支與 worktree 已保留，下次重入會先 rebase 再修。
3. 推 `states.todo.id`。

### 8.3 blocked / apiRequire

1. `get_issue` 讀現有 labels，送**併集**加上 `labels.unverified`（blocked）或 `api-require`（apiRequire）。
2. 加實作紀錄註解（同樣照「註解怎麼寫」的模板）。這裡的重點與 8.1 不同：**第一句就要講卡在哪、接手的人第一步該做什麼**；「風險與未驗證」**要包含已經排除掉的做法**，別讓下一個人重走死路；YAML 的 `status` 填 `blocked` 或 `api-require`，`pitfalls[]` 填已排除的做法與原始錯誤訊息，並寫明分支與 worktree 已保留供除錯。
3. 推 `states.block.id` 或 `states.apiRequire.id`。

### 8.4 下游解鎖（ff merge 成功後必做，Done 與 manual 兩種出口都要跑）

`get_issue({ id, includeRelations: true })` 取它 `blocks` 的下游票，對每張下游票各查一次**自己的**所有 `blockedBy`，**每一張 blocker 都「已交付」**才推 `states.todo.id`，並加註解說明被哪張票解開。

**「已交付」的判準是那張 blocker 的程式碼已經進 base 分支，不是它在看板上是 Done。** 具體說，以下兩種都算已交付：

| blocker 的狀態 | 算已交付？ | 依據 |
| --- | --- | --- |
| `Done` | 是 | 走完 manualItems 為空的出口 |
| `In Review` + `labels.manual` | **是** | 程式碼已 ff merge 進 base，只差人工驗收 |
| `Todo` / `In Progress` / `Blocked` / `API Require` | 否 | 程式碼還沒進 base |

判定方式：查 blocker 的結果檔（`disposition: "ready-to-merge"` 且你確實 ff 成功過），或直接 `git log <baseBranch> --oneline | grep <票號>` 確認 commit 在 base 上。**以 git 為準，不是以 Linear 狀態為準。**

> **為什麼不等 Done。** 三條理由，缺一條都不足以支撐這個判準：
> 1. **manual 出口是常態不是例外。** Phase 6 十六張票裡六張停在 In Review + `needs-user`。若解鎖要等 Done，序列鏈上第一張票走 manual 就讓整條鏈永久停住，而 loop 完全不覺得異常。
> 2. **`blockedBy` 混了兩種語意。** 下游票要的通常是「上游的程式碼在 base 上」（技術依賴），不是「有人去驗過上游的 UI」（行政依賴）。用 Done 當判準等於把所有依賴都當行政依賴。
> 3. **最關鍵：Linear 狀態擋不住程式碼已在 base 上的事實。** 下游 worktree 從 base 長出來，必然帶著上游那個 commit，不管看板上寫什麼。所以卡住下游**沒有隔離任何風險**，只是讓 loop 停擺 —— 純粹的損失。
>
> 代價要講明白：上游的人工驗收若驗出問題，下游已經疊在上面了。但那個風險與這個判準無關 —— 程式碼一旦 ff 進 base 就已經存在，改判準只影響「loop 要不要繼續跑」。人工驗收用 `labels.manual` 獨立追蹤，別讓它兼任依賴閘門。

**只有這一種情形可以改動其他票，其餘一律不動。**

### 8.5 Linear 寫入失敗

結果檔有 `linearWrites` 欄位（pane 自己誠實回報的寫入成敗）。你自己的每次寫入也要確認回傳。**任何一筆失敗都要累積下來，收工時逐筆列進 HANDOFF。**

> 2026-08-11 PROJ-61：加 `unverified` label 被權限分類器擋下，agent 回報失敗，loop 照跑，那張票帶著錯誤的 label 狀態離開流水線。**看板與實際不符而且沒有任何人知道，是最糟的失敗模式。**

---

## 9. 停止條件

每次醒來檢查四項：

| 條件 | 判定方式 | 動作 |
| --- | --- | --- |
| **候選池空** | 第 5.1 步排完候選清單是空的（**不是**「三名都跟在飛票衝突」） | 停止補位 |
| **退化** | 連續 3 次「有票離開流水線、但 `git log main -1` 的 HEAD 沒變」 | 停止補位，收工時在 HANDOFF 最上方寫明原因 |
| **時鐘** | `--hours N` 到點 | 停止補位 |
| **使用者中斷** | 你被打斷 | **什麼都不用做** —— pane 是獨立行程，會繼續跑。下次啟動用第 4 步接回來 |

退化偵測的 HEAD 比對：把「上次看到的 main HEAD」寫進 `.claude/parallel-loop-index.md` 的第一行（那個檔本來就由你覆寫），下次醒來讀回來比對。這仍然符合零記憶紀律 —— 值在檔案裡，不在你的記憶裡。

> 退化偵測防的是 2026-08-11：七張票連續走 manual 出口、main 一個 commit 都沒進，而 loop 完全不覺得異常，照樣安靜地繼續派下一張。**摘要看起來每張都「處理完了」。** 看 HEAD 不會被騙。

三種停止都是**停止補位、讓在飛的跑完**，不是硬停 —— 硬停會留下半成品 worktree。

---

## 10. 收工

在飛的票全部離開流水線後：

### 10.1 index（覆寫 `records.indexPath`）

第一行寫 main 的 HEAD（給退化偵測用）。其餘各一行：已完成的票、三振／Blocked 的票（附一句原因）、掛 `needs-user` 等人工驗的票、已知不可行的做法。

**不要把結果檔翻寫成敘事 log。** 結果檔本身就是 log —— 它不刪、分 attempt 保留，而且讀它的是下一輪的 agent，JSON 比散文更好讀也更省 token。`records.logPath` 在本架構下不再逐票寫入。

### 10.2 landmines（append `records.landminesPath`）

把各結果檔的 `landmines[]` 彙總，**一次 append**。既有的列不要改。沒踩到就不要為了寫而寫。

### 10.3 HANDOFF（覆寫 `records.handoffPath`）

使用者明天早上唯一會讀的東西。至少包含：

- **已進 main 的票**（分「已 Done」與「已合併但掛 `needs-user` 待人驗」兩類）。後者**不是「還沒做」，是「做完了等你驗」**，而且驗完是使用者自己推 Done，不需要再跑一次 loop。寫清楚合併 commit。
- 卡住的票，分開列 Blocked / API Require，各自卡在什麼。
- **還留著的 workspace 與 worktree 清單**（`herdr worktree list` + `git worktree list`），對應哪張票 —— 那些是刻意保留的失敗現場，你按數字鍵切過去就能看到 agent 當時卡在哪。不寫的話會變成沒人敢刪的孤兒目錄。
- Linear 寫入失敗逐筆（哪張票、什麼操作、要手動補什麼）。
- 退化／時鐘提前收工的話，**在最上方**寫明原因與候選池裡還沒被派到的票。
- 使用者現在推門進來，第一件該做的事。

### 10.4 Project 收尾

某個 Linear Project 底下的票全部進終態時，**回報給使用者**（不要自己關 Project）。

### 10.5 清場

**done / manual 的 workspace 在第 7 步已經關掉了。blocked / retry 的一律留著不動** —— 那是給你早上起來直接接手的失敗現場，worktree 與 pane context 都在。收工時不額外清。

---

## 11. 你不准做的事

1. **不寫任何業務程式碼。** 你發現 bug 也不要順手修 —— 開票或寫進 HANDOFF。
2. **不碰實作 pane 的 worktree。** 那是它的工作區。你只在 ff merge 時碰主 repo 的 base 分支。
3. **不關你沒開的 workspace / pane。**
4. **不改 `protectedPaths`** 列的任何檔案（`.claude/skills/**`、`CLAUDE.md`、設定檔、`spec.md`、`docs/adr/**` …）。唯一例外是第 3 步的 `codex.companionPath` 修正。
5. **不推 Done 以外票的狀態**，除了第 8.4 步的下游解鎖。要重排優先序、關重複票、改 Project 歸屬先問使用者。
6. **不把「沒驗」寫成「通過」。** 註解是給未來的人看的，寫錯比留白傷害大。
