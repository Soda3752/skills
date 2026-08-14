---
name: linear-workflow-init
description: "把一個專案接上 Linear 票券工作流：先跑 doctor 診斷缺什麼（MCP 授權、workspace、team、六個核心狀態欄、api-require label、規則檔、設定檔、CLAUDE.local.md import），列出缺口讓使用者確認後一次補齊，收尾再審一輪該解未解的 Blocked 票。Use this whenever the user wants to wire a project up to the Linear workflow, check what a project is still missing for Linear automation, migrate inline Linear rules out of CLAUDE.local.md, or re-verify state ids after changing a team's workflow states. Triggers: \"初始化 linear 工作流\", \"幫這個專案接 linear\", \"linear doctor\", \"檢查 linear 設定缺什麼\", \"設定 linear 自動推票\", \"linear 工作流搬到獨立檔\", \"新專案接上 linear 流程\", \"set up linear workflow for this project\", \"onboard this repo to the linear ticket workflow\", \"diagnose linear workflow setup\", \"why isn't the linear status being pushed\". 帶參數 doctor 時只診斷不寫檔。"
---

# linear-workflow-init

把當前專案接上 Linear 票券工作流。先診斷、列缺口、等使用者確認，再一次補齊。

這是**機械式 SOP**。不要重新談判預設值——team、狀態名稱這些都在 `config/defaults.env` 裡，使用者要改會自己去改那個檔。唯一該問使用者的是 § 問使用者 那幾件事。

> 這份 skill 是 `jira-workflow-init` 的 Linear 版。行為刻意保持平行，但**不要照抄 Jira 版的實作細節**——兩邊的資料模型差異大到有些步驟整個消失、有些是全新的。差異見 § 與 Jira 版的根本差異。

## 兩種呼叫

| 呼叫 | 行為 |
| --- | --- |
| 無參數 | doctor 掃描 → 列缺口表 → 問使用者要不要補 → 安裝 → Blocked 審查 |
| 帶 `doctor` | **只輸出缺口表，一個檔都不寫**。使用者想先看現況再決定。 |

帶 `doctor` 時特別要守住「不寫檔」：使用者刻意用了唯讀模式，這時候順手幫他建檔案是幫倒忙——他可能正在確認別人的專案，或想先看差異再手動處理。

## 這個 skill 做完之後，專案會有什麼

```
<專案根>/
├── CLAUDE.local.md                # 多一行 @.claude/linear-workflow.md
└── .claude/
    ├── linear-workflow.md         # 工作流規則（純行為，值指向 json）
    └── linear-workflow.json       # 這個專案實際用的 team / 狀態 id
```

規則與值分開是刻意的。規則跨專案一字不改，換專案只換 json——所以規則檔日後可以整檔升版而不會弄壞任何專案的設定。

## 與 Jira 版的根本差異

移植時最容易出錯的地方是照搬 Jira 的心智模型。四點必須先內化：

**1. 沒有 transition，也沒有 transition id。** Linear 的狀態轉換沒有圖，任何狀態都能直接轉到任何狀態。所以 Jira 版那整套「抓一張票 → 查 transition → 反推 id → 撞號檢查 → `verified: false`」在這裡**完全不存在**。取而代之的是 `list_issue_statuses({ team })`，一次拿到該 team 全部狀態欄的 id / 名稱 / type，永遠是完整的。

**2. 沒有零票專案問題。** `list_issue_statuses` 不需要任何一張實體票就能查。Jira 版必須請使用者建一張探測票、還要解釋「票號永久消耗」——這個尷尬環節在 Linear 整個消失。**不要為了校正狀態去建票。**

**3. 新的摩擦點在別處：缺欄要人手去建。** Linear 新 team 只有 `Backlog / Todo / In Progress / Done / Canceled / Duplicate`，而這套工作流需要 `In Review` / `Blocked` / `API Require`。**MCP 沒有建立狀態欄的工具**，所以缺欄一定要使用者自己到 Linear 網頁建。這是 Linear 版 doctor 最常見的缺口。

**4. `projectKey` 換成 `team`。** Linear 的 Project 是另一個東西（工作分組容器，對應 Jira 的 Epic）。票的歸屬單位是 **Team**，票號前綴由 team 決定。搞混會查到空的看板。

## 先讀預設值

讀 `config/defaults.env`（相對於這個 skill 的目錄）。它是使用者手動維護的預設來源，欄位含義寫在檔案註解裡。

這些值只是**預設**。實際寫進專案的值以 doctor 探測與使用者選擇為準。

## doctor：八項檢查

依序跑。每項用 ✅ 已備 / ❌ 缺 / ⚠️ 需人工處理 標記，最後彙整成一張表輸出。

| # | 檢查 | 怎麼查 | 缺了怎麼辦 |
| --- | --- | --- | --- |
| 1 | Linear MCP 已授權 | `get_workspace` | **失敗即停**，見下方說明 |
| 2 | team 可見 | `list_teams`，確認 `DEFAULT_TEAM` 在清單裡 | 列出可見 team 讓使用者挑（見 § 問使用者 Q1） |
| 3 | 六個核心狀態欄 | `list_issue_statuses({ team })` 逐一比對 | 對不到的寫 `null` 並列進缺口，見 § 狀態校正 |
| 4 | `apiRequireLabel` 存在 | `list_issue_labels` | ⚠️ 不算硬缺口，見 § label 檢查 |
| 5 | 慣例探測 | 見 § 慣例探測 | 探不到就留空，不算缺口 |
| 6 | `.claude/linear-workflow.json` | 存在且欄位完整 | ❌ 待建 |
| 7 | `.claude/linear-workflow.md` | 存在且 frontmatter `workflow-version` 等於 `references/linear-workflow.md` 的版本 | ❌ 待建 / ⚠️ 可升版 / ⚠️ 無版本標記 |
| 8 | `CLAUDE.local.md` 有 import 行 | 含 `@.claude/linear-workflow.md` | ❌ 待加；若同時偵測到內嵌規則見 § 遷移 |

第 7 項**只比版本號，內容差異一律不管**。使用者本來就該能微調自己專案的規則檔而不被每次 doctor 嘮叨；只有標準版真的升版了才提醒。

### 第 1 項失敗就停

MCP 授權沒法用寫檔案解決——它需要互動式登入。這種情況下繼續往後跑只會連續失敗，然後在一個沒授權的環境裡建出一堆設定檔。所以直接停下，告訴使用者跑 `/mcp` 選 Linear 完成授權後再回來，並說明其餘七項因此未檢查。

### 狀態校正

`list_issue_statuses({ team })` 回傳該 team 的完整狀態清單，每筆有 `id` / `name` / `type`。逐一對應到六個核心 key。

#### 名稱比對規則

對每個回傳的狀態，依序試：

1. `name` 是否等於某個 `STATE_NAME_*`
2. `name` 是否等於某個 `STATE_ALTNAME_*`

**兩步的「等於」都是先 trim 前後空白、再折疊大小寫之後才比。** `Blocked` 與 `blocked`、`In Review` 與 `in review` 是同一欄；純粹人為的大小寫差異不該讓校正失敗。

語意不同的才是真的不同（`Backlog` 不是 `Todo`，別因為都是「還沒開始」就對上去——Linear 的 Backlog 是刻意與 Todo 分離的「還沒排進來」層）。

三種都不中的狀態**不是錯誤**——那是這個 team 多出來的欄。把它們記進 json 的 `extraStates`：

```json
"extraStates": [
  { "id": "3795655f-…", "name": "Backlog",   "type": "backlog"   },
  { "id": "bf9736bb-…", "name": "Canceled",  "type": "canceled"  },
  { "id": "9199e43c-…", "name": "Duplicate", "type": "duplicate" }
]
```

記錄而不納入六個核心 key，是因為工作流的三個必推時點只認得那六個。多出來的欄是專案自己的用法，工作流不該擅自推票進去——但接手的人知道它存在會有幫助。

#### 缺欄一律寫 `null`，不要找相近的頂替

對不到的核心 key 在 json 裡寫 `null`。**絕對不要拿一個型別相同或名字相近的欄去頂替。**

理由跟 Jira 版的撞號檢查是同一個，但在 Linear 更危險：Jira 送錯 transition id 至少有機會被 workflow scheme 擋下來；Linear 任何狀態都能互轉，**推到錯的欄一定成功、一定不報錯**。例如把 `inReview` 對到 `In Progress`（兩者 type 都是 `started`），從此每次「進入驗證」都會把票推回進行中，看板上完全看不出異常。

寫 `null` 才安全：規則檔讀到 `null` 會停下來問使用者。

#### 缺欄怎麼補：只能請使用者去建

**MCP 沒有建立狀態欄的工具。** 缺 `In Review` / `Blocked` / `API Require` 時，把手順明確寫給使用者，不要只說「請去建」：

```
Linear → 左下角 Settings → Teams → <team 名> → Workflow
→ 對應區塊按 + New status，填名稱後儲存

建議的名稱與型別（來自 defaults.env）：
  In Review     type: started      ← 放在 In Progress 之後
  Blocked       type: unstarted
  API Require   type: unstarted
```

**型別的選擇不是美觀問題。** `started` 會被 Linear 算進「正在進行」的 cycle 進度與統計；`Blocked` / `API Require` 用 `unstarted` 是因為那些票實際上沒有人在推進，算進進行中會讓 cycle 燃盡圖失真，也會讓 `check-linear-status` 的「收尾優先」排序把一堆卡死的票排到最前面。

使用者建完之後**重跑一次第 3 項**確認，再寫設定檔。不要憑他說「建好了」就寫——名稱打錯一個空格就對不上。

### label 檢查

`list_issue_labels` 查 `API_REQUIRE_LABEL` 存不存在。

不存在**不算硬缺口**：`save_issue` 的 `labels` 參數送一個不存在的名稱時，Linear 會自動建立該 label。所以標 ⚠️ 提一句「首次推 API Require 時會自動建立」就好，不要為了它停下流程。

若已存在，把它的 id 一併記進設定檔，省掉之後每次的名稱解析。

### 慣例探測

用 `list_issues` 抽樣既有票，推出這個專案的實際慣例，寫進 json 當上下文：

- 各狀態欄的票數分佈（`Blocked` 欄有票在用，代表這個流程真的在跑）
- 專案裡出現過哪些 label
- 既有的 Linear Project 有哪些（`list_projects`），新票習慣掛在哪個底下

**回傳量要壓下來。** 兩個參數一定要送：

```
list_issues({
  team: "<team>",
  includeArchived: false,                       ← 預設是 true，不送會撈到封存票
  limit: 100,
  fields: ["id","title","status","statusType","labels","project","priority","updatedAt"]
})
```

不指定 `fields` 會帶回 description（即使被截斷仍然很長），十幾張票就數萬字元。`includeArchived` 預設 `true` 是 Linear 特有的坑：不關掉會把歷史封存票混進統計，於是你回報的「完成 47 張」其實包含三年前的東西。

探測不到不算缺口——新專案本來就是空的。這一步的價值在於接手**既有**專案時，不用每次從零摸索它的分類習慣。

## 問使用者

用 `AskUserQuestion`。除了這幾題不要再問別的。

### Q1：選 team

只在第 2 項需要決定時問（`DEFAULT_TEAM` 不在可見清單，或 workspace 上有多個 team 且無法從分支名的票號前綴確定）。

列出 `list_teams` 的結果（名稱 + 票號前綴），`DEFAULT_TEAM` 排第一並標「defaults.env 預設」。選完驗證它真的存在才寫進設定檔。

workspace 只有一個 team 時**不要問**——沒有第二個選項的問題只是浪費一次點擊。

### Q2：確認補齊缺口

列完缺口表之後問一次，選項依實際缺口動態組：

- 全部補齊（推薦）
- 只補設定檔與規則檔，不動 `CLAUDE.local.md`
- 取消，什麼都不寫

若表上有「遷移內嵌規則」這一項，把它在選項描述裡講明——那是唯一會改到使用者手寫內容的動作，他有權單獨拒絕。

**狀態欄缺口不列進這一題的選項**，因為它不是「要不要補」的問題——你補不了，只有使用者能補。它在缺口表裡標 ⚠️ 並附手順，然後照常往下走：設定檔照建，缺的 key 寫 `null`。

若八項全部 ✅，**不要走這個問答**。直接說「已設定完成，無事可做」，然後只跑 Blocked 審查。

## 安裝

### `.claude/linear-workflow.json`

```json
{
  "workspace": "<get_workspace 回傳的 name>",
  "workspaceUrl": "<get_workspace 回傳的 url>",
  "team": "<選定的 team 名稱>",
  "teamId": "<team UUID>",
  "ticketPrefix": "<從既有票號抽出的前綴，例如 PROJ>",
  "states": {
    "todo":       { "id": "…", "name": "Todo",        "type": "unstarted" },
    "inProgress": { "id": "…", "name": "In Progress", "type": "started"   },
    "inReview":   null,
    "block":      null,
    "apiRequire": null,
    "done":       { "id": "…", "name": "Done",        "type": "completed" }
  },
  "extraStates": [{ "id": "…", "name": "Backlog", "type": "backlog" }],
  "containerMode": "<CONTAINER_MODE>",
  "apiRequireLabel": "<API_REQUIRE_LABEL>",
  "apiRequireLabelId": "<存在才寫>",
  "ticketSource": "branch+api",
  "branchPattern": "<BRANCH_TICKET_PATTERN>",
  "commentLanguage": "<COMMENT_LANGUAGE>",
  "conventions": {
    "statusCounts": { "Todo": 3, "In Progress": 1 },
    "labelsSeen": ["bug", "…"],
    "projects": [{ "id": "…", "name": "登入流程改版" }]
  }
}
```

`conventions` 是探測結果，探不到的欄位就省略，不要塞空值——空陣列會讓下次讀的人以為「確認過沒有」，而其實是「沒查到」。

`ticketPrefix` 抽不到（team 一張票都沒有）就省略。它只是給分支比對當輔助，缺了不影響運作。

### `.claude/linear-workflow.md`

把 `references/linear-workflow.md` 整檔複製過去，frontmatter 的 `workflow-version` 保持原樣。不要在複製時把值插進文字——那份規則刻意寫成指向 json，插值會讓它日後無法整檔升版。

### `CLAUDE.local.md` import 行

檔案不存在 → 建立，內容就是一個 `## Linear 票券` 段落加 import 行。

檔案存在但沒有 import 行 → 加上：

```markdown
## Linear 票券

@.claude/linear-workflow.md
```

用 `Edit` 或 `Write` 工具，不要用 shell 的 append——尾端換行的邊界情況 shell 很容易弄壞。

**若這個專案同時也有 `@.claude/jira-workflow.md` 的 import 行，停下來問使用者。** 兩套票券工作流同時載入會讓模型在推狀態時不知道該推哪邊，而且兩份規則對「更新票券」的預設含義都有定義，會直接打架。正常情況是二選一。

### 遷移內嵌規則

第 8 項若偵測到 `CLAUDE.local.md` 裡已經內嵌了整段 Linear 規則（找「Linear」+「狀態」/「推票」/「實作紀錄」這類關鍵字構成的段落），這是既有專案的典型狀態：規則有效但無法升版。

處理順序，使用者在 Q2 同意之後才做：

1. `cp CLAUDE.local.md CLAUDE.local.md.bak` — 先備份。這是整個 skill 唯一會改到使用者手寫內容的動作，備份不是可選項。
2. 把那個段落整段換成 import 行，保留段落標題與周圍其他段落的相對位置
3. 規則檔內容以 `references/linear-workflow.md` 標準版為準，**不要**試著合併使用者原文的措辭差異
4. 回報時明講：原文已備份到 `CLAUDE.local.md.bak`，若標準版漏了他原本有的規則，從備份撈回來

## 收尾：Blocked 審查

不論這次有沒有安裝東西，最後都跑一輪。這是規則檔裡「解下游 Blocked」那段 SOP 的一次性補跑——接手既有專案時，通常已經積了幾張該解未解的票。

1. `list_issues({ team, state: "<states.block.id>", includeArchived: false, fields: [...] })`——**只掃 Blocked，不含 API Require**
2. 每張票跑 `get_issue({ id, includeRelations: true })`，逐一確認它的 `blockedBy` 狀態
3. 分兩組列出：blocker 全完成的（可解鎖）、還有 blocker 未完成的（維持，寫清楚卡在誰身上）

`states.block` 是 `null` 時整段跳過並說明原因——沒有那一欄就不會有票卡在那裡。

不掃 API Require 的理由：那些票的性質是「等後端交東西」，不是「被另一張票擋住」，逐張查關係查不出東西。而且它們通常量最大，全查等於一堆額外呼叫換一份空結果。**這一點在 Linear 比 Jira 更值得守**，因為每張票都要獨立一次 `get_issue`，成本是線性的。

**blocker 停在中間狀態時要說出來。** blocker 不是完成也不是待辦，而是卡在 In Review／In Progress 時，下游確實還不能解鎖——但這往往代表 blocker 本身的狀態沒跟上（程式早就 commit 了，票忘了推完成）。這種情形用 ⚠️ 標出來，比單純寫「維持 Blocked」有用得多，因為真正該處理的是上游那張票。

```
〔Blocked 審查〕
PROJ-33 卡 Blocked
  ▸ blocked by PROJ-41 ✅ Done
  ▸ blocked by PROJ-12 ✅ Done
  → 可解鎖（建議推 Todo）

PROJ-44 卡 Blocked
  ▸ blocked by PROJ-9  ✅ Done
  ▸ blocked by PROJ-52 ⚠️ In Progress
  → 維持 Blocked（真正該推的是 PROJ-52）
```

**只列表，不自動推狀態。** 解鎖是改動別人的票，而且 blocker 全清不代表下游立刻該開工（可能有優先序考量）。使用者看完自己決定。

## 冪等

重跑要安全：

- 八項全 ✅ → 說「已設定完成，無事可做」，只跑 Blocked 審查
- 規則檔已存在且版本相符 → 不覆寫
- import 行已存在 → 不重複加
- `CLAUDE.local.md.bak` 已存在 → 遷移前改用帶序號的備份名，別蓋掉上次的備份
- 設定檔已存在但某個核心狀態是 `null` → 重查一次；使用者可能已經去 Linear 補建了那一欄

最後一條是 Linear 版特有的：缺欄要人手補，所以「重跑 doctor」是使用者補完欄位之後的**正常後續動作**，不是異常。

## 不要做的事

- **不要**為了校正狀態去建任何票。Linear 不需要（見 § 與 Jira 版的根本差異 第 2 點）。
- **不要**在缺欄時挑一個相近的欄頂替。Linear 推錯欄不會報錯。
- **不要**執行 `git add` 或 commit。使用者決定什麼進版控。
- **不要**自動推任何票的狀態。這個 skill 只建置環境和回報。
- **不要**動 `.gitignore`。`linear-workflow.json` 含 workspace 名與 state UUID，進不進版控由使用者決定。
- **不要**把 doctor 的輸出存成報告檔。這是診斷，直接輸出在對話裡。
- **不要**在授權失敗時「先建檔案等一下再說」。沒授權就沒法驗證任何值。
