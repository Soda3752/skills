---
name: check-jira-status
description: "盤點當前專案的 Jira 未完成票，算出哪些真的可動（blocker 全清）、哪些卡住、卡在誰，並依「收尾優先 → 解鎖效益 → 優先序」建議下一張該做的票；順帶回報狀態不一致（分支已動工票沒推、票卡在進行中被遺忘、blocker 全清卻還停在 Block、審核中但實作 commit 早就進去了）。這是唯讀盤點，絕不改任何票。Use this whenever the user asks what to work on next, wants a status sweep of the board, asks which tickets are unblocked or actionable, wonders whether the board reflects reality, or is picking up work after time away. Triggers: \"盤點 jira\", \"檢查 jira 狀態\", \"接下來做哪張\", \"下一張票\", \"現在該做什麼\", \"看板現況\", \"哪些票可以動\", \"哪些票卡住了\", \"我做到哪了\", \"jira 狀態對不對\", \"check jira status\", \"what should I work on next\", \"which tickets are unblocked\", \"what's the state of the board\", \"where did I leave off\". 使用者只說「下一步做什麼」而當前專案有 .claude/jira-workflow.json 時也該觸發。"
---

# check-jira-status

盤點 Jira 現況，回報「下一張該做哪張票」以及「看板哪裡跟現實脫節」。

這是 `jira-workflow-init` 那套工作流（見它的 `references/jira-workflow.md`）的**唯讀**延伸。那份工作流負責推票，這個 skill 只負責看清楚——**一張票都不要動**。理由不是保守：盤點是使用者用來做決策的動作，如果盤點本身會改看板，他就沒辦法先看現況再決定。發現不一致就列進「待修正」區，讓他自己決定推不推。

## 流程

### 1. 讀設定

讀專案根的 `.claude/jira-workflow.json`，取 `site`、`projectKey`、`branchPattern`、`conventions.hierarchyLevel1IssueType`。

沒有這個檔案就停下來，告訴使用者這個專案還沒接上 Jira 工作流，可以跑 `/jira-workflow-init`。硬猜 project key 只會盤點到別人的看板。

### 2. 抽當前分支的票號

`git rev-parse --abbrev-ref HEAD`，用 `branchPattern` 抽票號。抽不到很正常（`main`、或 `refactor/kmp-mvvm-architecture` 這種），不要因此停住——盤點不需要票號也能跑，票號只是用來標記「分支對到這張」和偵測不一致。

### 3. 一次 JQL 抓完未完成票

```
project = <projectKey> AND statusCategory != Done ORDER BY created DESC
```

`fields` 一定要指定，**而且不要抓 `description`**：

```
["summary", "status", "issuetype", "parent", "priority", "labels", "issuelinks", "updated", "assignee", "duedate"]
```

不指定 fields 會預設帶 `description` 回來，實測一個 29 張票的小專案就吐出 31 萬字元、直接超過工具上限。`description` 對盤點毫無用處——要決定做哪張票，看 summary 和依賴就夠了，內文是動工之後才要讀的。

`maxResults` 給 100。

**一次就夠，不要對 blocker 逐張補查。** `issuelinks` 回傳時已經內嵌對方的 `key`、`summary` 和完整 `status`（含 `statusCategory`），所以可動性完全能從這一份結果算出來。看到「要判斷 blocker 完成了沒」就反射去打 `getJiraIssue` 是白花十幾次往返。

#### assignee 篩選要留退路

如果使用者的看板有在指派人，加上 `AND assignee = currentUser()` 能讓報告更聚焦。但**先確認這樣篩得到票**：很多個人專案根本不指派 assignee（實測 ACME 專案 29 張票全部未指派），這時候加了條件會回傳 0 張，然後你會誤報「沒有待辦事項」——那是最糟的失敗，因為它看起來像好消息。

穩健做法：直接用不含 assignee 的查詢，看回傳裡 `assignee` 是否普遍有值。若多數有值且屬於他人，才在報告中依 assignee 分組並聚焦本人的票，同時說明範圍。

### 4. 用腳本算盤點結果

**這一步預設就走腳本。** 即使已經照上面把 fields 壓到最小、只抓未完成票，回傳通常仍會超過工具上限而被自動落地成檔案——`issuelinks` 每筆都內嵌對方完整的 status / priority / issuetype 物件，實測 12 張未完成票就有 87,165 字元。所以正常情況下你手上會是一個檔案路徑，而不是 context 裡的 JSON。這其實是好事：整份原始資料不必進 context。

```bash
python3 <skill 目錄>/scripts/inventory.py <落地的 json 檔> \
  --container-type "工作流" --branch-tickets ACME-16
```

`--container-type` 傳設定檔的 `conventions.hierarchyLevel1IssueType`，`--branch-tickets` 傳步驟 2 抽到的票號（抽不到就省略）。腳本直接輸出下面那個格式，`--json` 可取機器可讀版本。

罕見情況下結果沒超限、直接落在 context 裡（票很少、依賴很稀疏），照下面的判準自己推算就好，不必為了跑腳本把 JSON 抄進檔案。

下面五條判準是腳本已經實作的邏輯。列出來有兩個用途：手算時照著做；以及當結果看起來不對時，你能判斷是資料問題還是判準沒對上實際看板。

#### 判準一：方向不能靠 `type` 字串判斷

`issuelinks[].type` 物件裡 `inward` 和 `outward` **兩個描述字串永遠都在**，所以 `type.outward == "blocks"` 這種判斷在任何一筆連結上都會成立，方向會整批反過來。唯一可靠的判準是哪個鍵存在：

| 鍵 | 意思 |
| --- | --- |
| `inwardIssue` | 這張票 **is blocked by** 對方 → 對方擋我 |
| `outwardIssue` | 這張票 **blocks** 對方 → 我擋對方 |

方向搞反的後果不是小瑕疵：整份「可動 / 卡住」會完全顛倒，然後你會叫使用者去做一張根本動不了的票。

#### 判準二：完成一律看 `statusCategory.key == "done"`

不要比對狀態名稱。名稱會因專案語言與自訂而不同（這個站台是「完成」、「待辦事項」、「審核中」，還有自訂的 `PENDING`），但 `statusCategory` 只有 `new` / `indeterminate` / `done` 三種，跨專案穩定。

#### 判準三：容器票不是可執行任務

`issuetype.hierarchyLevel > 0` 的票（Epic，本專案叫「工作流」）是分組容器，不要建議使用者去「做」它——它沒有可動工的內容。它們適合當分組標題（票的 `parent`）。

`hierarchyLevel == -1` 的子任務是可執行的，要留著。

#### 判準四：解鎖效益只算未完成的下游

一張票 `blocks` 的下游若已經完成，它其實沒擋住任何人。這種殘留連結在真實看板上很常見（實測 ACME-17 掛著 blocks ACME-22，而 ACME-22 早就完成了），全算進去會把效益虛報得離譜，排序就跟著失真。

#### 判準五：排序

先用硬門檻篩掉不可動的票——**所有**擋它的票都完成了才算可動。一張動不了的票再急也不能建議，那等於沒建議。

可動的票依序比較：

1. **收尾優先**：`statusCategory == indeterminate`（進行中、審核中）的票排最前。半成品的價值是 0，而審核中的票往往只差一則實作註解或一次驗收核對，收掉它比開新戰場划算得多。
2. **解鎖效益**：擋住的未完成下游數量，多者優先——讓看板整體流動起來。
3. **Jira 優先序**：Highest → Lowest。注意這欄常常整個專案都是同一值（實測 ACME 29 張票全是 Medium），那時它沒有區別力，排序自然落到下一個條件，不要因此硬湊出優先序差異。
4. **票號小者優先**：穩定的收尾條件。

### 5. 交叉比對 git，抓「其實早該推 done」的票

對每張落在「進行中 / 審核中」的票，查它有沒有實作 commit：

```bash
git log --all --format='%h %s' | grep -E "^[0-9a-f]+ [a-z]+(\(|.*\()ACME-10\)"
```

比對 commit **subject 的 scope**，不要用 `git log --grep=ACME-10`。後者會搜整個 message，於是 body 裡順帶提到票號的 commit 也算命中——實測 `--grep=ACME-17` 命中了一個 `feat(ACME-22)` 的 commit，只因為 body 提到它。這種誤判會讓你回報「這張票已經做完了」，而它其實一行都沒寫。

找到實作 commit 而票還在審核中 → 建議確認驗收後推 `done`。這是這套工作流最常見的落差：程式寫完、commit 進去了，票停在審核中沒人推。

這一條腳本抓不到（它看不到 git），所以要由你把它併進腳本輸出的「待修正」區再呈現給使用者，而不是分成兩份清單各講一半。

commit 沒進 `main` 不代表沒完成——功能分支上的工作照樣是完成的工作。判準是「有沒有這張票的實作 commit」，不是「有沒有 merge」。

## 輸出格式

在對話裡直接輸出，**不要存報告檔**。盤點是高頻動作，每次都寫一份 `.claude/report/` 會很快變成垃圾堆；使用者要留存會自己說。

用這個結構（沒有內容的區塊整段省略，不要留空標題）：

```
## Jira 盤點 — <projectKey> (<今天日期>)

### 建議下一張：<KEY> <summary>
- 可動 ✅ <無 blocker | blocker 全清>
- 優先序 <值>
- 解鎖效益 <解開 KEY, KEY | 無下游等待>
- <若在進行中/審核中：已在「審核中」，屬收尾工作>

次選：<KEY summary> ／ <KEY summary>

### 可動（blocker 全清）
- [狀態] KEY summary  解鎖 N  ←分支對到這張

### 卡住
- [狀態] KEY summary  ⛔ 等 KEY(狀態)

### 待修正（本 skill 不動票）
- ⚠️ KEY：<現象> → 建議<動作>
```

建議那張票時，把「為什麼是它」講完整——可動性、優先序、解鎖效益三條理由都要在。使用者要能不同意你的排序：如果他知道你是因為「解鎖 ACME-29」才推薦 ACME-10，他可以說「ACME-29 我不急」然後挑次選。只丟一個票號等於要他盲信。

## 待修正該抓哪些

| 現象 | 怎麼認 | 建議 |
| --- | --- | --- |
| 分支已動工，票沒推進 | 分支抽到的票號仍在 `new` 類別 | 推 `inProgress` |
| 可解未解 | blocker 全完成，票卻還在 Block 狀態欄 | 推 `todo` |
| 早該收尾 | 審核中／進行中，且有實作 commit | 確認驗收後推 `done` |
| 停滯 | 在進行中／審核中超過兩週沒 `updated` | 確認真實進度，別假設它還在動 |
| 多張票同時進行中 | 不只一張在 `indeterminate`，且分支只對到其中一張 | 確認其餘是否被遺忘 |

這些都只是**回報**。看起來再明顯也不要順手推——例如「審核中且有 commit」很像該推 done，但驗收條件核過了沒、實作註解寫了沒，只有使用者知道，而 `done` 在這套工作流裡代表「驗收完成」，不是「程式寫完」。

## 常見誤判

- **回報「沒有待辦事項」之前，先確認查詢真的有回傳票。** 這句話聽起來像好消息，所以最不會被質疑，也最該懷疑。0 張的常見原因是 assignee 條件、project key 打錯、或 `statusCategory` 拼錯，不是真的沒事做。
- **`PENDING` 之類的自訂狀態要照 `statusCategory` 歸類，不要自己解釋語意。** 站台把它歸在哪一類，就是哪一類。
- **不要因為某張票的 summary 看起來最重要就推薦它。** 排序判準是可動性與依賴結構，那是看板上的客觀事實；「看起來重要」是你的猜測，而使用者對優先序的了解永遠比你多。
