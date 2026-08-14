---
name: check-linear-status
description: "盤點當前專案的 Linear 未完成票，算出哪些真的可動（blocker 全清）、哪些卡住、卡在誰，並依「收尾優先 → 解鎖效益 → 優先序」建議下一張該做的票；順帶回報狀態不一致（分支已動工票沒推、票卡在進行中被遺忘、blocker 全清卻還停在 Blocked、In Review 但實作 commit 早就進去了）。這是唯讀盤點，絕不改任何票。Use this whenever the user asks what to work on next, wants a status sweep of the board, asks which tickets are unblocked or actionable, wonders whether the board reflects reality, or is picking up work after time away. Triggers: \"盤點 linear\", \"檢查 linear 狀態\", \"接下來做哪張\", \"下一張票\", \"現在該做什麼\", \"看板現況\", \"哪些票可以動\", \"哪些票卡住了\", \"我做到哪了\", \"linear 狀態對不對\", \"check linear status\", \"what should I work on next\", \"which tickets are unblocked\", \"what's the state of the board\", \"where did I leave off\". 使用者只說「下一步做什麼」而當前專案有 .claude/linear-workflow.json 時也該觸發。"
---

# check-linear-status

盤點 Linear 現況，回報「下一張該做哪張票」以及「看板哪裡跟現實脫節」。

這是 `linear-workflow-init` 那套工作流（見它的 `references/linear-workflow.md`）的**唯讀**延伸。那份工作流負責推票，這個 skill 只負責看清楚——**一張票都不要動**。理由不是保守：盤點是使用者用來做決策的動作，如果盤點本身會改看板，他就沒辦法先看現況再決定。發現不一致就列進「待修正」區，讓他自己決定推不推。

## 流程

### 1. 讀設定

讀專案根的 `.claude/linear-workflow.json`，取 `team`、`states`、`branchPattern`、`containerMode`。

沒有這個檔案就停下來，告訴使用者這個專案還沒接上 Linear 工作流，可以跑 `/linear-workflow-init`。硬猜 team 只會盤點到別人的看板。

### 2. 抽當前分支的票號

`git rev-parse --abbrev-ref HEAD`，用 `branchPattern` 抽票號，**抽到之後轉大寫**。

Linear 產生的分支名長這樣：`your-name/proj-1-get-familiar-with-linear`——票號那段是小寫的。忘了轉大寫的症狀是分支明明對得上卻標不到任何票，而且不會報錯。

抽不到很正常（`main`、或 `refactor/kmp-mvvm-architecture` 這種），不要因此停住——盤點不需要票號也能跑，票號只是用來標記「分支對到這張」和偵測不一致。

### 3. 抓未完成票

```
list_issues({
  team: "<team>",
  includeArchived: false,
  limit: 100,
  fields: ["id","title","status","statusType","priority","labels",
           "project","parentId","assignee","updatedAt","dueDate","url"]
})
```

三個參數都不能省：

- **`includeArchived: false` 一定要送。** 它的預設值是 `true`，不送會把封存的歷史票全部撈回來。症狀是完成數虛高、待辦清單混進三年前的東西——而「看起來事情很少」是最不會被質疑的假訊號。
- **`fields` 一定要指定，而且不要放 `description`。** 不指定會帶回描述（即使截斷仍很長），十幾張票就數萬字元，而描述對盤點毫無用處——要決定做哪張票，看標題和依賴就夠了，內文是動工之後才要讀的。
- **`limit` 給 100。** 回傳有 `hasNextPage` 與 `cursor`，票多時要翻頁翻完，別只看第一頁就下結論。

Linear 沒有 `statusCategory != Done` 這種查詢語法，所以**已完成的票會一起回來**，由腳本用 `statusType` 濾掉。不要為了少抓幾張票而分別對每個未完成狀態各查一次——那是 N 次呼叫換一件腳本一行就能做的事。

#### assignee 篩選要留退路

如果使用者的看板有在指派人，加上 `assignee: "me"` 能讓報告更聚焦。但**先確認這樣篩得到票**：很多個人 workspace 根本不指派 assignee，這時候加了條件會回傳 0 張，然後你會誤報「沒有待辦事項」——那是最糟的失敗，因為它看起來像好消息。

穩健做法：先用不含 assignee 的查詢，看回傳裡 `assignee` 是否普遍有值。若多數有值且屬於他人，才依 assignee 分組並聚焦本人的票，同時說明範圍。

### 4. 補關係資料（Linear 特有的一步）

**`list_issues` 完全不回傳阻塞關係**，`fields` 也沒有對應選項。可動性算不出來，除非逐張補查：

```
get_issue({ id: "<每張未完成票>", includeRelations: true })
```

這是 Linear 與 Jira 最大的成本差異：Jira 一次 JQL 就把所有 `issuelinks` 內嵌回來，Linear 是 N+1。所以：

- **只對未完成票查**，已完成的不查（它們不需要判定可動性，當 blocker 時的狀態從主清單就讀得到）。
- 未完成票超過 **25 張**時，先問使用者要不要縮範圍（限定某個 Project、某個 cycle、或只看 assignee 是自己的），不要默默打 60 次呼叫。
- 查不完或使用者喊停時，**沒查到關係的票標記為「關係未查」而不是「可動」**。腳本已經這樣實作。少建議一張票，好過建議一張其實動不了的。

### 5. 用腳本算盤點結果

把步驟 3 的清單與步驟 4 的關係合成一份 JSON 落到檔案（放 scratchpad，不要寫進專案），再跑：

```bash
python3 <skill 目錄>/scripts/inventory.py <json 檔> \
  --branch-tickets PROJ-16 \
  --block-state "<states.block.name>" \
  --container-mode "<containerMode>"
```

輸入形狀：

```json
{
  "issues": [ ...list_issues 回傳的元素原樣... ],
  "relations": {
    "PROJ-10": { "blocks": ["PROJ-11"], "blockedBy": [] },
    "PROJ-11": { "blockedBy": ["PROJ-10"] }
  }
}
```

`relations` 的值可以只放票號字串，腳本會回頭到主清單找它的狀態。主清單裡沒有的（例如那張 blocker 已完成、不在查詢範圍）會被當作「未解決」——所以**已完成的 blocker 最好連同狀態一起放進 relations 的物件形式**，否則它會被保守地當成還擋著。

下面五條判準是腳本已經實作的邏輯。列出來有兩個用途：手算時照著做；以及當結果看起來不對時，你能判斷是資料問題還是判準沒對上實際看板。

#### 判準一：完成一律看 `statusType`

不要比對狀態名稱。名稱會因 team 自訂而不同，但 `statusType` 只有 `backlog` / `unstarted` / `started` / `completed` / `canceled` / `duplicate` 六種，跨 team 穩定。

**「不再擋住任何人」= `completed` ∪ `canceled` ∪ `duplicate`。** 這一點與 Jira 不同：Jira 的取消票通常落在 `done` 類別裡，Linear 則把 `canceled` / `duplicate` 獨立出來。只認 `completed` 的話，一張被取消的 blocker 會永遠擋住下游，而看板上完全看不出原因。

**但 Project／父票收尾只認 `completed`。** 子票被取消不代表工作做完了。

#### 判準二：關係方向看鍵名

`get_issue({includeRelations: true})` 回傳裡：

| 欄位 | 意思 |
| --- | --- |
| `blockedBy` | 對方擋我 |
| `blocks` | 我擋對方 |

比 Jira 單純（Jira 的 `type.outward` 字串陷阱在這裡不存在），但**不要**把 `relations` 陣列裡的 `type` 欄位拿來反推方向——`related` 與 `duplicate` 型的關係也在同一個陣列裡，它們不構成阻塞。

#### 判準三：容器不是可執行任務

`containerMode` 是 `project` 時，Linear Project **不是 issue**，不會出現在票清單裡，天然不需要過濾。這是比 Jira Epic 乾淨的地方。

`containerMode` 是 `parent` 時，被別張票指為 `parentId` 的票是容器，不要建議使用者去「做」它。腳本會處理。

#### 判準四：解鎖效益只算未解決的下游

一張票 `blocks` 的下游若已經完成或被取消，它其實沒擋住任何人。這種殘留關係在真實看板上很常見，全算進去會把效益虛報得離譜，排序就跟著失真。

#### 判準五：排序

先用硬門檻篩掉不可動的票——**所有**擋它的票都解決了才算可動。一張動不了的票再急也不能建議，那等於沒建議。

可動的票依序比較：

1. **收尾優先**：`statusType == started`（In Progress、In Review）的票排最前。半成品的價值是 0，而 In Review 的票往往只差一則實作註解或一次驗收核對，收掉它比開新戰場划算得多。
2. **解鎖效益**：擋住的未解決下游數量，多者優先——讓看板整體流動起來。
3. **優先序**：Urgent → Low。**Linear 的 `0` 是「沒設優先序」不是「最急」**，排序時當最低。直接拿數字排會把所有沒分類過的票推到最前面。
4. **票號小者優先**：穩定的收尾條件。

### 6. 交叉比對 git，抓「其實早該推 Done」的票

對每張落在 In Progress / In Review 的票，查它有沒有實作 commit：

```bash
git log --all --format='%h %s' | grep -E "^[0-9a-f]+ [a-z]+(\(|.*\()PROJ-10\)"
```

比對 commit **subject 的 scope**，不要用 `git log --grep=PROJ-10`。後者會搜整個 message，於是 body 裡順帶提到票號的 commit 也算命中，這種誤判會讓你回報「這張票已經做完了」，而它其實一行都沒寫。

Linear 還有一條 Jira 沒有的線索：每張票自帶 `gitBranchName`。**分支存在不等於工作完成**，所以它只能當輔助訊號，判準仍然是有沒有實作 commit。

找到實作 commit 而票還在 In Review → 建議確認驗收後推 `done`。這是這套工作流最常見的落差：程式寫完、commit 進去了，票停在審核中沒人推。

這一條腳本抓不到（它看不到 git），所以要由你把它併進腳本輸出的「待修正」區再呈現給使用者，而不是分成兩份清單各講一半。

commit 沒進 `main` 不代表沒完成——功能分支上的工作照樣是完成的工作。

## 輸出格式

在對話裡直接輸出，**不要存報告檔**。盤點是高頻動作，每次都寫一份 `.claude/report/` 會很快變成垃圾堆；使用者要留存會自己說。

用這個結構（沒有內容的區塊整段省略，不要留空標題）：

```
## Linear 盤點 — <team> (<今天日期>)

### 建議下一張：<KEY> <title>
- 可動 ✅ <無 blocker | blocker 全清>
- 優先序 <值>
- 解鎖效益 <解開 KEY, KEY | 無下游等待>
- <若在 started 類狀態：已在「In Review」，屬收尾工作>

次選：<KEY title> ／ <KEY title>

### 可動（blocker 全清）
- [狀態] KEY title  解鎖 N  ←分支對到這張

### 卡住
- [狀態] KEY title  ⛔ 等 KEY(狀態)

### 關係未查（不列入可動判定）
- [狀態] KEY title

### 待修正（本 skill 不動票）
- ⚠️ KEY：<現象> → 建議<動作>
```

建議那張票時，把「為什麼是它」講完整——可動性、優先序、解鎖效益三條理由都要在。使用者要能不同意你的排序：如果他知道你是因為「解鎖 PROJ-29」才推薦 PROJ-10，他可以說「PROJ-29 我不急」然後挑次選。只丟一個票號等於要他盲信。

## 待修正該抓哪些

| 現象 | 怎麼認 | 建議 |
| --- | --- | --- |
| 分支已動工，票沒推進 | 分支抽到的票號仍在 `backlog` / `unstarted` | 推 `inProgress` |
| 可解未解 | blocker 全解決，票卻還在 `states.block.name` 那一欄 | 推 `todo` |
| 早該收尾 | In Review／In Progress，且有實作 commit | 確認驗收後推 `done` |
| 停滯 | 在 `started` 類狀態超過兩週沒 `updatedAt` | 確認真實進度，別假設它還在動 |
| 多張票同時進行中 | 不只一張在 `started`，且分支只對到其中一張 | 確認其餘是否被遺忘 |
| 設定檔的狀態欄失效 | `list_issue_statuses` 找不到設定檔記的某個 state id | 建議重跑 init 校正 |

這些都只是**回報**。看起來再明顯也不要順手推——例如「In Review 且有 commit」很像該推 Done，但驗收條件核過了沒、實作註解寫了沒，只有使用者知道，而 `done` 在這套工作流裡代表「驗收完成」，不是「程式寫完」。

## 常見誤判

- **回報「沒有待辦事項」之前，先確認查詢真的有回傳票。** 這句話聽起來像好消息，所以最不會被質疑，也最該懷疑。0 張的常見原因是 assignee 條件、team 名打錯、翻頁沒翻完，不是真的沒事做。
- **`includeArchived` 忘了關掉的症狀是「完成率異常漂亮」。** 看到完成票遠多於預期時，先檢查這個參數再相信數字。
- **自訂狀態欄要照 `statusType` 歸類，不要自己解釋語意。** team 把它設成哪一型，就是哪一型。
- **不要因為某張票的標題看起來最重要就推薦它。** 排序判準是可動性與依賴結構，那是看板上的客觀事實；「看起來重要」是你的猜測，而使用者對優先序的了解永遠比你多。
