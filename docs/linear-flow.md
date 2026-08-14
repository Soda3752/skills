[← 回目錄](README.md)

# linear-flow

票在 Linear 時的日常工作流。

## 作用

這個 plugin 有八個 skill。它們分成兩組。

**第一組：日常三支。** 你每天用它們。

```
需求 ──grill-to-linear──▶ 票  ──check-linear-status──▶ 知道下一張做哪個
                              └──linear-goal-loop────▶ 自動做完
```

**第二組：平行開發五支。** 你要同時做多張票時用它們。

五支的骨架完全相同：

1. 每張票開一個 git worktree。
2. 每個 worktree 派一個實作者。
3. Claude 不寫業務程式碼。
4. Claude 只做四件事：盤點派工、審碼、rebase 加 fast-forward 整合、維護看板。

它們的差別只有兩點：**誰在 worktree 裡實作**，以及**你看不看得見過程**。

## 安裝

```
/plugin install linear-flow@soda-skills
```

## 前置條件

使用前先完成兩件事：

1. Linear MCP 已授權。
2. 在專案根目錄執行過 `/linear-workflow-init`。

第 2 件產出 `.claude/linear-workflow.json`。**沒有這個檔案，日常三支會直接停止。** 它們不會猜 team 與狀態 id。猜錯的後果是票被建到錯的 team，或被推進錯的狀態欄。兩者都要手動善後，而 **Linear MCP 沒有刪票工具**。

## 含哪些 skill

| Skill | 作用 | 你要不要親自呼叫 |
| --- | --- | --- |
| `grill-to-linear` | 訪談需求 → 規格書 → 建票 | 要 |
| `check-linear-status` | 盤點看板，算出下一張做哪個 | 要 |
| `linear-goal-loop` | 無人監督地把看板做完 | 要 |
| `parallel-wave` | 用 Claude subagent 平行做一批票 | 要 |
| `codex-wave` | 用 Codex 背景 job 平行做一批票 | 要 |
| `herdr-codex-wave` | 用 Codex pane 平行做一批票，過程看得見 | 要 |
| `parallel-loop` | 用 Claude pane 持續清空看板 | 要 |
| `parallel-ticket` | 單票實作 SOP | **不要**。由 `parallel-loop` 呼叫。 |

---

# 日常三支

## grill-to-linear

### 作用

它把一個模糊的需求變成一批 Linear 票。

過程有五個階段：

1. 讀設定。
2. 快速探索 codebase。
3. **多輪訪談**。它一題一題問你，逼出決策。
4. 寫規格書。
5. 拆成垂直切片的票，並實際建票。

建票時會一併設定 blockedBy 依賴、Project 歸屬、Blocked 狀態。

### 使用方式

直接說出需求。例如：

```
幫我把「使用者要能匯出報表」這個功能拆成票
```

只要草稿、先不建票時，加上 `draft`：

```
/grill-to-linear draft
```

`draft` 模式走到拆票草稿為止。**一張票都不建。** 你想先看拆法再決定要不要上 Linear 時用這個模式。

### 什麼是垂直切片

一個垂直切片是一張**自己就能驗收**的票。它從 UI 到資料庫都包含。

反例是水平切片：「先建所有資料表」「再寫所有 API」「最後做 UI」。水平切片的每一張都無法單獨驗收。

### 注意事項

`draft` 模式下設定檔可以缺。草稿不碰 Linear。

---

## check-linear-status

### 作用

它盤點看板，然後回答三個問題：

1. 哪些票**真的可動**（所有 blocker 都已完成）？
2. 哪些票卡住？卡在誰？
3. 下一張該做哪個？

它同時回報**狀態不一致**。例如：

- 分支已經動工，但票沒推進行中。
- 票卡在進行中被遺忘。
- blocker 全部清完，但票還停在 Blocked。
- 票在 In Review，但實作 commit 早就進去了。

### 使用方式

問就好。例如：

```
接下來做哪張
現在該做什麼
盤點 linear
哪些票卡住了
我做到哪了
```

專案有 `.claude/linear-workflow.json` 時，你只說「下一步做什麼」也會觸發。

### 這是唯讀的

它**絕不改任何票**。它只讀取、計算、回報。看到不一致時，它列在「待修正」區塊給你看，但不動手。

### 輸出

結果直接顯示在對話裡。**它不存報告檔。** 盤點是高頻動作。每次都寫一份報告會很快變成垃圾。你要留存時自己說。

輸出結構：

```
## Linear 盤點 — <team> (<日期>)

### 建議下一張：<KEY> <標題>
- 可動 ✅
- 優先序 <值>
- 解鎖效益 <解開哪幾張>

次選：<KEY> ／ <KEY>

### 可動（blocker 全清）
### 卡住
### 關係未查
### 待修正（本 skill 不動票）
```

建議一定附三條理由：可動性、優先序、解鎖效益。你要能不同意它的排序。只給一個票號等於要你盲信。

### 排序邏輯

它依這個順序建議：

1. **收尾優先。** 已經在 In Review 的票先做完。
2. **解鎖效益。** 解開愈多下游的票愈優先。
3. **優先序。** 最後才看 Linear 的 priority 欄位。

---

## linear-goal-loop

### 作用

它在**無人監督**的情況下，一輪做一張票，直到看板收斂。

每一輪的流程固定：

```
推 In Progress → 定規格 → 實作 → 驗證 → commit
→ 寫實作紀錄註解 → 推終態 → 解鎖下游 → 收尾 Project → 寫 log
```

### 使用方式

用 `/loop` 啟動：

```
/loop /linear-goal-loop
```

它**不會自動啟動**。你必須明確啟動它。

### 安全前提

先讀完這一節再啟動。

**它會自己執行 shell 指令。** 每輪要跑的驗證指令來自 `.claude/linear-workflow.json` 的 `goalLoop.verifyCommands`。那個欄位等於「授權它在你的機器上執行什麼」。

所以：**第一次在某個專案啟動前，用人眼看過那幾條指令。** 不要因為 clone 下來的 repo 附了一份設定就直接啟動。

它遵守的紅線：

- 不 push。
- 不改自己的規則檔。
- 不 commit 憑證。
- 貼進票券前先遮蔽敏感值。

### 設定

規則本體零硬編碼。專案特定值全部讀自 `.claude/linear-workflow.json` 的 `goalLoop` 區塊。

主要欄位：

| 欄位 | 意思 |
| --- | --- |
| `branch` | 所有 commit 疊在這個分支 |
| `verifyCommands` | 每輪必跑。全綠才算通過。 |
| `terminalStates` | 哪些狀態算「這張票結束了」 |
| `pendingState` | 需要你裁示的票放哪裡 |
| `strikeLimit` | 同一張票驗證失敗最多修幾次 |
| `maxRoundsPerTicket` | 同一張票最多佔用幾輪 |
| `maxIdleRounds` | 連續幾輪零產出就停止 |
| `roundBudgetMinutes` | 單輪軟上限 |
| `protectedPaths` | 這些路徑它不准改 |

設定檔缺 `goalLoop` 區塊時，它會問你問齊再寫入。它不猜、也不沿用其他專案的值。

### 開跑前必須確定 PENDING 欄

`PENDING` 是這個 loop 最關鍵的終態。它是**你的收件匣**。需要你裁示的票會放進去。

Linear 預設沒有這一欄。你有兩個選擇：

**選擇 1（推薦）：建一個獨立狀態欄。**
到 `Settings → Teams → <team> → Workflow` 建一欄 `PENDING`，type 選 `unstarted`。看板上一眼看得出有幾張票在等你。

**選擇 2：沿用 Blocked 欄加一個 label。**
缺點是 Blocked 欄混了兩種意思：等票，以及等人。你要靠 label 篩選才分得出來。

**兩者都沒有就不要啟動。** 沒有 PENDING 的去處時，需要你裁示的票只能塞回 Blocked 或留在原地。loop 下一輪會重新挑到它，重新撞同一面牆，直到空轉保護才停止。一整晚就這樣浪費掉。

### 它寫哪些檔案

| 檔案 | 內容 | 寫法 |
| --- | --- | --- |
| `goal-loop-log.md` | 歷史。含失敗過的做法。 | 只 append，永不刪改 |
| `goal-loop-index.md` | 索引。三振票、PENDING 票、失敗做法各一行。 | 每輪覆寫 |
| `HANDOFF.md` | 快照。你這一刻進來，一頁看懂現況。 | 每輪覆寫 |

log 絕對不能覆寫。它唯一的價值是：第 8 輪的 Claude 不要重犯第 3 輪的錯。

### session 輪次上限

`/loop` 的每一輪都在同一段對話裡被喚醒。context 一路疊上去，跑到十幾輪後品質會下降。

所以有 `maxRoundsPerSession`。跑滿時它停機，而且**刻意不產出總結報告**（總結報告只在收斂時產生，提前產生會讓你誤以為做完了）。它改在 `HANDOFF.md` 頂端標記換手。你 `/clear` 後重下同一份 `/loop` 指令即可續跑。

---

# 平行開發五支

## 先選一支

| Skill | 實作者 | 過程可見性 | 外部依賴 | 何時選它 |
| --- | --- | --- | --- | --- |
| `parallel-wave` | Claude subagent | 看不到，只看結果 | **無** | 預設選這個 |
| `codex-wave` | Codex CLI 背景 job | 看不到 | `codex` CLI | 想讓 Codex 寫實作，不需要盯過程 |
| `herdr-codex-wave` | Codex，跑在 Herdr pane | **看得見，能中途插話** | `HERDR_ENV=1` + `codex` CLI | 想在旁邊看著做 |
| `parallel-loop` | Claude，跑在 Herdr pane | 看得見 | `HERDR_ENV=1` | 要持續清空整個看板 |
| `parallel-ticket` | — | — | — | 不由你觸發 |

## 「波」與「loop」的差別

前三支是**波**：你指定一批票。做完並整合完就停止。要不要開下一波由你決定。

`parallel-loop` 是 **loop**：它自己補位下一張票，直到看板收斂。

波的好處是每一波之間有一個檢查點。你看到完整結果再決定是否繼續。而且下一波的候選票是在「上一波成果已進 base 分支」的前提下重新盤點的，解鎖關係才算得準。

---

## parallel-wave

### 作用

它用 Claude subagent 平行做一批票。**它不需要任何外部工具。** 它只用內建的 Agent 功能。

### 使用方式

說出你要平行處理的意圖。例如：

```
這輪能並行做哪些
開多個 agent 跑票
一次做幾張票
哪些票可以同時進行
```

上一波剛收完時，你說「直接開始下一輪」也會觸發。

### 流程

**第 1 步：盤點。** 這是最有價值的一步。它做兩層判斷：

- **依賴關係**（硬條件）。A 被 B 擋住時，A 和 B 不能同時做。
- **共用檔衝突**（軟條件）。兩張票會改同一個檔案時，同時做會產生合併衝突。

**第 2 步：三件前置。**

1. 確認 base 分支乾淨。
2. 跑一次基準線驗證。
3. 建 worktree，並複製被 gitignore 的本機設定檔。

**第 3 步：派工。** 一則訊息把所有 subagent 一次啟動。

**第 4 步：回收。** 逐張審碼、逐張 rebase、逐張 fast-forward 合併。這一步是**序列**的，不是平行的。

### 為什麼基準線驗證省最多時間

設定檔宣稱的驗證項目常常與現實脫節。

實測案例：某專案的設定檔寫「13 支驗證腳本全部通過」。實際在乾淨的 base 分支上有 4 支是紅的。其中 2 支的輸入檔已經從 repo 消失，另外 2 支需要 dev server 在執行中。

若照設定檔把全部驗證掛上去，**每個實作者都會撞到不是自己造成的紅燈，白白浪費一整輪去追不存在的 bug**。

所以：先在主 repo 跑一次完整驗證。記下哪些本來就紅、原因是什麼。派工指令裡只列當下實際會綠的那幾條，並明講排除了哪幾條、為什麼、不要去修。

### 設定

額外設定放在 `.claude/linear-workflow.json` 的 `parallelWave` 區塊。

**設定缺漏不是停工理由。** 能從 repo 推斷的就推斷（base 分支、建置指令）。推不出來的問你一次，並在收工時提議把設定寫進檔案，下次就不用再問。

---

## codex-wave

### 作用

它與 `parallel-wave` 幾乎相同。**唯一的差別是實作者換成 Codex CLI。**

盤點、審碼、整合的原則兩邊一致。

### 使用方式

```
讓 Codex 開發
用 Codex 做這幾張票
派給 codex
用 codex 平行開發
```

### 需要什麼

- `codex` CLI 已安裝。
- `openai-codex` plugin 已安裝。

### 三個一定要先知道的差異

**1. Codex 可能寫不了 Linear。開工前先實查。**

讀 `~/.codex/config.toml` 的 `[mcp_servers]` 區塊。

- **沒有 linear**：所有 Linear 操作由 Claude 做。實作紀錄要由 Claude 根據 Codex 的回傳結果**加上實際 diff** 重建。這是最大的失真風險：你很容易把 Codex 說的話當成已驗證的事實寫進票裡。
- **有 linear**：讓 Codex 自己讀票。這省下 Claude 的 context，而且票是唯一權威。但仍要明令它**不准改票券狀態、不准留言**。

無論哪一種，**推狀態與整合註解一律由 Claude 寫**。

**2. Codex 不知道你的專案慣例。** 它沒讀過 `CLAUDE.md`。它不知道 commit 訊息風格。它不知道哪些驗收條件在本機驗不到。它不知道有哪些既有元件可以重用。該講的全部要寫進派工指令。講漏了它就自己發明一套。

**3. 有 Herdr 時先考慮 `herdr-codex-wave`。** 那個版本的狀態偵測更可靠，也沒有背景 job 的併發疑慮。

### 為什麼看板權限不給 Codex

讓同一個 agent 同時能改程式又能改看板時，出錯後你分不清看板反映的是真實進度，還是它的樂觀回報。

---

## herdr-codex-wave

### 作用

它與 `codex-wave` 相同，但 Codex 跑在 **Herdr pane** 裡。

所以你可以：

- 看見它正在做什麼。
- attach 進去。
- 中途插話。

### 使用方式

```
用 herdr 派給 codex
codex yolo mode 跑票
開幾個 codex pane 同時做
這幾張票丟 codex 平行做
```

### 需要什麼

- 環境變數 `HERDR_ENV=1`。
- `codex` CLI 已安裝。
- Herdr 的 codex integration 已安裝。

### 開工前的環境檢查

執行這三行：

```bash
echo "$HERDR_ENV"                    # 必須是 1
codex --version
herdr integration status | grep -A1 codex
```

**integration 沒裝過就先裝：**

```bash
herdr integration install codex
```

它寫入 `~/.codex/herdr-agent-state.sh`。這讓 Herdr 認得 Codex pane 的 `working` 與 `idle` 轉換。

沒裝的症狀是：`agent_status` 永遠停在 `unknown`。你只能輪詢畫面尾端來猜它做完了沒。而 Codex 思考久一點就會被誤判成做完了。

裝了之後 `herdr agent wait` 才可靠。

### 一波開幾個

pane 是可見的。所以波次大小的上限是「**你還看得過來幾個**」，不只是機器負載。

實務上三到四個是舒適上限。

### 開工前置：四件事

1. 確認 base 分支狀態。
2. 跑一次基準線驗證當對照組。
3. 建 worktree。
4. 複製被 gitignore 的本機設定檔。

第 4 件最容易漏。

---

## parallel-loop

### 作用

它持續清空 Linear 看板。每張票開一個 workspace、一個 worktree、一個 Claude pane。

pane 自己走完 dev → codex review → test → rebase。回報後，主 Agent 序列地 fast-forward 合併進 main，再補位下一張票。

### 使用方式

```
開始並行 loop
用 herdr 跑票
並行清空看板
接回上一輪的 loop
```

啟動參數：

```
--hours N     # 跑幾小時後停止補位。預設不限。
```

到時間只停止**補位**。已經在做的票跑完才收工。硬砍會留下半成品 worktree。

### 需要什麼

- 環境變數 `HERDR_ENV=1`。
- 先執行過 `/parallel-loop-init`。

### 安全前提

它與 goal loop 一樣，會**在無人監督下寫程式並 commit**。

而且它多一層風險：**pane 裡的 Codex 是 Yolo Mode**。啟動前先用 `/parallel-loop-init` 的 doctor 確認權限白名單與 worktree 根目錄是你預期的。

設定檔是 `.claude/parallel-loop.json`。

### 主 Agent 的邊界

主 Agent 只做三件事：

1. 派發票給 pane。
2. fast-forward 合併。**這是它唯一碰 main 的時刻。**
3. 推終態。**只有它能推。**

pane 不碰 main。pane 不推終態。

### 舊版 Workflow 不要同時執行

`.claude/workflows/parallel-linear-loop.mjs` 是同一套流程的另一個實作。兩套共用同一份 `.claude/parallel-loop.json`。

**不要同時執行。** 它們會搶同一批 worktree 與 port。

---

## parallel-ticket

### 作用

它是單票實作 SOP。`parallel-loop` 把它送進每個 pane。

流程：

```
確認現場 → 讀票 → dev → 推 In Review
→ codex 對抗式 review 與修正 → 測試
→ rebase base 分支 → squash → 寫結果檔 → 停下來等合併
```

### 使用方式

**一般不由你觸發。** 它由 `parallel-loop` 主 Agent 透過 `herdr agent prompt` 呼叫。

主 Agent 的 fast-forward 失敗時，你可能會看到它被要求重新 rebase。

### 它的邊界

它做完自己的票就停下來。它**不合併**。合併是主 Agent 的工作。

---

# 通用說明

## 不要在同一個專案接兩套工作流

同一個專案不要同時 import `jira-workflow.md` 與 `linear-workflow.md`。

兩份規則都定義了「更新票券」的預設意思。兩份同時存在時，它們會直接衝突。

`linear-workflow-init` 偵測到這種情形會停下來問你。

## Linear 與 Jira 的四個根本差異

移植 Jira 心智模型過來時，這四點最容易出錯。

**1. 沒有 transition，也沒有 transition id。**
Linear 的狀態轉換沒有圖。任何狀態都能直接轉到任何狀態。所以送出的是 state id，不是 transition id。

**2. 沒有零票專案問題。**
`list_issue_statuses` 不需要任何實體票就能查。**不要為了校正狀態去建票。**

**3. 缺的狀態欄要人手去建。**
Linear MCP 沒有建立狀態欄的工具。

**4. `projectKey` 換成 `team`。**
票的歸屬單位是 Team，不是 Project。

## 四個 Linear API 地雷

| 地雷 | 症狀 |
| --- | --- |
| 阻塞關係只能靠 `get_issue` 逐張讀 | `list_issues` 不回傳關係。成本是 N+1。 |
| `labels` 是整組取代語意 | 不先讀就送，會清光既有標籤。 |
| `includeArchived` 預設 `true` | 不指定就會撈到已封存的票。 |
| 分支名裡的票號是小寫 | Linear 產生 `proj-1`，但 API 認 `PROJ-1`。忘了轉大寫的症狀是「分支對得上卻查不到票」。 |

完整地雷表在 `plugins/workflow-init/skills/linear-workflow-init/references/linear-workflow.md`。
