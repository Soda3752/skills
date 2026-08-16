---
workflow-version: 1
generated-by: jira-workflow-init
---

# Jira 票券工作流

**只要是照著某張 Jira 票做的工作，票券狀態要跟著實際進度走，不必等使用者交代。** 看板要能隨時看出現在在哪張票、做到哪個階段——不要整張票悶頭做完才一次更新。

這份文件只寫「行為」。站台、專案 key、transition id 這些值一律不寫死在這裡，全部去讀 `.claude/jira-workflow.json`——因為同一套行為要能套在不同專案上，而那些值換專案就換。

## 設定檔

推任何狀態、寫任何註解之前，先讀 `.claude/jira-workflow.json`：

```json
{
  "site": "…atlassian.net",
  "projectKey": "…",
  "transitions": {
    "todo": "…", "inProgress": "…", "inReview": "…",
    "block": "…", "apiRequire": "…", "done": "…"
  },
  "verified": { "inReview": false },
  "extraStatuses": [{ "id": "…", "name": "…" }],
  "apiRequireLabel": "api-require",
  "ticketSource": "branch+jql",
  "branchPattern": "([A-Za-z]+-[0-9]+)"
}
```

- `site` 直接當 `cloudId` 參數傳給 MCP，不需轉 UUID。
- `verified` 裡標 `false` 的 transition 是 init 當時沒能實查驗證的。這種 id 有猜錯的可能，所以每次要用到它之前，先跑下面的三步流程確認。
- `extraStatuses` 是這個專案多出來、不屬於下面六個核心狀態的狀態欄。**工作流不會自動推票進去**——它們是專案自己的用法，要用得由使用者明講。列在這裡只是讓你知道看板上還有這些欄。

## 推狀態的三步流程

Jira MCP 走 `claude_ai_Atlassian`。任何狀態轉換都照這個順序，不要拿設定檔的 id 直接送：

1. 讀 `.claude/jira-workflow.json` 取 `site` / `transitions`
2. `getTransitionsForJiraIssue` 查這張票**當下**可用的轉換
3. `transitionJiraIssue`

第 2 步不是多餘的。transition id 綁在 workflow scheme 上，而且票在不同狀態下可用的轉換不同——設定檔裡那個 id 可能根本不在當前可用清單裡。實查一次就知道該送哪個，也順便抓到設定檔已經過期。**若實查結果與設定檔不符，以實查為準，並回報使用者設定檔該更新哪一欄。**

## 當前在哪張票

推狀態的前提是知道票號。票號的來源有優先序，別靠對話裡「剛剛提過」的記憶——跨 session 接手時那個記憶就沒了。

**主要來源：git 分支名。** 用 `branchPattern` 從分支名抽票號：

| 分支 | 抽出 |
| --- | --- |
| `fix/proj-8-9-api-path-and-codes` | PROJ-8、PROJ-9 |
| `feature/PROJ-49-idle-warning` | PROJ-49 |
| `main` / `develop` / 無票號分支 | 抽不到 |

**輔助交叉比對：JQL 實查。** 抽到票號後，另外查一次「`project = <projectKey>` AND `status = 進行中` AND `assignee = currentUser()`」。兩邊對不上時就回報，不要默默選一邊：

- 分支有 PROJ-8，但 PROJ-8 不在進行中 → 這張票的狀態沒跟上，可能該推 `inProgress`
- Jira 有票在進行中，但不在分支名裡 → 可能有票被遺忘在進行中，或現在做的其實是別的事

**抽不到票號時必須問使用者「這輪對到哪張票？」，不得猜、不得默默跳過推票。** 猜錯票號會把狀態推到別人的票上，比不推更糟；而默默跳過會讓看板停留在錯誤狀態，那正是這份工作流要解決的問題。

## 三個必推的時點

| 時點 | 推到 | 說明 |
| --- | --- | --- |
| **開始動工前** | `transitions.inProgress` | 規格確認完、要下第一個編輯動作之前就推，不是寫完才補。若卡在規格釐清或調查階段還沒動碼，也先推——調查本身就是這張票的工作。 |
| **程式完成、進入驗證** | `transitions.inReview` | 編譯過了、開始跑測試／實機驗證／自我 review 時推。這個階段票上發生的事最多（驗收逐條核對、發現邊界情境），狀態要看得出來。 |
| **驗收完成** | `transitions.done` | 驗收條件逐條核完、commit 完成後推。**推之前必須先加實作紀錄註解**（見下），不要只改狀態。 |

若一張票分多個 session 做，每次重新接手時先確認狀態仍正確，別讓票停在 `inProgress` 卻其實早就進驗證了。

## 被擋住的時候：`block` 還是 `apiRequire`

兩個都是「卡住」，差別在誰能解。判準是一句話：

> **要解這個阻塞，得有人動後端嗎？**

| 答案 | 推到 | 典型情形 |
| --- | --- | --- |
| **是** | `transitions.apiRequire`，並加上 `apiRequireLabel` 這個 label | API 還沒提供、契約不完整、錯誤碼未定義、回傳缺欄位 |
| **否** | `transitions.block` | 被另一張票擋住、缺實機／裝置、等設計稿、等使用者決策 |

加 label 的意義是讓所有後端缺口票能用一條 label 查詢聚合起來交給後端，而不是散在看板各處。

兩者都要在註解寫清楚**卡在哪、需要誰做什麼**——狀態欄只說明「停住了」，註解才說明「怎麼才能動」。

## 實作紀錄註解（推 `done` 前必做）

用 `addCommentToJiraIssue`，`contentFormat: "markdown"`，繁體中文。內容至少包含：

- 分支名與 commit hash
- **驗收條件逐條對照表**——每條寫清楚是通過、部分通過、還是沒做。只寫「已完成」等於沒寫，日後回頭查會完全看不出當時哪條其實沒驗。
- 與票券原始描述不同的決策，以及為什麼（例如某條驗收在實作方案下不適用、沿用既有慣例反而不符驗收）
- 票券沒列但實際遇到並處理掉的邊界情境
- 順手修掉的既有問題
- 已知限制與未驗證的部分——**別把「沒驗」寫成「通過」**。註解是給未來的人看的，寫錯比留白傷害大。

## 收票後必做：解開被這張票擋住的其他票

**每次把一張票推到 `done` 之後，主動往下游檢查一輪，不要等使用者問。**

1. 從剛完成那張票的 `issuelinks` 找出所有 `blocks`（outward）的下游票。
2. 對每一張下游票，查它**自己的**所有 `is blocked by`（inward）連結，逐一確認狀態。
3. **所有** blocker 都已完成 → 這張票解鎖了，把它從擋住的狀態推到 `transitions.todo`（除非它已經在進行中或更後面的狀態，那就別動）。
4. 還有 blocker 沒完成 → 維持原狀不動，並在回報中寫清楚它還卡在哪張票。

解鎖時在下游票加一則簡短註解，說明是被哪張票（票號 + 標題）解開的，讓看板上看得出因果。

**判斷依據一律是實際查到的 blocker 狀態，不是推測。** 一張票只被一張票擋住不代表就是剛完成的那張——每次都要實查 `issuelinks`。

除了「blocker 全清 → 解鎖」這一種情形，**不要改動其他票的狀態**。要改別的（重排優先序、關掉重複票、改 Epic 歸屬）先問使用者。

## 「更新 Jira」的預設含義

使用者只說「更新 Jira」時，預設是三件都做：

1. 推狀態到當前階段該有的位置
2. 加實作紀錄註解
3. 檢查下游解鎖
