---
name: herdr-codex-wave
description: "Claude 指揮、Codex 在 Herdr pane 裡開發：每張 Linear 票一個 workspace + git worktree + 一個 Yolo Mode 的 Codex CLI pane，Claude 只做盤點派工、審碼把關、rebase + fast-forward 整合、以及全部的 Linear 狀態與註解。Codex 讀得到 Linear MCP，所以由它自己讀票；pane 是可見、可 attach、可中斷的，狀態靠 herdr agent wait 而非輪詢畫面。完工時 pane 會自動起本地 dev server、把測試頁開在使用者面前，並附一份 STE100 寫法的人工驗收清單。Use this whenever the user wants Codex doing the implementation while Claude orchestrates and they want to watch or interrupt the panes, mentions dispatching tickets to Codex through Herdr, wants several tickets worked in parallel with visible terminals, or asks to resume a wave of Codex panes. Triggers: \"用 herdr 派給 codex\", \"herdr 開 codex\", \"codex yolo mode 跑票\", \"讓 codex 在 pane 裡做\", \"開幾個 codex pane 同時做\", \"這幾張票丟 codex 平行做\", \"claude 指揮 codex 用 herdr\", \"分波派給 codex\", \"開下一波 codex\", \"dispatch these tickets to codex via herdr\", \"spin up codex panes for these issues\", \"have codex implement these in parallel panes\". 需要 HERDR_ENV=1 與 codex CLI。想要背景 job 而非可見 pane 就用 codex-wave；想用 Claude subagent 而非 Codex 就用 parallel-wave。"
---

# Herdr Codex Wave —— Claude 指揮、Codex 在 pane 裡開發

一波 = 一批互相獨立的票，各自在專屬 worktree 裡由一個 Codex pane 做完，全部回收整合完才考慮下一波。

**你不寫業務程式碼。** 你做四件 Codex 做不好的事：判斷哪些票能同時跑、把專案的隱性知識寫進派工指令、逐一審碼把關、序列整合進 base 分支並維護看板。

## 選這個還是選別的

| 情境 | 用哪個 |
| --- | --- |
| 要看得見、能 attach 進去、能中途插話 | **本 skill** |
| 只要結果，不需要看過程 | `codex-wave`（codex-companion 背景 job） |
| 實作者要用 Claude subagent 而非 Codex | `parallel-wave` |
| 要無人監督地清空整個看板 | `parallel-loop` / `linear-goal-loop` |

**盤點、審碼、整合的原則與 `parallel-wave` 一致，本檔不重複**——需要時讀同 plugin 的 `parallel-wave` skill 的第 1、2、4 步。本檔專注在 Herdr + Codex 特有的部分，以及實戰換來的那幾個坑。

票券工作流的行為（狀態 id、推票時機、註解規範、下游解鎖）一律遵守專案的 `.claude/linear-workflow.md`，**本 skill 不覆寫它**。

---

## 0. 一次性環境檢查

```bash
echo "$HERDR_ENV"                    # 必須是 1，否則整個 skill 不適用
codex --version
herdr integration status | grep -A1 codex
```

**`herdr integration install codex` 沒跑過的話，先跑。** 它寫入 `~/.codex/herdr-agent-state.sh`，讓 Herdr 認得 Codex pane 的 `working` / `idle` 轉換。沒裝的症狀是 `agent_status` 永遠停在 `unknown`，你只能輪詢 `herdr agent read` 讀畫面尾端猜完工——而 Codex 思考久一點就會被誤判成做完了。裝了之後 `herdr agent wait` 才可靠。

**確認 Codex 有哪些 MCP**：讀 `~/.codex/config.toml` 的 `[mcp_servers]`。若有 linear，就讓 pane 自己 `get_issue` 讀票，不要把票券描述複製進指令（省你的 context，而且票是唯一權威）。若沒有，退回 `codex-wave` 的做法：由你把規格摘要寫進指令，並由你重建實作紀錄。

---

## 1. 盤點與波次組成

依 `parallel-wave` 第 1 步做兩層判斷（依賴關係硬條件、共用檔衝突軟條件），然後**用 AskUserQuestion 一次問完波次範圍與其他待決事項**，附推薦選項。

Herdr 版要多想一件事：**pane 是可見的，所以波次大小的上限是「使用者還看得過來幾個」**，不只是機器負載。三到四個是實務上的舒適上限。

---

## 2. 開工前置：五件事，第四件最容易漏

**1. 確認 base 分支狀態。** `git status --short`。有未預期改動就問使用者要保留、自己處理、還是由你 stash。**保留是常見選擇，那就在整合時做 stash dance**（見第 5 步）。

**2. 跑一次基準線驗證，當對照組。** 這一步省的時間最多，而且它的價值不只是暖快取：

> **設定檔宣稱的閘門狀態經常與現實脫節。** 實測過的案例：某專案的設定檔寫「13 支驗證腳本全部通過、全部免 server」，實際在乾淨的 base 分支上有 4 支是紅的——2 支的輸入檔已經從 repo 消失、2 支需要 dev server 在跑。若照設定檔把全部閘門掛上，**每個 pane 都會撞到不是自己造成的紅燈，白燒一整輪去追不存在的 bug。**

所以：在主 repo 跑一次完整閘門，記下哪些本來就紅、真因是什麼。**派工指令裡只列當下實際會綠的那幾條**，並明講排除了哪幾條、理由是什麼、不要去修。

**把這件事寫進記憶**——它是專案級事實，下次不必再測一遍。

**3. 建 worktree。** 分支名照專案慣例（多數專案的 `parallel-loop.json` / 慣例是 `feat/{TICKET}`），worktree 目錄名用簡短票號。

**4. 補齊所有未進版控的檔案。** worktree 只帶 tracked 檔案，`.gitignore` 的一律不繼承。清單通常在專案設定的 `worktreeSeedFiles` / `untrackedSetupFiles`，但**別只信那份清單**：

```bash
git status --short --ignored=no   # 看有哪些 ?? 檔是 agent 需要的
```

**最陰險的一項是 agent 指令檔本身。** 若 `AGENTS.md`（Codex 讀的）或 `CLAUDE.md` 還沒 commit 進版控，worktree 裡就沒有它們——Codex 會在**完全沒有專案指令**的情況下工作，包括那些「改任何 symbol 前先跑影響分析」之類的硬規則。實戰踩過。

```bash
for f in .dev.vars fixtures node_modules AGENTS.md CLAUDE.md CLAUDE.local.md; do
  [ -e "$MAIN/$f" ] && cp -Rc "$MAIN/$f" "$WT/$f" 2>/dev/null || cp -R "$MAIN/$f" "$WT/$f"
done
```

`node_modules` 用 `cp -Rc`（APFS clonefile）幾乎瞬間完成，比 `npm ci` 快非常多。複製完印一份確認表，並實跑一次 `npx tsc --noEmit` 之類的輕量指令確認工具鏈可用——比讓 pane 撞牆再回報便宜。

設定檔清單列了已不存在的檔案時，**回報使用者並提議修正設定**，不要默默跳過。

**5. 決定人工驗收要怎麼開頁，並分配 port。** 讀專案 `.claude/linear-workflow.json` 的 `manualVerification` 區塊（`devCommand`、`baseUrl`、`portBase`、`preflight`、`loginHint`）。沒有那個區塊就從 `package.json` / `Makefile` 推斷，**併進第 1 步那次 AskUserQuestion 一起問**，收工時提議回寫設定檔。

**port 由你分配，不能讓 pane 自己挑**：`portBase + 波內序號`（第一張 5173、第二張 5174⋯）。兩個 pane 撞同一個 port 時，使用者看到的畫面會屬於錯的那張票——而那個畫面「看起來是對的」，是最難察覺的一種錯。分配結果寫進派工指令。

Yolo Mode 的 Codex 沒有權限關卡，`nohup` / `open` / `curl` 直接就能跑，不必像 Claude 版那樣預先補白名單。

專案沒有可開的頁面（純 CLI／library／worker）就整段略過，並在派工指令裡明講「本票無畫面可驗」。細節見 `herdr-claude-wave/references/manual-verification.md`（兩支 skill 共用那一份）。

**接著把整批票推到 `states.inProgress`**，動第一個編輯之前就推。

---

## 3. 派工

一票一個 workspace，cwd 指向它的 worktree：

```bash
herdr workspace create --cwd "<worktree 絕對路徑>" --label "PROJ-111" --no-focus
# 從回傳 JSON 取 result.root_pane.pane_id
herdr agent start proj-111 --kind codex --pane <pane_id> -- --dangerously-bypass-approvals-and-sandbox
herdr agent prompt proj-111 "$(cat <prompt 檔>)"
```

**所有 pane 在同一則訊息裡起完並派工**，才是真的平行。

`--dangerously-bypass-approvals-and-sandbox` 就是 Yolo Mode：跳過所有確認、不沙箱。**這需要使用者明確要求**——它讓 Codex 能不受阻礙地跑建置與改檔，代價是沒有任何確認關卡。使用者沒提就先問。

指令模板見 `references/pane-prompt.md`。**每一段都是實戰換來的，特別是這幾條不要省**：

- **讓 pane 自己讀票，並且明講「連我寫的解鎖註解一起讀」**（`list_comments`）。解鎖註解裡有「現在可以直接用什麼」與「該避開的坑」——這是分波推進的複利所在，上一波的複查發現直接變成下一波的起跑優勢。
- **主 repo 唯讀**（規格文件常在 gitignore 的目錄裡）。
- **明講同波還有誰在跑、碰哪些檔、哪些檔獨佔**。pane 知道有鄰居才會自我克制。
- **共用檔的衝突紀律**：只准往檔尾追加、用註解標出區塊、只改最小必要行數、不准順手重排。
- **建置輸出重導到 log 再 `tail`**，不要讓數千行進 pane 的 context。
- **指路到既有的同類實作**。Codex 沒讀過你的架構決策；「有一個 X 已經用完全相同的模式做過，先把這三個檔讀完再動手，然後鏡像它」比任何抽象規範都有效。
- **不准 push、不准 merge、不准動 base 分支、不准改別的票、不准動 Linear 狀態或 labels**——整合與看板是你的職責。**但要求 pane 自己寫這張票的實作紀錄註解**（含思考軌跡三段：考慮過但沒選、撞到的牆、沒驗到的）——worktree 一刪 `RESULT.md` 就沒了，你的轉述必然流失第一人稱的判斷過程。
- **誠實度要求要具體到痛點**。不要只說「請誠實」，要說「本專案 E2E 已關閉、瀏覽器層零自動守門，`build` 全綠完全不代表畫面對，你沒在瀏覽器裡看過就必須標未驗證」。
- **要求把可純函式驗證的部分補進既有 `verify:*` 腳本**。自動守門薄的專案，這比 RESULT.md 裡寫「應該沒問題」有價值得多。
- **要求 pane 完工前起 dev server、開頁、並寫一份人工驗收清單**（`## 人工驗收清單` 段落，STE100 寫法：一句一個動作、祈使句、預期結果必須可觀察、禁用「正常」這類模糊詞）。指令裡要給它：分配到的 port、`devCommand`、`preflight`、`loginHint`、第一個該開的路徑。模板與規則見 `herdr-claude-wave/references/manual-verification.md`。**這是這個工作流唯一的瀏覽器層驗證來源**——不寫的話，這張票的畫面就是零驗證進 base。
- **要求寫 `RESULT.md` 到 worktree 根目錄且不要 commit**，內含 commit hash、改哪些檔與為什麼、**驗收條件逐條對照（通過／部分通過／未驗證 + 實際證據）**、與票券不同的決策、處理掉的邊界情境、未驗證清單。

---

## 4. 等待：用 Monitor 包 herdr agent wait

不要 `sleep` 輪詢，也不要反覆讀畫面：

```
Monitor({
  command: 'for a in proj-111 proj-112; do ( herdr agent wait $a --timeout 3000000 >/dev/null 2>&1 \
             && echo "[$a] 已回到 idle — 可回收" || echo "[$a] wait 逾時或出錯" ) & done; wait',
  description: 'Codex panes 完工通知',
  timeout_ms: 3600000, persistent: false,
})
```

`herdr agent wait` 不帶 `--until` 時會等 idle / done / blocked 任一。**先回報的先整合**，不要等全部——後面的 rebase 一下就好。

**`wait` 返回後，測試頁應該已經開在使用者面前了**（pane 完工前會起 dev server 並 `open`）。沒開就看 `manualVerification.logPath` 查 server 為什麼沒起來。**審碼的同時把 `RESULT.md` 的 `## 人工驗收清單` 原樣搬進對話**——不要摘要成「請驗一下訂單功能」，那等於把 pane 寫好的精確步驟丟掉。一波多票就標明哪個 port 屬於哪張票：

```
PROJ-111 訂單列表 → http://localhost:5173/orders （4 項，約 3 分鐘）
PROJ-112 設定頁   → http://localhost:5174/settings（3 項，約 2 分鐘）
```

使用者回報不符項就 `herdr agent prompt` 回原 pane 補正，**帶上他的原話**——你的轉譯會把症狀的關鍵細節磨掉。**不要為了等驗收而卡住審碼與 rebase**，兩件事平行做；只有 `git worktree remove` 必須等驗收回覆。

pane 若真的卡住（`herdr agent read` 看得出在原地打轉），`herdr agent prompt` 補一句更緊的指令即可，同一個 pane 保留完整脈絡。**同一張票補正兩次仍不達標就停下來問使用者**——多半是票券規格本身有歧義，那是人要決定的事。

---

## 5. 回收：審碼，然後整合

### 先看 worktree 實況，不要只讀 RESULT.md

```bash
git -C "$WT" log --oneline <base>..HEAD    # 有沒有 commit
git -C "$WT" status --short                 # 工作區乾淨嗎、有沒有誤 commit
git -C "$WT" diff --stat <base>...HEAD      # 改了什麼、範圍有沒有超出票券
```

**同時確認 `RESULT.md` 裡有 `## 人工驗收清單`**（本票有畫面可驗的話）。沒有就是沒做完，`herdr agent prompt` 要它補——**在關掉 workspace 之前**。

### 審碼：自我回報是線索，不是證據

`parallel-wave` 第 4 步那四項照做（看 diff 本身、看 log 實際結尾、確認測試真的執行過並數斷言數、確認 gitignored 檔沒被 commit），本 skill 再加三項：

**5. 診斷「超出票面範圍」是必要還是順手。** Codex 常常改到票面沒寫的檔。判準不是「有沒有超出」而是「有沒有正當理由」。實測過的兩個例子都成立：把 `BrowserRouter` 換成 data router，因為要用的 hook 只在 data router 下有效；把共用元件拆出 lazy chunk，因為驗收條件明文要求某頁不載入該套件。**驗證方式是逐行比對**——若拆檔前後只差一行函式名，那就是忠實搬移而非偷渡重構，風險警示可以解除。

**6. 找出「落在被排除閘門盲區」的改動。** 這是本工作流最大的結構性風險。你在第 2 步排除了幾條閘門，若 pane 的改動剛好落在那些閘門本該覆蓋的範圍（例如改了 worker 而 `verify:api` 被排除），那段程式碼就是**零執行期覆蓋**。此時要親自讀碼推資料流、對 schema、檢查 SQL 是否參數化，並在整合註解裡**明講「這段沒有任何一次真實執行」**。

**7. 地基票要額外讀碼並補測 pane 標「未驗證」的項目。** 型別定義、共用演算法、核心 helper 錯了會污染所有下游，而錯誤形式往往是「編譯過、測試過、語意錯」。實測過的案例：pane 誠實標了「66 店規模未驗證」（它只測 30 店），但下游要把那支函式掛在 UI 按鈕上——補測只花幾分鐘，結果 15 ms，疑慮解除並寫進下游的解鎖註解。**pane 標未驗證而下游會直接踩到的項目，就是你該補的那一項。**

### 整合：rebase + fast-forward，一張一張來

```bash
git -C "$WT" rebase <base>
git -C "$MAIN" merge --ff-only <branch>
```

**合併順序照第 1 步的風險分析**：低風險先進；共用檔的票**新增內容少的先合、多的 rebase 上去**，衝突面較小。

**base 分支有未提交改動時的 stash dance。** `--ff-only` 不允許被合併動到的檔案帶有本地改動：

```bash
git stash push -m "<描述>" -- <只有那個衝突檔>
git merge --ff-only <branch>
git stash pop
```

只 stash 真正衝突的那個檔，不要整個工作區。pop 之後**實查使用者的改動是否完整還原**並在註解裡交代。

**共用檔的 add/add 衝突有個固定形狀**：兩張票都在檔尾同一個插入點追加，git 會把兩者共用的結尾行（CSS 的 `}`、陣列的 `]`）合在一起而報衝突。**解法是兩塊都保留、各自補回自己的結尾行**，順序照合併順序。解完後 `grep -c "^<<<<<<<\|^=======$\|^>>>>>>>"` 確認無殘留，並**在 worktree 內先跑過建置閘門才合進 base**。

**每次合併後在 base 分支上重跑驗證，並比對斷言數。** 各自 worktree 綠不代表合起來綠。斷言數變少就是回歸訊號，要停下來查。

### 收尾

寫**整合註解**，標題 `## 整合與複查（主控）`。**pane 那則回答「當時是怎麼想的」，你這則回答「現在能不能信」——不要把它的實作紀錄重講一遍。** 寫法照 `.claude/linear-workflow.md` 的「註解怎麼寫」，正文照結論在前的順序：

1. **這張票現在是什麼狀態**：已進哪個分支、能不能信。一句話
2. **我對 pane 判斷的修正**：哪裡它想錯了、我改了什麼、我**補測**了什麼
3. **複查抓到的真問題**：每條一行（抓到什麼 → 怎麼處置）
4. **人工驗收結果**：幾項、使用者實驗幾項、哪幾項不符與怎麼處置、哪幾項他沒驗。使用者選擇不驗就寫「清單已產出、使用者選擇不驗、全 N 項均為未驗證」
5. **仍未驗證**：**原樣保留 pane 標的未驗證項與使用者沒驗到的清單項**，不要因為合併成功就把「未實機驗證」升級成通過
6. 下游影響（有才寫）

**這些進 `<details>` 摺疊區，不要放正文**——它們是證據不是結論：rebase 前後兩個 commit hash（rebase 會改寫 hash，只寫一個日後對不上；沒改寫時明講「前後同一個 hash，因為期間 base 沒有前進」）、逐條閘門結果與**實際斷言數**、**被排除的閘門與理由**、盲區評估、**人工驗收清單全文**（正文只留結果，步驟是證據）、複查發現的逐條推導。

**你派工時犯的錯不要寫進票**——那是流程問題，進對話或 log。

然後推 `states.done`，照 `.claude/linear-workflow.md` 檢查下游解鎖：取 `blocks` 的下游，逐一實查它們**自己的**所有 `blockedBy`，全清才推 `states.todo`。

**解鎖註解是這個工作流的複利引擎，值得寫厚一點。** 下一波的 pane 會被指示去讀它。要寫：現在可以直接用什麼（具體檔案路徑與匯出名稱、可以照抄的既有實作）、**該避開的坑**（你審碼時發現的邊界、效能特性、會誤觸的機制）、以及**上游有哪些未驗證項目**（讓下一張票知道遇到問題時該不該歸因給自己）。

**收 worktree 的時機被人工驗收綁住了：合併可以立刻做，`git worktree remove` 要等使用者回報驗收結果。** worktree 一刪，dev server 的 cwd 就消失、使用者手上的頁面當場壞掉。順序是：使用者回覆 → `kill $(cat <worktree>/.dev-server.pid)` → `git worktree remove` → `herdr workspace close <id>`。

使用者一直沒回就把 worktree 留著，並在收工回報講明「PROJ-111 的 worktree 與 :5174 還開著，驗完說一聲我來收」。**其餘不需要開頁的票（純 CLI／library）維持原則：合併完立刻收，別堆積。**

---

## 6. 收工回報

**例行成功用一兩行帶過**：commit hash、閘門結果、看板狀態。詳細的複查發現寫進 Linear 整合註解——那是給未來的人看的紀錄，不是對話內容，不要在對話裡重述一遍。

**只有這幾種情況才展開**：真的失敗、發現會影響決策的風險、需要使用者決定的事（要不要 push、要不要刪已合併分支、要不要開下一波）。**已經提醒過且使用者已做決定的事不要再提**——同一段「累積了多少驗證債」講第三次就只是雜訊。

需要使用者親自做的事要單獨點出來（外部主控台設定、憑證、`wrangler secret put` 這類營運動作），因為程式碼這側做不到。

**人工驗收清單也屬於這一類，而且它是每一波都會有的那一項。** 收工回報要講清楚：測試頁開在哪些網址、每張票幾項、還有哪些 worktree 因為等驗收而留著。

發現值得記住的專案特定坑就寫進記憶，下次不用再撞一遍。

---

## 反模式

| 別做 | 為什麼 |
| --- | --- |
| 沒跑 `herdr integration install codex` 就開始 | `agent_status` 停在 `unknown`，只能靠讀畫面猜完工，Codex 思考久一點就被誤判成做完 |
| 照設定檔把全部閘門掛上 | 設定檔常與現實脫節；每個 pane 都會撞到不是自己造成的紅燈 |
| 忘記複製 `AGENTS.md` / `CLAUDE.md` 到 worktree | 它們可能還沒進版控，Codex 會在零專案指令的狀態下工作 |
| 把票券描述複製進派工指令 | 燒你的 context，而且票是唯一權威；Codex 有 Linear MCP 就讓它自己讀 |
| 沒叫 pane 讀上一波的解鎖註解 | 白白丟掉分波推進最大的複利 |
| 用 `sleep` 或反覆讀畫面判斷完工 | 有 `herdr agent wait` + `Monitor` 就不必猜 |
| 分開送 pane 的啟動與派工訊息 | 會變成串行，白費整個 skill 的意義 |
| 相信「測試通過」而不數斷言數 | 測試沒被執行也會 exit 0 |
| 讓 pane 自己 merge 或動 Linear | 併發寫 base 分支會互相覆蓋；看板正確性是你的責任 |
| 把「編譯過」寫成驗收通過 | 視覺與實機行為完全沒驗到，日後回查會被誤導 |
| 忽略落在被排除閘門盲區的改動 | 那段程式碼零執行期覆蓋，而綠燈會讓人以為它被驗過了 |
| 收工回報把整合細節在對話裡重述一遍 | 那些該寫進 Linear 註解；對話裡只留結論與待決事項 |
| **pane 做完就結束，不開測試頁也不給驗收清單** | 瀏覽器層零自動守門，這張票的畫面等於零驗證進 base，而綠燈會讓人以為驗過了 |
| 讓 pane 自己挑 port | 兩個 pane 撞同一個 port，使用者看到的畫面會屬於錯的那張票，而那個畫面「看起來是對的」 |
| 驗收還沒回覆就 `git worktree remove` | server 的 cwd 消失，使用者手上的頁面當場壞掉 |
| 把 pane 寫的清單摘要成「請驗一下 X 功能」 | 精確步驟是清單的全部價值，摘要掉就等於沒寫 |
| 清單裡寫「確認顯示正常」 | 「正常」是模糊詞；使用者不知道要看哪裡，回報會變成「怪怪的」，pane 補正只能猜 |
| 使用者跳過驗收就把該項寫成通過 | 紀錄失真比沒驗更危險，未來回查會被誤導 |

---

## 參考檔

- `references/pane-prompt.md` —— Codex pane 派工指令模板，逐段說明為什麼要有那一段
- `references/herdr-runtime.md` —— 已實查的 `herdr` CLI 契約與回傳形狀
- `herdr-claude-wave/references/manual-verification.md`（同 plugin）—— 完工開頁、port 分配與 server 生命週期、STE100 寫法的人工驗收清單模板；兩支 skill 共用，差異列在該檔文末
- `parallel-wave`（同 plugin）—— 共用的盤點、前置、整合原則
