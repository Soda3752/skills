---
name: herdr-claude-wave
description: "Claude 指揮、Claude Code 在 Herdr pane 裡開發：每張 Linear 票一個 workspace + git worktree + 一個 Claude Code pane（`--permission-mode auto`），主控 Claude 只做盤點派工、審碼把關、rebase + fast-forward 整合、以及全部的 Linear 狀態與註解。pane 是可見、可 attach、可中斷的，狀態靠 herdr agent wait 而非輪詢畫面。Use this whenever the user wants Claude Code panes doing the implementation while another Claude orchestrates and they want to watch or interrupt the panes, mentions dispatching tickets to Claude panes through Herdr, wants several tickets worked in parallel with visible terminals, or asks to resume a wave of Claude panes. Triggers: \"用 herdr 派給 claude\", \"herdr 開 claude pane\", \"claude 指揮 claude\", \"讓 claude code 在 pane 裡做\", \"開幾個 claude pane 同時做\", \"這幾張票丟 claude 平行做\", \"分波派給 claude\", \"開下一波 claude\", \"dispatch these tickets to claude panes via herdr\", \"spin up claude code panes for these issues\", \"have claude implement these in parallel panes\". 需要 HERDR_ENV=1。實作者要換成 Codex 就用 herdr-codex-wave；不要可見 pane、只要 Agent tool 就用 parallel-wave；要無人監督清空整個看板就用 parallel-loop。"
---

# Herdr Claude Wave —— Claude 指揮、Claude Code 在 pane 裡開發

一波 = 一批互相獨立的票，各自在專屬 worktree 裡由一個 Claude Code pane 做完，全部回收整合完才考慮下一波。

**你不寫業務程式碼。** 你做四件 pane 做不好的事：判斷哪些票能同時跑、把專案的隱性知識寫進派工指令、逐一審碼把關、序列整合進 base 分支並維護看板。

## 選這個還是選別的

| 情境 | 用哪個 |
| --- | --- |
| 要看得見、能 attach 進去、能中途插話，實作者是 Claude Code | **本 skill** |
| 實作者要換成 Codex（不同模型、天然的對抗性） | `herdr-codex-wave` |
| 不需要可見 pane，用內建 Agent tool 就好 | `parallel-wave` |
| 要無人監督地清空整個看板（自動補位、自動收工） | `parallel-loop` / `linear-goal-loop` |

**盤點、審碼、整合的原則與 `parallel-wave` 一致，本檔不重複**——需要時讀同 plugin 的 `parallel-wave` skill 的第 1、2、4 步。本檔專注在 Herdr + Claude Code pane 特有的部分。

**與 `herdr-codex-wave` 的差異集中在第 0、2、3、4、5 步**（integration 名稱、worktree 的 `.claude/` 空洞、`--add-dir`、`blocked` 處理、同模型審碼的對抗來源）。其餘骨架相同，那些是實戰換來的，照做。

票券工作流的行為（狀態 id、推票時機、註解規範、下游解鎖）一律遵守專案的 `.claude/linear-workflow.md`，**本 skill 不覆寫它**。

---

## 0. 一次性環境檢查

```bash
echo "$HERDR_ENV"                       # 必須是 1，否則整個 skill 不適用
claude --version
herdr integration status | grep claude
```

**`claude: not installed` 的話先跑 `herdr integration install claude`。** 它寫入 `~/.claude/hooks/herdr-agent-state.sh`，讓 Herdr 認得 Claude pane 的 `working` / `idle` / `blocked` 轉換。沒裝的症狀是 `agent_status` 永遠停在 `unknown`，你只能輪詢 `herdr agent read` 讀畫面尾端猜完工——而 Claude 思考久一點就會被誤判成做完了。裝了之後 `herdr agent wait` 才可靠。**它會改使用者的 `~/.claude/` 設定，先徵得同意。**

**確認 pane 能不能自己讀票**：Claude Code 的 MCP 來自 user scope（`~/.claude.json`）與**專案的 `.mcp.json`**。user scope 的 linear 在任何 cwd 都在，worktree 裡也有；只寫在專案 `.mcp.json` 而該檔沒進版控時，worktree 裡就沒有（見第 2 步）。有 linear 就讓 pane 自己 `get_issue` + `list_comments` 讀票，不要把票券描述複製進指令——省你的 context，而且票是唯一權威。沒有就由你把規格摘要寫進指令，並由你重建實作紀錄。

---

## 1. 盤點與波次組成

依 `parallel-wave` 第 1 步做兩層判斷（依賴關係硬條件、共用檔衝突軟條件），然後**用 AskUserQuestion 一次問完波次範圍與其他待決事項**，附推薦選項。

Herdr 版要多想一件事：**pane 是可見的，所以波次大小的上限是「使用者還看得過來幾個」**，不只是機器負載。三到四個是實務上的舒適上限。

---

## 2. 開工前置：四件事，第四件最容易漏

**1. 確認 base 分支狀態。** `git status --short`。有未預期改動就問使用者要保留、自己處理、還是由你 stash。**保留是常見選擇，那就在整合時做 stash dance**（見第 5 步）。

**2. 跑一次基準線驗證，當對照組。** 這一步省的時間最多，而且它的價值不只是暖快取：

> **設定檔宣稱的閘門狀態經常與現實脫節。** 實測過的案例：某專案的設定檔寫「13 支驗證腳本全部通過、全部免 server」，實際在乾淨的 base 分支上有 4 支是紅的——2 支的輸入檔已經從 repo 消失、2 支需要 dev server 在跑。若照設定檔把全部閘門掛上，**每個 pane 都會撞到不是自己造成的紅燈，白燒一整輪去追不存在的 bug。**

所以：在主 repo 跑一次完整閘門，記下哪些本來就紅、真因是什麼。**派工指令裡只列當下實際會綠的那幾條**，並明講排除了哪幾條、理由是什麼、不要去修。

**把這件事寫進記憶**——它是專案級事實，下次不必再測一遍。

**3. 建 worktree。** 分支名照專案慣例（多數專案的 `parallel-loop.json` / 慣例是 `feat/{TICKET}`），worktree 目錄名用簡短票號。

**4. 補齊所有未進版控的檔案——本 skill 這一步比 codex 版更關鍵。** worktree 只帶 tracked 檔案，`.gitignore` 的一律不繼承。清單通常在專案設定的 `worktreeSeedFiles` / `untrackedSetupFiles`，但**別只信那份清單**：

```bash
git status --short --ignored=no   # 看有哪些 ?? 檔是 agent 需要的
```

**Claude pane 特有的空洞：worktree 裡沒有專案層的 `.claude/` 與 `CLAUDE.md`。** 多數專案整個 `.claude/` 都在 `.gitignore` 裡，而 `CLAUDE.md` / `CLAUDE.local.md` 也常常還沒 commit。後果是三件事一起消失，而且**都不會有錯誤訊息**：

| 消失的東西 | 症狀 |
| --- | --- |
| `CLAUDE.md` / `CLAUDE.local.md` | pane 在**完全沒有專案指令**下工作——包括「改任何 symbol 前先跑影響分析」「UI 文字一律繁中」這種硬規則 |
| 專案層 skill（`.claude/skills/`） | pane 回 `Unknown command: /xxx`，而 `herdr agent prompt --wait` 只給你一個看不出原因的 `agent_prompt_stalled` |
| 專案層 `.mcp.json` | pane 讀不到 Linear / gitnexus，於是「自己讀票」那一段整段失效 |
| `.claude/settings.local.json` | 權限白名單消失，`--permission-mode auto` 之外的指令全部撞 `blocked` |

所以複製清單至少要涵蓋這幾項：

```bash
for f in .dev.vars fixtures node_modules CLAUDE.md CLAUDE.local.md .mcp.json .claude; do
  [ -e "$MAIN/$f" ] && { cp -Rc "$MAIN/$f" "$WT/$f" 2>/dev/null || cp -R "$MAIN/$f" "$WT/$f"; }
done
```

> 複製整個 `.claude/` 是刻意的：settings、skills、linear-workflow.json、report 都在裡面，逐項挑反而容易漏。副作用是 pane 會看到主 repo 的報告與狀態檔——那是唯讀性質的參考資料，無害。**唯一要注意的是別讓 pane 在 worktree 的 `.claude/` 裡寫東西然後以為主 repo 也有**，指令裡要明講產出只寫 `RESULT.md`。

`node_modules` 用 `cp -Rc`（APFS clonefile）幾乎瞬間完成，比 `npm ci` 快非常多。複製完印一份確認表，並實跑一次 `npx tsc --noEmit` 之類的輕量指令確認工具鏈可用——比讓 pane 撞牆再回報便宜。

設定檔清單列了已不存在的檔案時，**回報使用者並提議修正設定**，不要默默跳過。

**接著把整批票推到 `states.inProgress`**，動第一個編輯之前就推。

---

## 3. 派工

一票一個 workspace，cwd 指向它的 worktree：

```bash
herdr workspace create --cwd "<worktree 絕對路徑>" --label "PROJ-111" --no-focus
# 從回傳 JSON 取 result.root_pane.pane_id
herdr agent start proj-111 --kind claude --pane <pane_id> \
  -- --permission-mode auto --add-dir "<主 repo 絕對路徑>"
herdr agent prompt proj-111 "$(cat <prompt 檔>)"
```

**所有 pane 在同一則訊息裡起完並派工**，才是真的平行。

### `--permission-mode auto`

分類器自動放行低風險指令，白名單在 worktree 的 `.claude/settings.local.json`（第 2 步複製過去的那份），兩層都沒接住時 Herdr 會回報 `blocked`，由你在第 4 步處理。

**不要預設用 `--dangerously-skip-permissions`。** 它確實讓 pane 不會停下來，但也讓「rm -rf 打錯路徑」「push 到 origin」這類動作零關卡，而 pane 的 cwd 旁邊就是使用者的主 repo。**只有使用者明確要求時才升級**，合理的升級情境是：worktree 完全離線、或白名單反覆撞牆已經拖慢整波。升級了就在收工回報裡講明白。

### `--add-dir <主 repo>`

**這是 Claude pane 相對於 Codex 必須多做的一件事。** Claude Code 的工具存取限於 cwd 及其子目錄，而規格文件、reference 專案、報告經常在主 repo 的 gitignore 目錄裡（vault、`.claude/report/`、`docs/`）——不加這個旗標，pane 讀不到，然後它會自己編一套規格。

加了之後主 repo 對 pane 是**可讀也可寫**的，所以**指令裡必須明令「主 repo 只能讀」**（見模板）。兩個 pane 同時往主 repo 寫會互相踩，而且那些改動不在任何一條分支上，整合時你看不到。

### 指令模板

見 `references/pane-prompt.md`。**每一段都是實戰換來的，特別是這幾條不要省**：

- **讓 pane 自己讀票，並且明講「連我寫的解鎖註解一起讀」**（`list_comments`）。解鎖註解裡有「現在可以直接用什麼」與「該避開的坑」——這是分波推進的複利所在。
- **主 repo 唯讀**（因為 `--add-dir` 給了寫入能力，這句是唯一的防線）。
- **明講同波還有誰在跑、碰哪些檔、哪些檔獨佔**。pane 知道有鄰居才會自我克制。
- **共用檔的衝突紀律**：只准往檔尾追加、用註解標出區塊、只改最小必要行數、不准順手重排。
- **建置輸出重導到 log 再 `tail`**，不要讓數千行進 pane 的 context。
- **指路到既有的同類實作**。「有一個 X 已經用完全相同的模式做過，先把這三個檔讀完再動手，然後鏡像它」比任何抽象規範都有效。
- **不准 push、不准 merge、不准動 base 分支、不准改別的票、不准動 Linear 狀態或 labels**——整合與看板是你的職責。**但 pane 要自己寫實作紀錄註解**（見下），不要由你轉述。
- **誠實度要求要具體到痛點**。不要只說「請誠實」，要說「本專案 E2E 已關閉、瀏覽器層零自動守門，`build` 全綠完全不代表畫面對，你沒在瀏覽器裡看過就必須標未驗證」。
- **要求把可純函式驗證的部分補進既有 `verify:*` 腳本**。
- **要求寫 `RESULT.md` 到 worktree 根目錄且不要 commit**，內含 commit hash、改哪些檔與為什麼、**驗收條件逐條對照（通過／部分通過／未實測／沒做 + 實際證據）**、與票券不同的決策、處理掉的邊界情境、未驗證清單。**並要求它邊做邊寫**——pane 會 auto-compact，等做完才回想細節會失真。
- **要求 pane 在票上自己寫一則實作紀錄註解**，標題 `## 實作紀錄（pane · <票號>）`，含**思考軌跡**三段：我考慮過但沒選的做法、我撞到的牆（原始錯誤訊息）、我沒驗到的。格式照 `.claude/linear-workflow.md`。

  **這條是實跑之後改過來的，方向與早期版本相反。** 早期禁止 pane 留言、由你轉述 `RESULT.md`——結果是 worktree 一移除，pane 的思考軌跡就永久消失，而票上只剩你的第三人稱複述。轉述最先流失的永遠是「考慮過但沒選」，偏偏那是下一個接手的人最需要的：他第一個冒出來的念頭，常常正是 pane 已經評估並否決過的方案。

---

## 4. 等待：用 Monitor 包 herdr agent wait

不要 `sleep` 輪詢，也不要反覆讀畫面：

```
Monitor({
  command: 'for a in proj-111 proj-112; do ( herdr agent wait $a --timeout 3000000 >/dev/null 2>&1 \
             && echo "[$a] 已離開 working — 去對帳" || echo "[$a] wait 逾時或出錯" ) & done; wait',
  description: 'Claude panes 完工通知',
  timeout_ms: 3600000, persistent: false,
})
```

`herdr agent wait` 不帶 `--until` 時會等 idle / done / blocked 任一。**先回報的先整合**，不要等全部——後面的 rebase 一下就好。

### 醒來第一件事：分辨「做完了」與「卡住了」

`--permission-mode auto` 下 `blocked` 是常態，不是異常。**`wait` 返回不等於完工**，跑 `herdr agent list` 看實際狀態：

| 狀態 | 意義 | 動作 |
| --- | --- | --- |
| `idle` / `done` | 這一輪講完話了 | 讀 `RESULT.md` → 第 5 步。**沒有 RESULT.md = 沒做完**，回 pane 問 |
| `blocked` | 卡在權限提示或提問 | 見下 |
| `unknown` | Herdr 認不出來，**不代表完成** | `herdr agent read` 看畫面判斷 |
| 消失 | pane 被關 / 崩了 | 關 workspace、**留 worktree**、票退回 `states.todo` |

**`blocked` 的處理：**

```bash
herdr agent read proj-111 --source detection --lines 40
```

看它在問什麼。**權限提示**：判斷該指令是否落在合理範圍（跑 verify、動自己的 worktree、讀主 repo）→ 是就 `herdr agent send-keys` 放行，並**把該指令補進 worktree 的 `.claude/settings.local.json` 白名單**，讓它下次不再問；同一批指令反覆撞牆就一次補齊整組。**規格提問**：那不是你能答的，把問題原文帶回來問使用者。

pane 若在原地打轉（`herdr agent read` 看得出來），`herdr agent prompt` 補一句更緊的指令即可，同一個 pane 保留完整脈絡。**同一張票補正兩次仍不達標就停下來問使用者**——多半是票券規格本身有歧義，那是人要決定的事。

---

## 5. 回收：審碼，然後整合

### 先看 worktree 實況，不要只讀 RESULT.md

```bash
git -C "$WT" log --oneline <base>..HEAD    # 有沒有 commit
git -C "$WT" status --short                 # 工作區乾淨嗎、有沒有誤 commit
git -C "$WT" diff --stat <base>...HEAD      # 改了什麼、範圍有沒有超出票券
```

**同時 `list_comments({ issueId })` 確認 pane 真的寫了實作紀錄註解。** 沒寫就 `herdr agent prompt` 要它補——**在關掉 workspace 之前**，那之後 `RESULT.md` 與它的 context 就都沒了，補不回來。只有 `RESULT.md` 而票上沒有註解，等於這張票的思考軌跡只存在於一個即將被刪除的檔案裡。

### 審碼：同模型的自我回報，證據力比 Codex 更低

`parallel-wave` 第 4 步那四項照做（看 diff 本身、看 log 實際結尾、確認測試真的執行過並數斷言數、確認 gitignored 檔沒被 commit）。本 skill 再加四項，**第 8 項是 Claude-to-Claude 特有的**：

**5. 診斷「超出票面範圍」是必要還是順手。** 判準不是「有沒有超出」而是「有沒有正當理由」。**驗證方式是逐行比對**——若拆檔前後只差一行函式名，那就是忠實搬移而非偷渡重構，風險警示可以解除。

**6. 找出「落在被排除閘門盲區」的改動。** 這是本工作流最大的結構性風險。你在第 2 步排除了幾條閘門，若 pane 的改動剛好落在那些閘門本該覆蓋的範圍（例如改了 worker 而 `verify:api` 被排除），那段程式碼就是**零執行期覆蓋**。此時要親自讀碼推資料流、對 schema、檢查 SQL 是否參數化，並在整合註解裡**明講「這段沒有任何一次真實執行」**。

**7. 地基票要額外讀碼並補測 pane 標「未驗證」的項目。** 型別定義、共用演算法、核心 helper 錯了會污染所有下游，而錯誤形式往往是「編譯過、測試過、語意錯」。**pane 標未驗證而下游會直接踩到的項目，就是你該補的那一項。**

**8. 同模型審自己的碼會同盲點——對抗來源要另外找。** pane 是 Claude、你是 Claude、pane 的自審也是 Claude。三層都同一個模型，意味著**「它覺得對」與「你覺得對」高度相關**，這正是 `herdr-codex-wave` 天然具備而本 skill 缺少的東西。三個補救方式，**至少用一個**：

| 做法 | 什麼時候用 | 怎麼做 |
| --- | --- | --- |
| **Codex 對抗複查（最強）** | 地基票、演算法票、安全相關 | 回收時對 diff 跑 `codex:rescue`（或在 pane 的指令裡要求它自己跑一輪 codex review），明講「請證明這段是錯的」而不是「請 review」 |
| **執行證據取代判斷** | 任何票 | 不問「這樣對嗎」，改問「跑出來是什麼」。實跑、數斷言數、對輸出——執行結果不受模型盲點影響 |
| **反向舉證式自審** | 便宜、每票都做 | 你自己讀 diff 時，把問題從「這寫得好嗎」換成「**給我一組會讓它壞掉的輸入**」。舉不出來才算過 |

**「pane 的 RESULT.md 說驗收條件全過」在本 skill 裡的證據力，比在 codex 版更低**——因為它的判準和你的判準來自同一個分布。要嘛有執行證據，要嘛有異質來源背書，兩者皆無就標「未驗證」。

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

寫**整合註解**，標題 `## 整合與複查（主控）`。它與 pane 那則是兩份不同的東西：**pane 那則回答「當時是怎麼想的」，你這則回答「現在能不能信」。**

**你的職責是收斂、加註、修正 pane 的判斷，不是把它的 `RESULT.md` 重講一遍。** pane 已經自己寫了實作紀錄，你再複述一次只會讓票變長而資訊沒增加。

格式照 `.claude/linear-workflow.md` 的「註解怎麼寫」，**正文照結論在前的順序寫**：

| 順序 | 寫什麼 |
| --- | --- |
| 1 | **這張票現在是什麼狀態**：已進哪個分支、能不能信。一句話 |
| 2 | **我對 pane 判斷的修正**：哪裡它想錯了、我改了什麼。這是你存在的意義，沒這段就只是複讀 |
| 3 | **複查抓到的真問題**：每條一行（抓到什麼 → 怎麼處置）。用了哪個對抗來源（第 8 項）一句帶過 |
| 4 | **仍未驗證**：**原樣保留 pane 標的未驗證項**，不要因為合併成功就把「未實機驗證」升級成通過 |
| 5 | 下游影響（有才寫） |

**這些一律進 `<details>` 摺疊區，不要放正文**——它們是證據，不是結論：

- rebase 前後兩個 commit hash（rebase 會改寫 hash，只寫一個日後對不上；沒改寫時明講「前後同一個 hash，因為期間 base 沒有前進」）
- 在 base 分支上實跑的逐條閘門結果與**實際斷言數**
- **被排除的閘門與理由**、盲區評估（讓未來的人知道綠燈的邊界在哪）
- 複查發現的逐條推導、版面／效能的完整量測

**這三類不要寫進票**：你派工時犯的錯（進 log／HANDOFF，那是流程問題不是這張票的產出）、為什麼要跑異質複查的方法論、複查核對過但沒打穿的項目（壓成一句「另核對 N 項無發現」）。

判準一句話：**讀者不追問「你怎麼知道」就不需要的東西，不該在正文。**

然後推 `states.done`，照 `.claude/linear-workflow.md` 檢查下游解鎖：取 `blocks` 的下游，逐一實查它們**自己的**所有 `blockedBy`，全清才推 `states.todo`。

**解鎖註解是這個工作流的複利引擎，值得寫厚一點。** 下一波的 pane 會被指示去讀它。要寫：現在可以直接用什麼（具體檔案路徑與匯出名稱、可以照抄的既有實作）、**該避開的坑**（你審碼時發現的邊界、效能特性、會誤觸的機制）、以及**上游有哪些未驗證項目**（讓下一張票知道遇到問題時該不該歸因給自己）。

**合併完立刻 `git worktree remove` 並 `herdr workspace close <id>`**，別堆積。

---

## 6. 收工回報

**例行成功用一兩行帶過**：commit hash、閘門結果、看板狀態。詳細的複查發現寫進 Linear 整合註解——那是給未來的人看的紀錄，不是對話內容，不要在對話裡重述一遍。

**只有這幾種情況才展開**：真的失敗、發現會影響決策的風險、需要使用者決定的事（要不要 push、要不要刪已合併分支、要不要開下一波）。**已經提醒過且使用者已做決定的事不要再提。**

需要使用者親自做的事要單獨點出來（外部主控台設定、憑證、`wrangler secret put` 這類營運動作），因為程式碼這側做不到。

**若這一波曾把某個 pane 升級成 `--dangerously-skip-permissions`，收工時要講。**

發現值得記住的專案特定坑就寫進記憶，下次不用再撞一遍。

---

## 反模式

| 別做 | 為什麼 |
| --- | --- |
| 沒跑 `herdr integration install claude` 就開始 | `agent_status` 停在 `unknown`，只能靠讀畫面猜完工 |
| 忘記把 `.claude/` 與 `CLAUDE.md` 複製進 worktree | 它們多半在 gitignore；pane 會在零專案指令、零白名單、零 MCP 的狀態下工作，而且沒有任何錯誤訊息 |
| 沒給 `--add-dir <主 repo>` | pane 讀不到 gitignore 目錄裡的規格文件，然後自己編一套 |
| 給了 `--add-dir` 卻沒明令主 repo 唯讀 | 那個旗標同時給了寫入能力，兩個 pane 會在主 repo 互相踩，而且改動不在任何分支上 |
| 預設用 `--dangerously-skip-permissions` | pane 的 cwd 旁邊就是使用者的主 repo；沒有使用者明確要求就不要拿掉關卡 |
| 把 `wait` 返回當成完工 | `auto` 模式下 `blocked` 也會讓 wait 返回；一律 `herdr agent list` 對帳 |
| 照設定檔把全部閘門掛上 | 設定檔常與現實脫節；每個 pane 都會撞到不是自己造成的紅燈 |
| 把票券描述複製進派工指令 | 燒你的 context，而且票是唯一權威；pane 有 Linear MCP 就讓它自己讀 |
| 沒叫 pane 讀上一波的解鎖註解 | 白白丟掉分波推進最大的複利 |
| 用 `sleep` 或反覆讀畫面判斷完工 | 有 `herdr agent wait` + `Monitor` 就不必猜 |
| 分開送 pane 的啟動與派工訊息 | 會變成串行，白費整個 skill 的意義 |
| **把 Claude pane 的自審當成獨立驗證** | 同一個模型的判準高度相關；要嘛執行證據、要嘛異質來源，皆無就標未驗證 |
| 相信「測試通過」而不數斷言數 | 測試沒被執行也會 exit 0 |
| 讓 pane 自己 merge 或推狀態 | 併發寫 base 分支會互相覆蓋；看板正確性是你的責任 |
| **反過來：不讓 pane 自己寫實作紀錄註解** | worktree 一刪 `RESULT.md` 就沒了，你的轉述必然流失第一人稱的判斷過程——尤其「考慮過但沒選」那段 |
| 整合註解把 pane 的實作紀錄重講一遍 | 票變長但資訊沒增加。你那則只寫收斂、加註、修正 |
| 把 commit hash 表格與逐條閘門放進正文 | 那是證據不是結論。讀者要先看到「改變了什麼、能不能信、還缺什麼」 |
| 把「編譯過」寫成驗收通過 | 視覺與實機行為完全沒驗到，日後回查會被誤導 |
| 忽略落在被排除閘門盲區的改動 | 那段程式碼零執行期覆蓋，而綠燈會讓人以為它被驗過了 |
| 收工回報把整合細節在對話裡重述一遍 | 那些該寫進 Linear 註解；對話裡只留結論與待決事項 |

---

## 參考檔

- `references/pane-prompt.md` —— Claude pane 派工指令模板，逐段說明為什麼要有那一段
- `references/herdr-runtime.md` —— 已實查的 `herdr` CLI 契約與 Claude pane 特有的旗標
- `parallel-wave`（同 plugin）—— 共用的盤點、前置、整合原則
- `herdr-codex-wave`（同 plugin）—— 換成 Codex 當實作者的版本
