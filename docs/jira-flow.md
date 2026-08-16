[← 回目錄](README.md)

# jira-flow

票在 Jira 時的初始化與日常工作流。

## 作用

這個 plugin 有四個 skill：一支一次性的初始化，三支涵蓋票券完整生命週期的日常工具。

```
新專案 ──jira-workflow-init──▶ 接上 Jira（站台、project key、transition id）

需求 ──grill-to-jira──▶ 票  ──check-jira-status──▶ 知道下一張做哪個
                            └──jira-goal-loop────▶ 自動做完
```

行為與 `linear-flow` 的日常三支刻意保持一致。你在兩個系統之間切換時，不需要重新學習流程。

`jira-flow` 沒有平行開發 skill。平行開發只在 `linear-flow` 提供。

## 安裝

```
/plugin marketplace add Soda3752/skills
/plugin install jira-flow@soda-skills
```

## 前置條件

使用前先完成兩件事：

1. Atlassian MCP 已授權。
2. 在專案根目錄執行過 `/jira-workflow-init`（見下方[jira-workflow-init](#jira-workflow-init)）。

第 2 件產出 `.claude/jira-workflow.json`。**沒有這個檔案，日常三支都會直接停止。**

它們不會猜站台、project key、transition id。猜錯的後果是票被建到錯的專案，或被推進錯的狀態欄。兩者都要手動善後，而 **Jira MCP 沒有刪票工具**。

## 含哪些 skill

| Skill | 作用 |
| --- | --- |
| `jira-workflow-init` | 把專案接上 Jira。一次性。 |
| `grill-to-jira` | 訪談需求 → 規格書 → 建票 |
| `check-jira-status` | 盤點看板，算出下一張做哪個 |
| `jira-goal-loop` | 無人監督地把看板做完 |

---

## jira-workflow-init

### 作用

它把當前專案接上 Jira。這是**一次性設定工具**，一個專案執行一次就好。行為與 `linear-flow` 的 `linear-workflow-init` 對齊：先診斷缺什麼、列缺口、問你要不要補，你同意後才一次補齊。任何東西被寫入之前，你先看到完整清單。

### 使用方式

```
/jira-workflow-init          # 診斷 + 安裝
/jira-workflow-init doctor   # 只診斷，不寫檔
```

### 它會檢查九項

比 Linear 版多一項：**transition id 的實查校正**。

Jira 的狀態轉換有圖。你不能任意從一個狀態跳到另一個狀態。每一條轉換有自己的 id，而且**每個 project 的 id 不同**。所以 skill 必須實際抓一張票，查它有哪些 transition，再反推 id。

### 產出

```
<專案根>/
├── CLAUDE.local.md              # 多一行 @.claude/jira-workflow.md
└── .claude/
    ├── jira-workflow.md         # 工作流規則
    └── jira-workflow.json       # 站台、project key、transition id
```

### 安裝後第一件事

預設值放在：

```
plugins/jira-flow/skills/jira-workflow-init/config/defaults.env
```

裡面的站台網址與 project key 是**佔位符**。第一次使用前，至少改掉 `JIRA_SITE` 與 `DEFAULT_PROJECT_KEY`。transition id 不用改，skill 會實查校正。

文件中的 `PROJ` 與 `ACME` 是兩個真實專案的匿名代號。

### 零票專案的處理

Jira 需要一張實體票才能查 transition id。專案還沒有任何票時，skill 會請你建一張探測票。**票號會被永久消耗。** 這是 Jira 的限制。

Linear 沒有這個問題。`list_issue_statuses` 不需要任何票就能查。

---

## grill-to-jira

### 作用

它把一個模糊的需求變成一批 Jira 卡片。

過程有五個階段：

1. 讀設定。
2. 快速探索 codebase。
3. **多輪訪談**。它一題一題問你，逼出決策。
4. 寫規格書。
5. 拆成垂直切片的卡片，並實際建票。

建票時會一併設定 Blocked by 依賴、Epic 歸屬、Block 狀態。

### 使用方式

直接說出需求。例如：

```
幫我拆成 jira 卡片
這個需求開票
訪談我然後拆票
規格談完幫我開票
```

只要草稿、先不建票時，加上 `draft`：

```
/grill-to-jira draft
```

`draft` 模式走到拆票草稿為止。**一張票都不建。**

### 什麼是垂直切片

一個垂直切片是一張**自己就能驗收**的卡片。它從 UI 到資料庫都包含。

反例是水平切片：「先建所有資料表」「再寫所有 API」「最後做 UI」。水平切片的每一張都無法單獨驗收。

### 產出的卡片長什麼樣

每張卡片有固定四段：

```
## 要做什麼
## 完成的樣子
## Blocked by
## 來源
```

「來源」指向規格書。你日後回頭看時，知道這張票的決策從哪裡來。

---

## check-jira-status

### 作用

它盤點看板，然後回答三個問題：

1. 哪些票**真的可動**（所有 blocker 都已完成）？
2. 哪些票卡住？卡在誰？
3. 下一張該做哪個？

它同時回報**狀態不一致**。例如：

- 分支已經動工，但票沒推進行中。
- 票卡在進行中被遺忘。
- blocker 全部清完，但票還停在 Block。
- 票在審核中，但實作 commit 早就進去了。

### 使用方式

問就好。例如：

```
盤點 jira
接下來做哪張
現在該做什麼
哪些票可以動
jira 狀態對不對
```

專案有 `.claude/jira-workflow.json` 時，你只說「下一步做什麼」也會觸發。

### 這是唯讀的

它**絕不改任何票**。它只讀取、計算、回報。看到不一致時，它列在「待修正」區塊給你看，但不動手。

### 輸出

結果直接顯示在對話裡。**它不存報告檔。** 盤點是高頻動作。每次都寫報告會很快變成垃圾。

輸出結構：

```
## Jira 盤點 — <projectKey> (<日期>)

### 建議下一張：<KEY> <標題>
### 可動（blocker 全清）
### 卡住
### 待修正（本 skill 不動票）
```

建議一定附三條理由：可動性、優先序、解鎖效益。

### 排序邏輯

它依這個順序建議：

1. **收尾優先。** 已經在審核中的票先做完。
2. **解鎖效益。** 解開愈多下游的票愈優先。
3. **優先序。** 最後才看 Jira 的優先序欄位。

### 回傳爆量的地雷

Jira 的 `searchJiraIssuesUsingJql` 預設會回傳大量欄位。不限制欄位時，回傳內容會塞爆 context。

這個 skill 已經處理了。你自己手動查詢時要注意。

---

## jira-goal-loop

### 作用

它在**無人監督**的情況下，一輪做一張票，直到看板收斂。

每一輪的流程固定：

```
推進行中 → 定規格 → 實作 → 驗證 → commit
→ 寫實作紀錄註解 → 推終態 → 解鎖下游 → 收尾 Epic → 寫 log
```

### 使用方式

用 `/loop` 啟動：

```
/loop /jira-goal-loop
```

它**不會自動啟動**。你必須明確啟動它。

### 安全前提

先讀完這一節再啟動。

**它會自己執行 shell 指令。** 每輪要跑的驗證指令來自 `.claude/jira-workflow.json` 的 `goalLoop.verifyCommands`。那個欄位等於「授權它在你的機器上執行什麼」。

所以：**第一次在某個專案啟動前，用人眼看過那幾條指令。** 不要因為 clone 下來的 repo 附了一份設定就直接啟動。

它遵守的紅線：

- 不 push。
- 不改自己的規則檔。
- 不 commit 憑證。
- 貼進票券前先遮蔽敏感值。最後一條特別重要：**Jira 註解是對外發佈的**。保留錯誤訊息原文之前，先遮掉 token 與內部主機名。

### 四種終態的分辨方式

這個 loop 最關鍵的判斷是：一張票做不下去時，該推到哪一欄。

| 終態 | 意思 | 誰來解 |
| --- | --- | --- |
| **完成** | 做完了，驗證全綠。 | 無 |
| **PENDING** | 需要你本人動手或裁示。 | 你 |
| **API Require** | 缺後端。 | 後端 |
| **Block** | 純粹被另一張未完成票擋住。 | 另一張票 |

分辨 Block 與 PENDING 的判準：**Block 只用在「等票」，不用在「等人」。要人的一律進 PENDING。**

分辨 API Require 的判準一句話：**要解這個阻塞，得有人動後端嗎？**

### PENDING 欄怎麼來

`PENDING` 是**你的收件匣**。開跑前必須確定它有著落。

Jira 需要你在 workflow scheme 裡建這一欄，並取得它的 transition id。`jira-workflow-init` 會實查校正。

**沒有 PENDING 的去處就不要啟動。** 需要你裁示的票會被塞回 Block 或留在原地。loop 下一輪重新挑到它，重新撞同一面牆，直到空轉保護才停止。一整晚就這樣浪費掉。

### 什麼時候它會停手不做

有一類改動它**一定不做**：影響使用者看到什麼的改動，以及不可逆的改動。

例如：

- 要不要下架某個功能。
- 遷移資料。
- 改 API 契約。
- 動到別張票的範圍。

遇到這些，它推 PENDING，在註解列出具體問題清單，然後換下一張票。

### 設定

規則本體零硬編碼。專案特定值全部讀自 `.claude/jira-workflow.json` 的 `goalLoop` 區塊。

主要欄位：

| 欄位 | 意思 |
| --- | --- |
| `branch` | 所有 commit 疊在這個分支 |
| `verifyCommands` | 每輪必跑。全綠才算通過。 |
| `terminalStates` | 哪些狀態算「這張票結束了」 |
| `strikeLimit` | 同一張票驗證失敗最多修幾次 |
| `maxRoundsPerTicket` | 同一張票最多佔用幾輪 |
| `maxRoundsPerSession` | 同一段對話最多跑幾輪 |
| `maxIdleRounds` | 連續幾輪零產出就停止 |
| `roundBudgetMinutes` | 單輪軟上限 |
| `protectedPaths` | 這些路徑它不准改 |

### 它寫哪些檔案

| 檔案 | 內容 | 寫法 |
| --- | --- | --- |
| `goal-loop-log.md` | 歷史。含失敗過的做法。 | 只 append，永不刪改 |
| `goal-loop-index.md` | 索引。三振票、PENDING 票、失敗做法各一行。 | 每輪覆寫 |
| `HANDOFF.md` | 快照。你這一刻進來，一頁看懂現況。 | 每輪覆寫 |

log 絕對不能覆寫。它唯一的價值是：第 8 輪的 Claude 不要重犯第 3 輪的錯。

index 存在的理由是成本。log 跑到二三十輪會長到每輪重讀就吃掉可觀的 context。而每輪真正需要的只有兩件事：哪些票別再碰，哪些做法別再試。

### 三振出局

同一張票驗證失敗達到 `strikeLimit` 次時，它停止修這張票。

處理方式：存下 patch、回滾改動、推 PENDING、在 index 標記三振。下一輪不再挑這張票。

### 單輪軟上限

實作時間超過 `roundBudgetMinutes` 而且還看不到綠燈時，它不硬撐。它走回滾與 PENDING 流程，理由寫「單輪預算耗盡」。

**做到一半的大改動比沒改更糟。**

### session 輪次上限

`/loop` 的每一輪都在同一段對話裡被喚醒。context 一路疊上去，跑到十幾輪後品質會下降。

所以有 `maxRoundsPerSession`。跑滿時它停機，而且**刻意不產出總結報告**（總結報告只在收斂時產生，提前產生會讓你誤以為做完了）。它改在 `HANDOFF.md` 頂端標記換手。你 `/clear` 後重下同一份 `/loop` 指令即可續跑。

只有「本 session 已跑」會歸零。已跑輪數、連續空轉、三振紀錄都是跨 session 累計的。

---

## Jira 與 Linear 的差別

你同時用兩個系統時，這三點差最多。

**1. Jira 有 transition，Linear 沒有。**
Jira 的狀態轉換有圖。你不能任意跳。每一條轉換有 id，而且每個 project 的 id 不同。所以 `jira-workflow-init` 必須實查校正。

**2. Jira 需要一張實體票才能查 transition id。**
零票專案要先建一張探測票。票號會被永久消耗。

**3. 容器名稱不同。**
Jira 叫 Epic。Linear 叫 Project。兩者的作用相同。

## 不要在同一個專案接兩套工作流

同一個專案不要同時 import `jira-workflow.md` 與 `linear-workflow.md`。

兩份規則都定義了「更新票券」的預設意思。兩份同時存在時，它們會直接衝突。

`linear-workflow-init` 偵測到這種情形會停下來問你。
