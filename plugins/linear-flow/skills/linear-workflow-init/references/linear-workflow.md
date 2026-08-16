---
workflow-version: 2
generated-by: linear-workflow-init
---

# Linear 票券工作流

**只要是照著某張 Linear 票做的工作，票券狀態要跟著實際進度走，不必等使用者交代。** 看板要能隨時看出現在在哪張票、做到哪個階段——不要整張票悶頭做完才一次更新。

這份文件只寫「行為」。team、狀態 id、label 名稱這些值一律不寫死在這裡，全部去讀 `.claude/linear-workflow.json`——因為同一套行為要能套在不同專案上，而那些值換專案就換。

## 設定檔

推任何狀態、寫任何註解之前，先讀 `.claude/linear-workflow.json`：

```json
{
  "workspace": "…",
  "team": "…",
  "teamId": "…",
  "ticketPrefix": "PROJ",
  "states": {
    "todo":       { "id": "…", "name": "Todo",        "type": "unstarted" },
    "inProgress": { "id": "…", "name": "In Progress", "type": "started"   },
    "inReview":   { "id": "…", "name": "In Review",   "type": "started"   },
    "block":      { "id": "…", "name": "Blocked",     "type": "unstarted" },
    "apiRequire": { "id": "…", "name": "API Require", "type": "unstarted" },
    "done":       { "id": "…", "name": "Done",        "type": "completed" }
  },
  "extraStates": [{ "id": "…", "name": "Backlog", "type": "backlog" }],
  "containerMode": "project",
  "apiRequireLabel": "api-require",
  "ticketSource": "branch+api",
  "branchPattern": "([A-Za-z]+-[0-9]+)"
}
```

- **`states` 裡值為 `null` 的，代表這個 team 根本沒有那一欄。** 需要推到它時**停下來問使用者**，不要挑一個看起來相近的欄硬推。Linear 允許任意狀態互轉，所以推錯欄不會報錯，只會靜默把票放到錯的地方。
- `extraStates` 是這個 team 多出來、不屬於六個核心狀態的欄（`Backlog`、`Canceled`、`Duplicate` 通常都在這）。**工作流不會自動推票進去。**

## 推狀態：直接送 state id

Linear 走 `claude_ai_Linear` MCP。**沒有 transition 這個概念**——狀態轉換沒有圖，任何狀態都能直接轉到任何狀態，也不需要先查「這張票當下可用的轉換」。所以推狀態就一步：

```
save_issue({ id: "PROJ-24", state: "<states.<key>.id>" })
```

**一律送 `id`，不要送名稱、更不要送 type。** `state` 參數同時吃 id / 名稱 / type 三種形式，這個彈性是陷阱：送 `"started"` 會撞到 team 裡任何一個 `started` 型的欄（`In Progress` 與 `In Review` 都是），送名稱則會在有人把欄位改名之後靜默失敗或對到別欄。id 是唯一不會歧義的。

若送 id 得到錯誤（欄位被刪、被改），**重跑一次 `list_issue_statuses` 校正**，以實查為準，並回報使用者設定檔哪一欄該更新。

## 當前在哪張票

推狀態的前提是知道票號。票號的來源有優先序，別靠對話裡「剛剛提過」的記憶——跨 session 接手時那個記憶就沒了。

**主要來源：git 分支名。** 用 `branchPattern` 從分支名抽票號。

Linear 每張票自帶一個建議分支名（`gitBranchName`），形狀是 `<使用者>/<票號小寫>-<標題 slug>`：

| 分支 | 抽出 |
| --- | --- |
| `your-name/proj-1-get-familiar-with-linear` | PROJ-1 |
| `feature/PROJ-49-idle-warning` | PROJ-49 |
| `fix/proj-8-9-api-path` | PROJ-8、PROJ-9 |
| `main` / `develop` / 無票號分支 | 抽不到 |

**抽出來一定要轉大寫再用。** Linear 產生的分支名裡票號是小寫的（`proj-1`），而 API 認的是 `PROJ-1`。忘了轉大寫的症狀是「明明分支對得上卻查不到票」。

**輔助交叉比對：實查。** 抽到票號後，另外查一次進行中的票：

```
list_issues({ team, state: "<states.inProgress.id>", includeArchived: false,
              fields: ["id","title","status","statusType","assignee"] })
```

兩邊對不上時就回報，不要默默選一邊：

- 分支有 PROJ-8，但 PROJ-8 不在進行中 → 這張票的狀態沒跟上，可能該推 `inProgress`
- Linear 有票在進行中，但不在分支名裡 → 可能有票被遺忘在進行中，或現在做的其實是別的事

**抽不到票號時必須問使用者「這輪對到哪張票？」，不得猜、不得默默跳過推票。** 猜錯票號會把狀態推到別人的票上，比不推更糟；而默默跳過會讓看板停留在錯誤狀態，那正是這份工作流要解決的問題。

## 三個必推的時點

| 時點 | 推到 | 說明 |
| --- | --- | --- |
| **開始動工前** | `states.inProgress` | 規格確認完、要下第一個編輯動作之前就推，不是寫完才補。若卡在規格釐清或調查階段還沒動碼，也先推——調查本身就是這張票的工作。 |
| **程式完成、進入驗證** | `states.inReview` | 編譯過了、開始跑測試／實機驗證／自我 review 時推。這個階段票上發生的事最多（驗收逐條核對、發現邊界情境），狀態要看得出來。 |
| **驗收完成** | `states.done` | 驗收條件逐條核完、commit 完成後推。**推之前必須先加實作紀錄註解**（見下），不要只改狀態。 |

若一張票分多個 session 做，每次重新接手時先確認狀態仍正確，別讓票停在 `inProgress` 卻其實早就進驗證了。

## 被擋住的時候：`block` 還是 `apiRequire`

兩個都是「卡住」，差別在誰能解。判準是一句話：

> **要解這個阻塞，得有人動後端嗎？**

| 答案 | 推到 | 典型情形 |
| --- | --- | --- |
| **是** | `states.apiRequire`，並加上 `apiRequireLabel` 這個 label | API 還沒提供、契約不完整、錯誤碼未定義、回傳缺欄位 |
| **否** | `states.block` | 被另一張票擋住、缺實機／裝置、等設計稿、等使用者決策 |

加 label 的意義是讓所有後端缺口票能用一條 label 查詢聚合起來交給後端，而不是散在看板各處。

兩者都要在註解寫清楚**卡在哪、需要誰做什麼**——狀態欄只說明「停住了」，註解才說明「怎麼才能動」。

### ⚠️ 加 label 一定要先讀現有 label

`save_issue` 的 `labels` 參數是**整組取代**，不是附加。直接送 `labels: ["api-require"]` 會把這張票原本掛的所有 label 清光。

```
1. get_issue({ id })                                  ← 先讀現有 labels
2. save_issue({ id, labels: [...現有, "api-require"] }) ← 併集送出
```

這是 Linear 與 Jira 最容易踩的行為差異：Jira 的加 label 是附加語意，照原本習慣寫在 Linear 上會靜默刪掉別人掛的標籤，而且沒有任何錯誤訊息。

同理，**移除某個 label 的做法是送出「不含它的完整清單」**，沒有專門的移除參數。

## 依賴關係

Linear 的阻塞關係是 `save_issue` 的一級參數，不需要另外建連結：

| 參數 | 語意 |
| --- | --- |
| `blockedBy` | 這幾張票擋住我 |
| `blocks` | 我擋住這幾張票 |
| `removeBlockedBy` / `removeBlocks` | 解除既有關係 |

`blockedBy` 與 `blocks` 都是**附加語意**（append-only），送出不會清掉既有關係——與 `labels` 剛好相反，兩者不要記混。要拿掉關係得用對應的 `remove*` 參數。

**讀取關係只有一條路：`get_issue({ id, includeRelations: true })`，一張票一次呼叫。** `list_issues` 完全不回傳關係，`fields` 也沒有對應選項。這與 Jira 不同（JQL 一次就把所有 `issuelinks` 內嵌回來），所以任何需要跨票算可動性的動作，成本是 N+1 次呼叫，要事先把票數壓下來再查。

## 註解怎麼寫

票上的註解有兩種讀者，**寫法完全不同**：

| 讀者 | 要的東西 | 寫在哪 |
| --- | --- | --- |
| 人（你自己、PM、下週接手的同事） | 這張票到底改變了什麼、能不能信、還有什麼沒做 | 註解正文 |
| Agent（續跑的 loop、盤點 skill、下一張票的實作者） | 可直接取用的欄位：commit、檔案、驗收結果、地雷 | 摺疊區的 YAML |

**兩者不要混寫。** 混在同一段自由文裡的結果，是為了同時滿足兩邊而寫得很抽象——人看不出實際做了什麼，agent 也解析不出東西。分開寫之後，正文可以講人話，YAML 可以講精確。

### 寫給人看的部分：九條硬規則

這幾條是可以逐條檢查的，不是方向性建議。寫完自己過一遍。

1. **結論寫在第一句。** 先講這張票改變了什麼，再講怎麼做到的。不要鋪陳背景。
2. **一句一件事，句子不超過 25 字。** 超過就斷句。
3. **動詞開頭，主動語態。** 寫「改用串流讀取大檔」，不要寫「針對大檔的讀取方式進行了調整」。
4. **同一個東西全篇用同一個詞。** 決定叫「票」就整篇叫票，不要在議題、card、ticket 之間換。換詞會讓讀者以為你在講不同東西。
5. **禁用模糊修飾詞。** 這幾個一律不准出現：大致上、基本上、原則上、應該、若干、相關處理、進行優化、完善、健全、做了一些調整。要嘛給具體對象，要嘛給數字。
6. **數字要有基準與單位。** 寫「128 項測試全數通過」，不要寫「測試都過了」。
7. **提到檔案或函式時，先講它負責什麼。** 讀者不一定看過這份程式碼。寫「匯出流程的進入點 `ExportService`」，不要只丟一個類別名。
8. **驗收結果只用四個固定詞：通過／部分通過／未實測／沒做。** 不要自創「基本通過」「應該沒問題」——這種詞會讓日後查帳的人無法判斷當時到底驗了沒。
9. **「沒驗」就寫沒驗。** 不要因為程式看起來對、或因為別人回報完成，就升級成通過。註解是給未來的人看的，**寫錯比留白傷害大**。

正反例：

| 不要這樣寫 | 改成這樣 |
| --- | --- |
| 完成了相關處理，功能已可正常運作 | 匯出功能現在可處理 500MB 以上的檔案，不再中途失敗 |
| 針對效能問題進行了優化 | 匯出 10 萬筆資料的時間從 42 秒降到 6 秒 |
| 驗收條件皆已滿足 | AC1 通過、AC2 部分通過（只驗了 iOS）、AC3 未實測（需真機藍牙） |
| 修改了若干檔案以支援新流程 | 改了 3 個檔案：進入點加分頁參數、資料層改串流、測試補 2 個案例 |

### 實作紀錄註解（推 `done` 前必做）

用 `save_comment`，Markdown，語言依設定檔 `commentLanguage`。照這個形狀寫：

````markdown
## 完成：<票號> <票標題>

<一句話結論：誰現在可以做到什麼。>

**做了什麼**
- <動詞開頭，一到四條，講改變不是講檔案>

**驗收對照**
| # | 驗收條件 | 結果 | 依據 |
| --- | --- | --- | --- |
| 1 | <條件原文> | 通過 | <實際怎麼驗的> |
| 2 | <條件原文> | 未實測 | <為什麼驗不到> |

**決策與取捨**
- <與票券原始描述不同的地方> → <為什麼這樣改>

**風險與未驗證**
- <未驗的部分，以及誰該接手驗>
- <已知限制、留下的技術債>

<details>
<summary>給 Agent 的結構資料</summary>

```yaml
ticket: PROJ-24
status: done
branch: feature/proj-24-export-stream
commits: [a1b2c3d]
files:
  - src/export/ExportService.kt
  - src/export/StreamReader.kt
acceptance:
  - id: AC1
    result: pass
    note: 500MB 檔案實測通過
  - id: AC3
    result: unverified
    note: 需真機藍牙
verification:
  - cmd: ./gradlew test
    result: pass
    tests: 128
unverifiable: [真機藍牙連線]
decisions:
  - what: 改用串流而非全載入
    why: 全載入在 500MB 就 OOM
pitfalls:
  - tried: 調大 heap size
    failed_with: "java.lang.OutOfMemoryError: Java heap space"
followups: [PROJ-51]
unblocks: [PROJ-25]
```
</details>
````

YAML 的規則：

- **受控值，不要自由發揮。** `status` 只有 `done` / `in-review` / `blocked` / `api-require`；`result` 只有 `pass` / `partial` / `unverified` / `skipped`，與正文表格的四個中文詞一一對應。
- **路徑、指令、錯誤訊息一律保留英文原文。** 這一區存在的意義就是日後 grep 得到，翻成中文就廢了。
- **`pitfalls` 的 `failed_with` 要原始錯誤訊息，不要摘要。** 「建置失敗」對下一個人毫無用處，完整訊息才能讓他三秒認出是同一個坑。
- **沒有內容的欄位整段省略**，不要留空陣列充數。
- 正文與 YAML **不准互相矛盾**。正文說未實測，YAML 就不能寫 `pass`——矛盾時以正文為準，但那代表你寫錯了一邊。

`<details>` 摺疊是刻意的：看板上預設只顯示人話，需要的人才展開。

### 其他註解也適用同一套規則

九條硬規則適用**所有**寫進票裡的註解，不只實作紀錄。各類註解的重點差異：

| 類型 | 第一句要講 | 需要 YAML 區嗎 |
| --- | --- | --- |
| 進度／卡關 | 現在卡在什麼、需要誰做什麼 | 不用 |
| 整合紀錄（合併後） | 程式碼已經進了哪個分支 | 要，至少 `commits` 與 `verification` |
| 解鎖通知（下游票） | 你現在可以直接用什麼 | 不用，但要具體到檔案路徑 |

寫 Markdown 時直接用真正的換行字元，不要寫成 `\n` 逸出序列——Linear MCP 會逐字保留，貼上去就是一團 `\n`。

## 收票後必做：解開被這張票擋住的其他票

**每次把一張票推到 `done` 之後，主動往下游檢查一輪，不要等使用者問。**

1. `get_issue({ id: 剛完成那張, includeRelations: true })`，取它 `blocks` 的下游票。
2. 對每一張下游票，各跑一次 `get_issue({ includeRelations: true })`，查它**自己的**所有 `blockedBy`，逐一確認狀態。
3. **所有** blocker 都已完成 → 這張票解鎖了，把它推到 `states.todo`（除非它已經在進行中或更後面的狀態，那就別動）。
4. 還有 blocker 沒完成 → 維持原狀不動，並在回報中寫清楚它還卡在哪張票。

解鎖時在下游票加一則簡短註解，說明是被哪張票（票號 + 標題）解開的，讓看板上看得出因果。

**判斷依據一律是實際查到的 blocker 狀態，不是推測。** 一張票只被一張票擋住不代表就是剛完成的那張——每次都要實查。

除了「blocker 全清 → 解鎖」這一種情形，**不要改動其他票的狀態**。要改別的（重排優先序、關掉重複票、改 Project 歸屬）先問使用者。

## Linear 專屬地雷

| 地雷 | 現象 | 對策 |
| --- | --- | --- |
| `includeArchived` 預設 **true** | 盤點會把封存的舊票一起撈回來，完成率與待辦數全部失真 | 每次 `list_issues` 明確送 `includeArchived: false` |
| 不指定 `fields` 會帶回 description | 十幾張票就數萬字元，且仍被截斷、對盤點無用 | 明確指定 `fields`，**不要**放 `description` |
| `labels` 是整組取代 | 加一個 label 會清掉其餘全部 | 先 `get_issue` 讀現有清單再送併集 |
| `state` 吃 id/名稱/type 三種 | 送 type 會撞到同型的其他欄（`started` 有兩欄） | 一律送 id |
| 關係查不到 | `list_issues` 不回傳 relations | `get_issue({ includeRelations: true })`，一票一次 |
| 優先序 `0` 不是最急 | Linear：0=None、1=Urgent、4=Low。當成數字排序會把「沒設優先序」排到最前面 | 排序時把 0 當最低，不是最高 |
| 沒有刪票工具 | 建錯的票只能到 Linear 手動刪，票號永久消耗 | 建票前確認清楚 |

## 「更新 Linear」的預設含義

使用者只說「更新 Linear」時，預設是三件都做：

1. 推狀態到當前階段該有的位置
2. 加實作紀錄註解
3. 檢查下游解鎖
