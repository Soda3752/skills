---
name: jira-workflow-init
description: "把一個專案接上 Jira 票券工作流：先跑 doctor 診斷缺什麼（MCP 授權、站台、project key、transition id、issue link types、規則檔、設定檔、CLAUDE.local.md import），列出缺口讓使用者確認後一次補齊，收尾再審一輪該解未解的 Block 票。Use this whenever the user wants to wire a project up to the Jira workflow, check what a project is still missing for Jira automation, migrate inline Jira rules out of CLAUDE.local.md, or re-verify transition ids after a Jira workflow scheme change. Triggers: \"初始化 jira 工作流\", \"幫這個專案接 jira\", \"jira doctor\", \"檢查 jira 設定缺什麼\", \"設定 jira 自動推票\", \"jira 工作流搬到獨立檔\", \"新專案接上 jira 流程\", \"set up jira workflow for this project\", \"onboard this repo to the jira ticket workflow\", \"diagnose jira workflow setup\", \"why isn't the jira status being pushed\". 帶參數 doctor 時只診斷不寫檔。"
---

# jira-workflow-init

把當前專案接上 Jira 票券工作流。先診斷、列缺口、等使用者確認，再一次補齊。

> 文中的 `PROJ` 與 `ACME` 是兩個真實專案的匿名代號。那些實例保留下來是因為它們解釋了「為什麼要有這條規則」——規則本身看起來都很像過度謹慎，直到你知道它是踩過哪個坑才長出來的。

這是**機械式 SOP**。不要重新談判預設值——站台、transition id 這些都在 `config/defaults.env` 裡，使用者要改會自己去改那個檔。唯一該問使用者的是 § 問使用者 那兩件事。

## 兩種呼叫

| 呼叫 | 行為 |
| --- | --- |
| 無參數 | doctor 掃描 → 列缺口表 → 問使用者要不要補 → 安裝 → Block 審查 |
| 帶 `doctor` | **只輸出缺口表，一個檔都不寫**。使用者想先看現況再決定。 |

帶 `doctor` 時特別要守住「不寫檔」：使用者刻意用了唯讀模式，這時候順手幫他建檔案是幫倒忙——他可能正在確認別人的專案，或想先看差異再手動處理。

## 這個 skill 做完之後，專案會有什麼

```
<專案根>/
├── CLAUDE.local.md              # 多一行 @.claude/jira-workflow.md
└── .claude/
    ├── jira-workflow.md         # 工作流規則（純行為，值指向 json）
    └── jira-workflow.json       # 這個專案實際用的站台 / project / transition id
```

規則與值分開是刻意的。規則跨專案一字不改，換專案只換 json——所以規則檔日後可以整檔升版而不會弄壞任何專案的設定。

## 先讀預設值

讀 `config/defaults.env`（相對於這個 skill 的目錄）。它是使用者手動維護的預設來源，欄位含義寫在檔案註解裡。

這些值只是**預設**。實際寫進專案的值以 doctor 探測與使用者選擇為準。

## doctor：九項檢查

依序跑。每項用 ✅ 已備 / ❌ 缺 / ⚠️ 未驗證 標記，最後彙整成一張表輸出。

| # | 檢查 | 怎麼查 | 缺了怎麼辦 |
| --- | --- | --- | --- |
| 1 | Jira MCP 已授權 | `atlassianUserInfo` | **失敗即停**，見下方說明 |
| 2 | 站台可存取 | `getAccessibleAtlassianResources`，確認 `JIRA_SITE` 在清單裡 | 停，回報使用者這個帳號看不到該站台 |
| 3 | project key 可見 | `getVisibleJiraProjects` | 列出可見 project 讓使用者挑（見 § 問使用者 Q1） |
| 4 | transition 表 | 見 § transition 校正 | 對不到的先撞號檢查：沒撞號才沿用 env 並標 `verified:false`，撞號寫 `null`。專案零票見 § 零票專案 |
| 5 | issue link types | `getIssueLinkTypes` 有 Blocks / is blocked by | ⚠️ 並告知「解下游 Block」那段 SOP 在此站台會空轉 |
| 6 | 票號分類慣例 | 見 § 慣例探測 | 探不到就留空，不算缺口 |
| 7 | `.claude/jira-workflow.json` | 存在且欄位完整 | ❌ 待建 |
| 8 | `.claude/jira-workflow.md` | 存在且 frontmatter `workflow-version` 等於 `references/jira-workflow.md` 的版本 | ❌ 待建 / ⚠️ 可升版 / ⚠️ 無版本標記 |
| 9 | `CLAUDE.local.md` 有 import 行 | 含 `@.claude/jira-workflow.md` | ❌ 待加；若同時偵測到內嵌規則見 § 遷移 |

第 8 項**只比版本號，內容差異一律不管**。使用者本來就該能微調自己專案的規則檔而不被每次 doctor 嘮叨；只有標準版真的升版了才提醒。

### 第 1 項失敗就停

MCP 授權沒法用寫檔案解決——它需要互動式登入。這種情況下繼續往後跑只會連續失敗，然後在一個沒授權的環境裡建出一堆設定檔。所以直接停下，告訴使用者跑 `/mcp` 完成 Atlassian 授權後再回來，並說明其餘八項因此未檢查。

### transition 校正

1. 用 JQL 抓專案任一張票（`project = <key> ORDER BY updated DESC`，取一張就好）。**抓不到票見 § 零票專案**
2. `getTransitionsForJiraIssue` 帶 **`includeUnavailableTransitions: true`** 查它的 transitions
3. 逐一比對，反推出六個核心 key 對應的 id（比對規則見下）
4. 對到的 → 以實查的 id 為準。**若與 env 不同，在表格裡明白寫出差異**（`inReview: env=31 → 實查=32`），這代表 env 過期或這個 project 用了不同 workflow scheme

**能不能一次拿到全表，看專案類型。** next-gen（`simplified: true`）專案的 transition 通常全是 `isGlobal: true`——任何狀態都能轉到任何狀態，所以一張票就回傳完整表，六個 key 全部驗證得到。classic 專案的 transition 綁在特定狀態上，這時就算帶了 `includeUnavailableTransitions` 也只拿到與當前狀態相關的那些。

判斷方式：看回傳的 transition 是否多數帶 `isGlobal: true`。

- **全表拿到** → 六個 key 全標 `verified: true`
- **只拿到部分** → 缺的**先做撞號檢查再決定沿用或留空**（見下）。不要為了補齊而去各狀態各抓一張票逐一查——那是 5–6 次額外 API 呼叫，而且票源不齊（例如沒有任何票在 Block）時照樣補不完。

標 `false` 不是失敗，是誠實記錄「這個 id 沒被證實過」。規則檔本來就要求每次推狀態前實查一次，所以未驗證的 id 不會直接造成災難——但使用者有權知道哪幾個是猜的。

#### 沿用 env 之前必須撞號檢查

**`verified: false` 防不住撞號。** 沿用 env 的 id 之前，檢查那個 id 是否已經被這次實查對到的其他 key 佔用；佔用了就寫 `null`，不要沿用。

ACME 的實例說明為什麼這條非有不可。實查得到 `todo=21`、`inProgress=31`、`done=41`，缺 `inReview`／`block`。而 env 的值是 `TRANSITION_INREVIEW=31`、`TRANSITION_BLOCK=41`——那兩個 id 在 ACME 分別是「進行中」與「完成」。照「沿用 env」辦，推審核中會靜默把票推進**進行中**，推 Block 會直接推進**完成**。`verified: false` 完全擋不住，因為值看起來是有效的 id，實查也會成功，只是推錯欄。

寫 `null` 才安全：規則檔讀到 `null` 會停下來問使用者，而讀到一個能用的錯 id 只會照推。**id 撞號時，留空比猜測嚴格地好。**

沒撞號的才沿用 env 並標 `verified: false`。無論沿用或留空，都要在缺口表裡逐一寫明是哪一種。

#### 零票專案

剛建好的 project 一張票都沒有，而 `getTransitionsForJiraIssue` 需要一張實體票——所以第 4 項在新專案上必然卡住。這是接新專案的常態，不是意外。

沒有捷徑可繞：MCP 讀不到 project 的狀態欄清單（`fetch` 只吃 ARI，打不了任意 REST endpoint），`getJiraProjectIssueTypesMetadata` 只給 issue type 不給狀態。**唯一辦法是專案裡有一張票。**

處理順序：

1. **先確認狀態欄已建齊再探測。** 新建的專案通常只有預設三欄（待辦事項／進行中／完成），這時探測只會拿到三個 key，另外三個還是缺。先讓使用者把欄位補齊，一次探測就能六個 key 全驗證，省一輪往返。
2. **建探測票要先取得使用者授權**，別自己動手。這是寫進他 Jira 的東西。
3. 建票時把用途寫進摘要與描述（例如 `[環境探測] jira-workflow-init 用於校正 transition id，可刪`），讓它在看板上不會變成來歷不明的垃圾票。
4. 查完 transition 後**明確告知使用者這張票的下場由他決定**。

**要事先講明的兩件代價**，別等使用者問：

- **MCP 沒有 delete issue 工具**（只有 create／edit／comment／transition），所以這張票你刪不掉，只能請他到 Jira 手動刪（開票 → 右上 `⋯` → 刪除）。
- 票號**永久消耗**，刪掉也不會回收——`ACME-1` 用掉了，第一張真正的工作票就是 `ACME-2`。有些人在意編號從 1 開始，所以這件事值得先說。

另一條路是請使用者自己去建第一張**真正的工作票**，拿它來探測。不消耗廢票號、也不留垃圾，代價是多一次往返。使用者若在意編號整齊，優先建議這條。

#### 名稱比對規則

transition 的 `name` 與它目標狀態的 `to.name` 可能不同。PROJ 的實例：transition `name: "In Review"`，但 `to.name: "審核中"`——看板上顯示的是後者。只比對其中一邊會漏。

對每個 transition，依序試：

1. `to.name` 是否等於某個 `STATUS_NAME_*`
2. transition `name` 是否等於某個 `STATUS_NAME_*`
3. 兩者是否等於某個 `STATUS_ALTNAME_*`

**這三步的「等於」都是先 trim 前後空白、再折疊大小寫之後才比。** ACME 的欄位叫 `BLOCK`，env 寫的是 `STATUS_NAME_BLOCK=Block`——嚴格字串相等會漏掉，然後把一個明明存在的核心狀態欄誤記成 `extraStatuses`，`block` 那個 key 反而空著。這種純粹人為的大小寫差異不該讓校正失敗。

語意不同的才是真的不同（`PENDING` 不是 `API Require`，別因為都是「等別人」就對上去）。

任一命中就算對到。三種都不中的 transition **不是錯誤**——那是這個專案多出來的狀態欄（PROJ 就有第七個 `PENDING`，id 3，2 張票在用）。把它們記進 json 的 `extraStatuses`：

```json
"extraStatuses": [{ "id": "3", "name": "PENDING" }]
```

記錄而不納入六個核心 key，是因為工作流的三個必推時點只認得那六個。多出來的狀態欄是專案自己的用法，工作流不該擅自推票進去——但接手的人知道它存在會有幫助。

### 慣例探測

用 JQL 抽樣專案現有票，推出這個專案的實際慣例，寫進 json 當上下文：

- 各狀態欄的票數分佈（Block 欄有票在用，代表這個流程真的在跑）
- 專案裡出現過哪些 label，特別是 `API_REQUIRE_LABEL` 有沒有在用
- Epic 結構：有哪些 Epic、缺口票習慣掛在哪個 Epic 底下

探測不到不算缺口——新專案本來就是空的。這一步的價值在於接手**既有**專案時，不用每次從零摸索它的分類習慣。

**JQL 回傳量要壓下來。** `searchJiraIssuesUsingJql` 即使指定了 `fields`，回傳裡仍然帶完整 description——PROJ 抓 50 張票就是 24 萬字元，直接超過單次工具回傳上限。所以這一步不要把結果讀進上下文，而是讓它落到檔案後用 `jq` 只取需要的欄位：

```bash
jq -r '[.issues.nodes[].fields.status.name] | group_by(.) | map("\(length)\t\(.[0])") | .[]' <file>
jq -r '[.issues.nodes[].fields.labels[]?] | group_by(.) | map("\(length)\t\(.[0])") | .[]' <file>
jq -r '[.issues.nodes[].fields.parent? | select(.!=null) | "\(.key) \(.fields.summary)"] | unique | .[]' <file>
```

工具在超量時會把完整 JSON 存到檔案並回報路徑，直接對那個路徑跑 jq。若專案票數少（幾張）而沒有超量，直接讀回傳也行——但別預設它一定不會爆。

## 問使用者

用 `AskUserQuestion`。除了這兩題不要再問別的。

### Q1：選 Jira project

只在第 3 項需要決定時問（`DEFAULT_PROJECT_KEY` 不在可見清單，或站台上有多個 project 且無法從分支名確定）。

列出 `getVisibleJiraProjects` 的結果（key + 名稱），`DEFAULT_PROJECT_KEY` 排第一並標「defaults.env 預設」。選完驗證它真的存在才寫進設定檔。

若 `DEFAULT_PROJECT_KEY` 就在可見清單裡、而且 git 分支名抽出的票號前綴也指向它，那就不必問——證據已經足夠了，問了只是浪費使用者一次點擊。

### Q2：確認補齊缺口

列完缺口表之後問一次，選項依實際缺口動態組：

- 全部補齊（推薦）
- 只補設定檔與規則檔，不動 `CLAUDE.local.md`
- 取消，什麼都不寫

若表上有「遷移內嵌規則」這一項，把它在選項描述裡講明——那是唯一會改到使用者手寫內容的動作，他有權單獨拒絕。

若九項全部 ✅，**不要走這個問答**。直接說「已設定完成，無事可做」，然後只跑 Block 審查。走完整流程去產出「什麼都沒改」的結果，只會讓使用者懷疑到底有沒有動到東西。

## 安裝

### `.claude/jira-workflow.json`

```json
{
  "site": "<JIRA_SITE>",
  "projectKey": "<選定的 key>",
  "projectName": "<選定 project 的名稱>",
  "transitions": {
    "todo": "…", "inProgress": "…", "inReview": "…",
    "block": "…", "apiRequire": "…", "done": "…"
  },
  "verified": {
    "todo": true, "inProgress": true, "inReview": true,
    "block": true, "apiRequire": true, "done": true
  },
  "extraStatuses": [{ "id": "3", "name": "PENDING" }],
  "apiRequireLabel": "<API_REQUIRE_LABEL>",
  "ticketSource": "branch+jql",
  "branchPattern": "<BRANCH_TICKET_PATTERN>",
  "commentLanguage": "<COMMENT_LANGUAGE>",
  "conventions": {
    "blockColumnInUse": true,
    "labelsSeen": ["api-require", "…"],
    "epics": [{ "key": "PROJ-17", "summary": "…" }]
  }
}
```

`conventions` 是探測結果，探不到的欄位就省略，不要塞空值——空陣列會讓下次讀的人以為「確認過沒有」，而其實是「沒查到」。

### `.claude/jira-workflow.md`

把 `references/jira-workflow.md` 整檔複製過去，frontmatter 的 `workflow-version` 保持原樣。不要在複製時把值插進文字——那份規則刻意寫成指向 json，插值會讓它日後無法整檔升版。

### `CLAUDE.local.md` import 行

檔案不存在 → 建立，內容就是一個 `## Jira 票券` 段落加 import 行。

檔案存在但沒有 import 行 → 加上：

```markdown
## Jira 票券

@.claude/jira-workflow.md
```

用 `Edit` 或 `Write` 工具，不要用 shell 的 append——尾端換行的邊界情況 shell 很容易弄壞。

### 遷移內嵌規則

第 9 項若偵測到 `CLAUDE.local.md` 裡已經內嵌了整段 Jira 規則（找「Jira」+「transition」/「推狀態」/「實作紀錄」這類關鍵字構成的段落），這是既有專案的典型狀態：規則有效但無法升版。

處理順序，使用者在 Q2 同意之後才做：

1. `cp CLAUDE.local.md CLAUDE.local.md.bak` — 先備份。這是整個 skill 唯一會改到使用者手寫內容的動作，備份不是可選項。
2. 把那個段落整段換成 import 行，保留段落標題與周圍其他段落的相對位置
3. 規則檔內容以 `references/jira-workflow.md` 標準版為準，**不要**試著合併使用者原文的措辭差異——標準版已經涵蓋同樣的行為，而且多了原文沒有的部分（`block` vs `apiRequire` 判準、當前票來源）
4. 回報時明講：原文已備份到 `CLAUDE.local.md.bak`，若標準版漏了他原本有的規則，從備份撈回來

## 收尾：Block 審查

不論這次有沒有安裝東西，最後都跑一輪。這是規則檔裡「解下游 Block」那段 SOP 的一次性補跑——接手既有專案時，通常已經積了幾張該解未解的票。

1. JQL 抓 `status` 在 Block 的票——**只掃 Block，不含 API Require**
2. 每張票查它自己的 `is blocked by`（inward）連結，逐一確認 blocker 狀態
3. 分兩組列出：blocker 全完成的（可解鎖）、還有 blocker 未完成的（維持，寫清楚卡在誰身上）

不掃 API Require 的理由：那些票的性質是「等後端交東西」，不是「被另一張票擋住」，逐張查 `issuelinks` 查不出東西。而且它們通常量最大（PROJ 有 17 張），全查等於 17 次額外 API 呼叫換一份空結果。

**blocker 停在中間狀態時要說出來。** blocker 不是「完成」也不是「待辦」，而是卡在審核中／進行中時，下游確實還不能解鎖——但這往往代表 blocker 本身的狀態沒跟上（程式早就 commit 了，票忘了推完成）。這種情形在列表裡用 ⚠️ 標出來，比單純寫「維持 Block」有用得多，因為真正該處理的是上游那張票。

```
〔Block 審查〕
PROJ-33 卡 Block
  ▸ blocked by PROJ-41 ✅ 完成
  ▸ blocked by PROJ-12 ✅ 完成
  → 可解鎖（建議推 todo）

PROJ-44 卡 Block
  ▸ blocked by PROJ-9  ✅ 完成
  ▸ blocked by PROJ-52 ❌ 進行中
  → 維持 Block
```

**只列表，不自動推狀態。** 解鎖是改動別人的票，而且 blocker 全清不代表下游立刻該開工（可能有優先序考量）。使用者看完自己決定。

若第 5 項顯示站台沒有 Blocks / is blocked by 連結類型，跳過這段並說明原因。

## 冪等

重跑要安全：

- 九項全 ✅ → 說「已設定完成，無事可做」，只跑 Block 審查
- 規則檔已存在且版本相符 → 不覆寫
- import 行已存在 → 不重複加
- `CLAUDE.local.md.bak` 已存在 → 遷移前改用帶序號的備份名，別蓋掉上次的備份

## 不要做的事

- **不要**執行 `git add` 或 commit。使用者決定什麼進版控。
- **不要**自動推任何票的狀態。這個 skill 只建置環境和回報，推票是日常工作流的事。
- **不要**動 `.gitignore`。`jira-workflow.json` 只含站台 hostname 與 project key，進不進版控由使用者決定，不需要 skill 代為判斷。
- **不要**把 doctor 的輸出存成報告檔。這是診斷，直接輸出在對話裡；使用者要留存自己會說。
- **不要**在授權失敗時「先建檔案等一下再說」。沒授權就沒法驗證任何值，建出來的設定檔全是未證實的猜測。
