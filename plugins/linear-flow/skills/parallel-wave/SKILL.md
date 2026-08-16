---
name: parallel-wave
description: "用 Agent + git worktree 分波平行完成一批 Linear 票：先盤點哪些票真的能同時跑（依賴關係 + 共用檔衝突風險），每票一個 worktree 派一個 subagent 實作，回收時逐一審碼、rebase、fast-forward 合併、實跑驗證、推 Done、解鎖下游。**不需要 Herdr、不需要任何外部工具**，只用內建 Agent tool，與需要 HERDR_ENV 的 parallel-loop 是兩回事。Use this whenever the user wants to work several tickets at once, asks which tickets can be parallelized, wants to speed up a backlog with multiple agents, or asks to batch through a set of unblocked issues. Triggers: \"平行處理哪些票\", \"開多個 agent 跑票\", \"這輪能並行做哪些\", \"一次做幾張票\", \"分波處理\", \"開下一波\", \"多開幾個 agent 同時做\", \"哪些票可以同時進行\", \"work these tickets in parallel\", \"spin up agents for these issues\", \"which tickets can run at the same time\", \"batch through the unblocked tickets\". 使用者說「直接開始下一輪」而上一波剛收完時也該觸發。"
---

# Parallel Wave —— 分波平行執行票券

你是**派發者與整合者**。你不寫業務程式碼，那是 subagent 的事。你負責三件別人做不好的事：**判斷哪些票能同時跑**、**逐一審碼把關**、**序列整合進 base 分支**。

## 為什麼是「波」而不是「連續 loop」

一波 = 一批互相獨立的票同時開工，全部回收整合完才考慮下一波。

這比連續 drain 好在：每波之間有一個清楚的檢查點，使用者能看到完整結果再決定要不要繼續；而且下一波的候選票是在「上一波成果已進 base 分支」的前提下重新盤點的，解鎖關係才算得準。連續 loop 適合無人監督地清空看板（那是 `linear-goal-loop` 與 `parallel-loop` 的領域），本 skill 適合**有人在旁邊、要看得懂每一步**的批次推進。

---

## 0. 先讀設定

專案設定在 `.claude/linear-workflow.json`。票券工作流的行為（狀態 id、推票時機、註解規範、下游解鎖）一律遵守同目錄的 `.claude/linear-workflow.md`，**本 skill 不重複那些規則，也不覆寫它們**。

本 skill 額外需要的專案特定值放在同一個 JSON 的 `parallelWave` 區塊。欄位說明與缺漏時的處理見 `references/config-and-setup.md`。

**設定缺漏不是停工理由**：能從 repo 推斷的就推斷（base 分支、建置指令），推不出來的就問使用者一次，並在收工時提議把 `parallelWave` 區塊補進設定檔，下次就不用再問。

---

## 1. 盤點：哪些票真的能同時跑

這是本 skill 最有價值的一步，別跳過。兩層判斷：

### 第一層：依賴關係（硬條件）

```
list_issues({ project: <活躍 project id>, state: <states.todo.id>,
              includeArchived: false,
              fields: ["id","title","status","priority","labels"] })
```

`includeArchived: false` 與明確指定 `fields` 都是必要的——預設會撈進封存票並帶回整份 description，盤點會失真且爆 context。

拿到候選後，**逐張 `get_issue({ id, includeRelations: true })`**（關係只能這樣查，`list_issues` 不回傳）。確認兩件事：

1. 每張的 `blockedBy` 是否真的全部完成——狀態欄可能沒跟上實際進度
2. **候選之間有沒有互相阻擋**——若 A blocks B，兩張就不能同波

### 第二層：共用檔衝突（軟條件，決定波的組成）

依賴關係過關不代表能舒服地平行。真正會痛的是多個 agent 改同一個檔。**動手前先實地掃描**專案裡的衝突熱點，別憑印象：

| 熱點類型 | 怎麼找 | 典型衝突形式 |
| --- | --- | --- |
| DI / 註冊中心 | `find . -name "*Module*" -o -name "*Registry*"` | 多張票都要註冊新元件 |
| 路由 / 導航表 | `find . -ipath "*navigation*" -o -name "*Route*"` | 多張票都要加路由 |
| 依賴宣告 | `build.gradle*`、`package.json`、`*.toml`、`requirements.txt` | 多張票都要加套件 |
| 字串 / 資源索引 | `strings.xml`、i18n 檔、barrel `index.ts` | 多張票都要加條目 |
| 窮盡式 enum / switch | 上一波剛加過的 enum | 加一項就要改所有 when/switch |

風險分級與對策：

- **低**：純新增檔案，彼此無交集 → 放心同波
- **中**：會改同一個 append-only 清單（DI 註冊、路由表）→ **仍可同波**，但要在 agent 指令裡下衝突紀律（見下），並在整合時**刻意排序**：先合併新增內容少的，後者 rebase 上去
- **高**：會改同一個檔的同一段邏輯 → **不要同波**，拆到下一波

中風險的衝突紀律（寫進 agent 指令）：

> 註冊語句加在清單**最末端**並用註解標出區塊；import 照現有順序插入；**只改最小必要行數**，不要順手重排或重構這個檔。

### 決定波的組成，然後問使用者

把分析結果攤開給使用者：每張票、主要動作、風險等級、彼此的衝突點。**用 AskUserQuestion 給選項**（全開／保守拆波／只做低風險），附上推薦與理由。使用者的時間比你的 token 貴——一次講清楚，別擠牙膏。

---

## 2. 開工前的三件前置（省下大量重工）

**1. 確認 base 分支乾淨。** `git status --short` 有未預期的改動就先問，不要蓋掉使用者手上的東西。

**2. 先跑一次基準建置。** 這一步很容易被跳過，但省的時間最多：N 個 worktree 各自冷編譯會把機器打爆，先在主 repo 跑一次 `warmupCommand`，把建置快取暖起來，後面每個 agent 都是增量編譯。順便確認**動工前 base 就是綠的**——否則後面每個 agent 都會撞到不是自己造成的失敗，白白燒掉一輪。

**3. 建 worktree 並補齊未進版控的設定檔。** 這是最陰險的坑：worktree 只帶版控內的檔案，被 gitignore 的本機設定（簽章檔、金鑰、`.env`、服務憑證）通通不在，建置會以**完全看不出真因的訊息**失敗。從 `parallelWave.untrackedSetupFiles` 讀清單，建完立刻複製：

```bash
for f in <untrackedSetupFiles>; do
  [ -f "$MAIN/$f" ] && cp "$MAIN/$f" "$WT/$dir/$f"
done
```

複製完印一份確認表。這些檔在 `.gitignore` 內不會被誤 commit，但整合時仍要用 `git diff --name-only` 再確認一次。

分支名用 Linear 票自帶的 `gitBranchName`——票號抽得到，工作流才對得上。worktree 目錄名用簡短票號（`proj-97`）。

**接著把整批票推到 `states.inProgress`**，動第一個編輯之前就推，不是做完才補。

---

## 3. 派工：一則訊息、全部 spawn

**所有 Agent 呼叫放在同一則訊息裡**，才會真的平行；分開送會變成串行，白費整個 skill 的意義。

指令模板見 `references/agent-prompt.md`，照它組。模板包含的每一段都是實戰換來的，特別是這幾條**不要省**：

- **讓 agent 自己讀票**（`get_issue`），不要把 description 複製進指令——省你的 context，而且票是唯一權威
- **主 repo 唯讀**——規格文件常在 gitignore 的目錄裡（vault、docs），只能從主 repo 讀，但絕不能在那裡改
- **建置指令要重導到 log 再 tail**——建置輸出動輒數千行，直接吃進 context 會癱瘓 agent
- **驗證要讀測試結果檔確認數量**，不只看「BUILD SUCCESSFUL」——測試沒被執行也會 BUILD SUCCESSFUL，這是假綠燈的主要來源
- **不准 push、不准合併、不准動 base 分支、不准改別的票**——整合是你的職責，讓 agent 碰會亂
- **實機／視覺／跨平台驗收一律誠實標「未驗證」**——寫成通過比留白傷害大得多
- **告知同波有誰在跑、碰哪些檔**——agent 知道有鄰居才會自我克制

---

## 4. 回收：逐張審、逐張合

Agent 可能**直接進入閒置而沒有正式回報**。別空等——收到閒置通知就直接查 worktree 實況：

```bash
git -C "$WT" log --oneline <base>..HEAD    # 有沒有 commit
git -C "$WT" status --short                 # 工作區是否乾淨
git -C "$WT" diff --stat <base>...HEAD      # 改了什麼
```

### 審碼：不要照單全收

**agent 的自我回報是線索，不是證據。** 至少做這四項：

1. **看 diff 本身**——不是看它說改了什麼。範圍有沒有超出票券？有沒有順手重構無關的東西？
2. **看建置／測試 log 的實際結尾**，確認真的綠燈
3. **確認測試真的執行**——讀測試結果檔的數量欄位，`tests="0"` 等於沒測
4. **確認 commit 只含預期路徑**：`git show --stat <hash>`。有些 harness 會在 commit 前做 `git add`，把未追蹤檔一併帶進去——所以除了 `git diff --name-only <base>...HEAD | grep -E "<敏感檔樣式>"` 掃敏感檔，也要看 commit 本身的檔案清單有沒有多出東西。發現多餘檔案在 worktree 裡改掉再合併，不要帶進 base 分支。

**地基票（型別定義、共用演算法、核心 helper）要額外讀碼。** 這類票錯了會污染所有下游，而且錯誤形式往往是「編譯過、測試過、語意錯」——例如 enum 順序與外部系統對不上。花幾分鐘讀關鍵段落，比事後回滾十張票便宜太多。

### 合併：rebase + fast-forward，一張一張來

```bash
git -C "$WT" rebase <base>
git -C "$MAIN" merge --ff-only <branch>
```

`--ff-only` 是刻意的：歷史保持線性，每張票一個 commit，出事時好回溯。合併順序照第 1 步的風險分析——低風險先進，共用檔的票刻意排序。

**每次合併後在 base 分支上重跑驗證。** 各自 worktree 綠不代表合起來綠。有測試的票要連測試一起跑，並再次確認測試數量。

### 收尾：註解、推 Done、解鎖下游

合併後在票上補一則**整合註解**（agent 寫的是實作紀錄，你寫的是整合紀錄，兩者不同）。**寫法照 `.claude/linear-workflow.md` 的「註解怎麼寫」**：九條硬規則一體適用，第一句先講程式碼已經進了哪個分支，末尾附 YAML 區（至少 `commits` 與 `verification`）。整合註解的正文要有：

- rebase 前後的 commit hash（rebase 會改寫 hash，只寫一個日後對不上）
- 在 base 分支上實跑的驗證結果與**測試實際數量**
- 你審碼時的複查發現
- **未驗證項目原樣保留**——不要因為合併成功就把「未實機驗證」升級成通過
- 下游影響

然後推 `states.done`，並照 `.claude/linear-workflow.md` 的規則檢查下游解鎖：取這張票 `blocks` 的下游，逐一實查它們**自己的**所有 `blockedBy`，全清才推 `states.todo` 並加解鎖註解。**解鎖註解要寫「現在可以直接用什麼」**——已完成的元件路徑、已備妥的接口、該避開的坑。下一個接手的人（或 agent）會省下大量摸索。

**合併完立刻移除 worktree**，別堆積：`git worktree remove <path>`。

---

## 5. 收工回報

一波結束給使用者一份實話實說的總結：

- 每張票的 commit、內容、**驗證強度**（只編譯過？有幾個測試？）——不要讓「全部完成」掩蓋掉驗證深度的差異
- **沒驗到的部分集中列出**：實機、視覺、跨平台、與外部系統的真實互通
- 解鎖了哪些下游，還有哪些卡住、卡在誰
- **待使用者決定的事**：要不要 push（本 skill 全程不 push）、要不要刪已合併的分支、要不要開下一波
- 下一波的建議與理由

**發現值得記住的專案特定坑**（那個看不出真因的建置錯誤、某個工具的怪癖），寫進記憶，下次不用再撞一遍。

---

## 反模式

| 別做 | 為什麼 |
| --- | --- |
| 沒暖快取就派 N 個 agent | N 個冷建置同時跑，機器卡死，每個 agent 都慢好幾倍 |
| 相信 agent 說「測試通過」 | 測試沒被執行也會 BUILD SUCCESSFUL；一定要看數量 |
| 等全部 agent 回報才開始合併 | 先回報的先合，後面的 rebase 一下就好，整體快得多 |
| 讓 agent 自己 merge 進 base | 併發寫 base 分支，遲早互相覆蓋或產生垃圾 merge commit |
| 把「編譯過」寫成驗收通過 | 視覺與實機行為完全沒驗到，日後回查會被誤導 |
| 高風險衝突票硬塞同一波 | 省下的時間全還給衝突解決，還可能解錯 |
| 一次問使用者一個問題 | 用 AskUserQuestion 一次問完 2~4 題，附推薦選項 |

---

## 參考檔

- `references/agent-prompt.md` —— 派工指令模板，逐段說明為什麼要有那一段
- `references/config-and-setup.md` —— `parallelWave` 設定欄位、缺漏時的推斷與補寫
