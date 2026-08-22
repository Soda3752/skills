---
name: herdr-claude-wave-v2
description: "herdr-claude-wave 的自主版：一次取得整份波次計畫與授權，之後連跑多波不再逐波問人，並把審碼與整合後驗證外包給兩個常駐 pane（reviewer / verifier），主控只保留波次判斷、ff merge 與看板。實作仍是每張 Linear 票一個 workspace + git worktree + 一個 Claude Code pane。Use this whenever the user wants a multi-wave Linear push to run with one upfront approval instead of stopping between waves, asks to drain several waves of tickets without being asked each time, wants code review or post-merge verification offloaded to dedicated standing panes, or says the orchestrator is spending too long blocked. Triggers: \"連跑多波\", \"不要每波問我\", \"一次授權跑完\", \"自主推進\", \"開常駐 reviewer\", \"審碼拆出去\", \"整合太慢\", \"主控卡太久\", \"wave v2\", \"run several waves without asking\", \"autonomous wave\", \"offload the review to another pane\". 需要 HERDR_ENV=1。要每波都停下來確認就用 herdr-claude-wave（單波審慎版）；實作者要換成 Codex 用 herdr-codex-wave；不要可見 pane 用 parallel-wave；要完全無人監督清空整個看板用 parallel-loop。"
---

# Herdr Claude Wave v2 —— 一次授權，連跑多波

與 v1 同一套骨架：一波 = 一批互相獨立的票，各自在專屬 worktree 裡由一個 Claude Code pane 做完。**差別在主控不再是唯一的序列瓶頸，也不再每波停下來等人。**

**你不寫業務程式碼。** v2 之後你連審碼與整合後驗證都不自己扛，只剩四件真正需要全局視野的事：波次判斷、ff merge、看板、以及決定何時該停下來問人。

## v2 改了什麼，為什麼

四項改造都來自同一次實測（15 張票的架構重構專案，第一波單票）：

| 觀測 | 數字 | 對應改造 |
| --- | --- | --- |
| 實作完成到主控收工 | 實作 20 分鐘，**整合尾段 15 分鐘**（佔 43%） | 審碼外包 reviewer、整合後驗證外包 verifier |
| 一波燒掉的主控 context | **21%**，而那一波只有一張票 | 審碼外包（讀 diff 是最大宗）+ context 預算與主動交接 |
| 波次之間的空轉 | 做完之後**完全停住**，等人回答「下一波派哪幾張」 | 一次取得波次計畫與授權，之後不問 |
| 閘門重複跑 | 每張票 ff 後都跑一次完整測試，序列累加 | 閘門分層：迭代只編譯，整波合完跑一次完整測試 |

**這四項是一組，不要只挑一項做。** 只做多波授權而不外包審碼，主控會在第二波就把 context 燒光；只外包審碼而仍逐波問人，省下的時間會全部還給等待。

## 選這個還是選別的

| 情境 | 用哪個 |
| --- | --- |
| 波次計畫已經清楚、票夠多、想讓它自己推完 | **本 skill** |
| 規格還不穩、第一次跑這個專案、想每波看一眼再決定 | `herdr-claude-wave`（單波審慎版） |
| 實作者要換成 Codex（不同模型、天然的對抗性） | `herdr-codex-wave` |
| 不需要可見 pane，用內建 Agent tool 就好 | `parallel-wave` |
| 要完全無人監督地清空整個看板（自動補位、自動收工） | `parallel-loop` / `linear-goal-loop` |

**盤點、審碼判準、整合原則與 `parallel-wave` 一致，本檔不重複**——需要時讀同 plugin 的 `parallel-wave` skill 的第 1、2、4 步。

票券工作流的行為（狀態 id、推票時機、註解規範、下游解鎖）一律遵守專案的 `.claude/linear-workflow.md`，**本 skill 不覆寫它**。

---

## 0. 一次性環境檢查

```bash
echo "$HERDR_ENV"                       # 必須是 1，否則整個 skill 不適用
claude --version
herdr integration status | grep claude
```

**`claude: not installed` 的話先跑 `herdr integration install claude`。** 它寫入 `~/.claude/hooks/herdr-agent-state.sh`，讓 Herdr 認得 Claude pane 的 `working` / `idle` / `blocked` 轉換。沒裝的症狀是 `agent_status` 永遠停在 `unknown`，你只能輪詢 `herdr agent read` 讀畫面尾端猜完工——而 Claude 思考久一點就會被誤判成做完了。

**v2 對這件事的依賴比 v1 更重**：多波自主推進意味著沒有人在旁邊看畫面，`wait` 不可靠等於整條流程失去唯一的完工訊號。**它會改使用者的 `~/.claude/` 設定，先徵得同意。**

**確認 pane 能不能自己讀票**：Claude Code 的 MCP 來自 user scope（`~/.claude.json`）與**專案的 `.mcp.json`**。有 linear 就讓 pane 自己 `get_issue` + `list_comments` 讀票，不要把票券描述複製進指令——省你的 context，而且票是唯一權威。沒有就由你把規格摘要寫進指令。

**確認 pane 預算。** 實作 pane 一波三到四個，加上兩個常駐 pane，同時活著的 Claude 實例是五到六個。跑 `herdr agent list` 看現在還有誰在，別把使用者正在用的那隻算進去。

---

## 1. 波次計畫與授權 —— 一次問完，之後不再問

這是 v2 與 v1 唯一的流程性差異，也是省下最多掛鐘時間的一步。

依 `parallel-wave` 第 1 步做兩層判斷（依賴關係硬條件、共用檔衝突軟條件），但**不是只排出這一波，是排出到收斂為止的整份波次計畫**：

```
波 1  PROJ-11                      ← prefactor，所有票的上游
波 2  PROJ-12 + PROJ-13 + PROJ-17  ← 檔案面不交集
波 3  PROJ-14 + PROJ-15 + PROJ-16  ← 共用 UiState，等波 2 的結論
波 4  PROJ-18 + PROJ-19            ← 兩張 contract 票
```

計畫是**預測不是承諾**。每一波收完要重算，因為上一波可能改變了衝突面。**重算的結果與原計畫不同時不必問人，把差異寫進波次交棒紀錄即可**（第 6 步）——問人正是 v2 要消除的那件事。

### 用一次 AskUserQuestion 問完全部

一次問完這幾項，附推薦選項：

1. **波次計畫**：整份給他看，問要不要調整
2. **授權範圍**：連跑到收斂，還是跑到第 N 波為止
3. **`manualVerification` 設定**（見第 2 步第五件）
4. **base 分支與未提交改動的處置**（見第 2 步第一件）
5. **要不要升級 `--dangerously-skip-permissions`**（預設不要）

**問完就不要再問。** v2 的價值全部建立在這一句上。

### 授權書：只有這三種情況才停下來

把這三條講給使用者聽並取得同意，之後就照著執行：

| 停 | 不停 |
| --- | --- |
| pane 卡在**規格歧義**（票券本身講不清楚，補正兩次仍不達標） | pane 卡在權限提示 → 你放行並補白名單 |
| 閘門紅了而且**查不出原因**（不是 pane 造成的、也不是已知排除項） | 閘門紅了但看得出是 pane 的問題 → 回 pane 補正 |
| 需要**使用者親自動手**（Xcode 加 SPM、憑證、外部主控台） | 波次計畫與原本不同 → 記錄下來繼續跑 |

停下來的時候要一次講清楚：卡在哪、你需要什麼、以及**其他還在跑的 pane 現在是什麼狀態**——使用者要能判斷該先處理這件事還是先讓其他票跑完。

---

## 2. 開工前置：六件事

前五件與 v1 相同，**第六件是 v2 新增的**。

**1. 確認 base 分支狀態。** `git status --short`。有未預期改動就在第 1 步那次 AskUserQuestion 一起問：保留、自己處理、還是由你 stash。保留是常見選擇，那就在整合時做 stash dance（見第 5 步）。

**2. 跑一次基準線驗證，當對照組。** 這一步省的時間最多：

> **設定檔宣稱的閘門狀態經常與現實脫節。** 實測過的案例：某專案的設定檔寫「13 支驗證腳本全部通過」，實際在乾淨的 base 分支上有 4 支是紅的。若照設定檔把全部閘門掛上，**每個 pane 都會撞到不是自己造成的紅燈，白燒一整輪去追不存在的 bug。**

另一種更隱蔽的形式：**設定檔寫的閘門指令本身跑不起來。** 實測案例——專案設定寫閘門是 `:composeApp:allTests`，但那個 task 含 iOS target，而 iOS 端缺一個必須由人在 Xcode 加的 SPM 套件，於是 `allTests` 永遠紅；實際可用的閘門是 `:composeApp:testDebugUnitTest`。**這種事只有實跑才會發現，而且發現一次就該寫進記憶**，否則每一波都要重新踩一遍。

派工指令裡只列當下實際會綠的那幾條，並明講排除了哪幾條、理由是什麼、不要去修。

**3. 建 worktree。** 分支名照專案慣例（多數專案是 `feat/{TICKET}`），worktree 目錄名用簡短票號。

**4. 補齊所有未進版控的檔案。** worktree 只帶 tracked 檔案，`.gitignore` 的一律不繼承。**Claude pane 特有的空洞：worktree 裡沒有專案層的 `.claude/` 與 `CLAUDE.md`**，而且三件事會一起消失且都沒有錯誤訊息：

| 消失的東西 | 症狀 |
| --- | --- |
| `CLAUDE.md` / `CLAUDE.local.md` | pane 在**完全沒有專案指令**下工作 |
| 專案層 skill（`.claude/skills/`） | pane 回 `Unknown command: /xxx`，而 `--wait` 只給你一個看不出原因的 `agent_prompt_stalled` |
| 專案層 `.mcp.json` | pane 讀不到 Linear / gitnexus，「自己讀票」整段失效 |
| `.claude/settings.local.json` | 權限白名單消失，`auto` 之外的指令全部撞 `blocked` |

```bash
for f in .dev.vars fixtures node_modules CLAUDE.md CLAUDE.local.md .mcp.json .claude; do
  [ -e "$MAIN/$f" ] && { cp -Rc "$MAIN/$f" "$WT/$f" 2>/dev/null || cp -R "$MAIN/$f" "$WT/$f"; }
done
```

`node_modules` 用 `cp -Rc`（APFS clonefile）幾乎瞬間完成。複製完印一份確認表，並實跑一次輕量指令確認工具鏈可用。

**5. 決定人工驗收要怎麼開頁，並分配 port。** 讀專案 `.claude/linear-workflow.json` 的 `manualVerification` 區塊。**port 由你分配，不能讓 pane 自己挑**：`portBase + 波內序號`。兩個 pane 撞同一個 port 時，使用者看到的畫面會屬於錯的那張票——而那個畫面「看起來是對的」，是最難察覺的一種錯。

**Claude pane 特有的一步**：`nohup`、`open`、`curl` 在 `--permission-mode auto` 下可能撞權限提示，先補進 worktree 的 `.claude/settings.local.json` 白名單。專案沒有可開的頁面（純 CLI／library）就整段略過。細節見 `references/manual-verification.md`。

**6. 起兩個常駐 pane。** v2 新增，完整協定見 `references/standing-panes.md`。

```bash
herdr workspace create --cwd "<主 repo>" --label "reviewer" --no-focus
herdr agent start reviewer --kind claude --pane <pane_id> \
  -- --permission-mode auto --add-dir "<worktree 根目錄>"
herdr agent prompt reviewer "$(cat <reviewer 開場指令>)"

herdr workspace create --cwd "<主 repo>" --label "verifier" --no-focus
herdr agent start verifier --kind claude --pane <pane_id> -- --permission-mode auto
herdr agent prompt verifier "$(cat <verifier 開場指令>)"
```

**常駐是刻意的：它們跨波次活著，不隨波次關閉。** 理由是它們累積的專案知識（這個 repo 的慣例、哪些閘門本來就紅、上一波抓到什麼）正是它們的價值所在，每波重開等於每波重新學一次。

**reviewer 的 cwd 是主 repo，並用 `--add-dir` 把 worktree 根目錄加進去**——它要能同時讀主 repo 與多個 worktree。verifier 只在主 repo 的 base 分支上跑閘門，不需要額外目錄。

常駐 pane 的 context 也會滿。**每波收完檢查一次它們的用量，超過 60% 就重起一隻並把累積知識寫進開場指令**——這比讓它在半波中途 auto-compact 掉關鍵脈絡安全。

**接著把整批票推到 `states.inProgress`**，動第一個編輯之前就推。

---

## 3. 派工

一票一個 workspace，cwd 指向它的 worktree：

```bash
herdr workspace create --cwd "<worktree 絕對路徑>" --label "PROJ-111" --no-focus
herdr agent start proj-111 --kind claude --pane <pane_id> \
  -- --permission-mode auto --add-dir "<主 repo 絕對路徑>"
herdr agent prompt proj-111 "$(cat <prompt 檔>)"
```

**所有 pane 在同一則訊息裡起完並派工**，才是真的平行。

### `--permission-mode auto`

分類器自動放行低風險指令，白名單在 worktree 的 `.claude/settings.local.json`。**不要預設用 `--dangerously-skip-permissions`**——pane 的 cwd 旁邊就是使用者的主 repo。只有使用者在第 1 步明確同意時才升級，升級了就在收工回報裡講明白。

### `--add-dir <主 repo>`

Claude Code 的工具存取限於 cwd 及其子目錄，而規格文件、reference 專案、報告經常在主 repo 的 gitignore 目錄裡。不加這個旗標，pane 讀不到，然後它會自己編一套規格。

加了之後主 repo 對 pane 是**可讀也可寫**的，所以**指令裡必須明令「主 repo 只能讀」**。

### 指令模板

見 `references/pane-prompt.md`。v1 那些段落全部保留，**v2 要多寫進去的有三段**：

- **閘門分層**（見下）——不寫的話 pane 會在每次小改動後跑完整測試，一張票就浪費掉十幾分鐘
- **鄰居包含常駐 pane**：明講 reviewer 會在它完工後審它的碼。知道會被異質審查的 pane，`RESULT.md` 會寫得比較誠實
- **完工訊號要明確**：`RESULT.md` 寫完才算完工，因為 reviewer 與 verifier 都以它為輸入

### 閘門分層

v1 的做法是每個 pane 每次驗證都跑完整閘門。在測試數量大的專案（數百個測試、Gradle／Xcode 這類冷啟動昂貴的工具鏈）這是主要的時間去處。

| 階段 | 跑什麼 | 誰跑 |
| --- | --- | --- |
| pane 內迭代 | 只跑**編譯／型別檢查**（`assembleDebug`、`tsc --noEmit`、`cargo check`） | 實作 pane，每次改動後 |
| pane 完工前 | 完整測試套件一次 | 實作 pane，寫 `RESULT.md` 之前 |
| 每張 ff merge 後 | 只跑編譯 | 主控（快，確認沒編壞） |
| 整波合完 | 完整測試套件一次 + 比對斷言數 | **verifier pane**，主控不等它 |

**斷言數比對只在整波那一次做，但一定要做。** 少了它，回歸會被「反正都綠」蓋過去。

**這張表要照專案調整，不要照抄。** 判準是「這個階段最可能出現的錯，最便宜的偵測手段是什麼」。編譯期就能抓的錯不必動用測試；只有測試抓得到的錯，不要拖到整波才發現——所以 pane 完工前那一次完整測試不能省。

---

## 4. 等待：Monitor 包 herdr agent wait

不要 `sleep` 輪詢，也不要反覆讀畫面：

```
Monitor({
  command: 'for a in proj-111 proj-112 proj-113; do ( herdr agent wait $a --timeout 3000000 >/dev/null 2>&1 \
             && echo "[$a] 已離開 working — 去對帳" || echo "[$a] wait 逾時或出錯" ) & done; wait',
  description: 'Claude panes 完工通知',
  timeout_ms: 3600000, persistent: false,
})
```

**只 wait 實作 pane，不要 wait 常駐 pane。** 常駐 pane 在波次之間本來就是 idle，把它加進 wait 清單會讓 Monitor 立刻返回，你就失去了完工訊號。

`herdr agent wait` 不帶 `--until` 時會等 idle / done / blocked 任一。**先回報的先進第 5 步**，不要等全部。

### 醒來第一件事：分辨「做完了」與「卡住了」

`--permission-mode auto` 下 `blocked` 是常態，不是異常。**`wait` 返回不等於完工**，跑 `herdr agent list` 看實際狀態：

| 狀態 | 意義 | 動作 |
| --- | --- | --- |
| `idle` / `done` | 這一輪講完話了 | 讀 `RESULT.md` → 第 5 步。**沒有 RESULT.md = 沒做完**，回 pane 問 |
| `blocked` | 卡在權限提示或提問 | 見下 |
| `unknown` | Herdr 認不出來，**不代表完成** | `herdr agent read` 看畫面判斷 |
| 消失 | pane 被關 / 崩了 | 關 workspace、**留 worktree**、票退回 `states.todo` |

**`blocked` 的處理：** `herdr agent read proj-111 --source detection --lines 40` 看它在問什麼。**權限提示**：判斷該指令是否落在合理範圍 → 是就 `herdr agent send-keys` 放行，並**把該指令補進 worktree 的白名單**。**規格提問**：依授權書，**先補正兩次再決定要不要停下來問人**。

### 醒來第二件事：把兩件事同時發出去

v1 在這裡是序列的：主控自己讀 diff → 審碼 → rebase → merge → 跑閘門 → 寫註解。v2 把第一件與最後一件外包，**在同一則訊息裡發出去**：

```bash
herdr agent prompt reviewer "審 PROJ-111：worktree <路徑>，base <分支>，RESULT.md 已寫。<協定見 references>"
```

然後你**立刻**去做 rebase 與 ff merge，不等 reviewer。兩件事在時間上重疊，這是 v2 省下整合尾段時間的主要來源。

**唯一的排序約束：reviewer 回報「有阻斷級問題」時，若你已經 ff merge 了，就 `git reset --hard` 退回並回 pane 補正。** 這聽起來危險，實際上不是——base 分支在這個工作流裡是本地分支、沒有 push、只有你在寫，退回的成本就是一個指令。**用「可以退回」換掉「必須等待」是划算的。**

真的不能接受退回的票（已經有別的票 rebase 上去了、或這是要立刻 push 的分支），就在那一張票上退回 v1 的序列做法：等 reviewer 回報再 merge。**這是逐票的判斷，不是整波的模式切換。**

### 醒來第三件事：把人工驗收清單搬進對話

pane 完工時已經起好 dev server、把測試頁 `open` 在使用者的瀏覽器裡，並把清單寫進 `RESULT.md`。**原樣搬進對話**，不要摘要成「請驗一下訂單功能」。一波多票就標明哪個 port 屬於哪張票：

```
PROJ-111 訂單列表 → http://localhost:5173/orders （4 項，約 3 分鐘）
PROJ-112 設定頁   → http://localhost:5174/settings（3 項，約 2 分鐘）
```

**人工驗收是唯一不受授權書覆蓋的等待。** 授權你連跑多波，不等於授權你替使用者宣告畫面驗過了。使用者沒回覆就繼續跑下一波，但那些項目在票上一律標「未驗證」，並在收工回報列出還欠哪幾張的驗收。

---

## 5. 回收：審碼外包，整合序列，驗證外包

### 先看 worktree 實況，不要只讀 RESULT.md

```bash
git -C "$WT" log --oneline <base>..HEAD    # 有沒有 commit
git -C "$WT" status --short                 # 工作區乾淨嗎、有沒有誤 commit
git -C "$WT" diff --stat <base>...HEAD      # 改了什麼、範圍有沒有超出票券
```

**這三行你自己跑，不外包。** 它們很便宜，而且是你判斷「要不要相信 reviewer 的結論」的基準——reviewer 說沒問題但 `diff --stat` 顯示它動了三十個不該動的檔，那就是 reviewer 漏了。

### 審碼：外包給 reviewer，但結論由你負責

reviewer 的協定、開場指令與回報格式見 `references/standing-panes.md`。你要理解的是**它替你做了什麼、沒替你做什麼**：

| reviewer 做 | 你仍然要做 |
| --- | --- |
| 逐行讀 diff，找出超出票面範圍的改動並判斷是必要還是順手 | 決定阻斷級問題要退回還是接受 |
| 檢查 gitignored 檔有沒有被 commit | 判斷「落在被排除閘門盲區」的改動風險——只有你知道排除了哪些閘門、為什麼 |
| 讀 log 實際結尾，確認測試真的執行過並數斷言數 | 地基票的補測（型別定義、共用演算法、核心 helper） |
| 反向舉證：對每個結論給出「會讓它壞掉的輸入」，舉不出來才算過 | 把結論寫進整合註解 |

**reviewer 是 Claude，pane 也是 Claude，同盲點問題沒有因為換一個 pane 就消失。** 換 pane 消除的是「自己審自己」的那層偏誤，不是模型層的盲點。所以 v1 的三個補救手段仍然全部適用，**至少用一個**：

| 做法 | 什麼時候用 |
| --- | --- |
| **Codex 對抗複查（最強）** | 地基票、演算法票、安全相關。在 reviewer 的指令裡要求它對 diff 跑 `codex:rescue`，明講「請證明這段是錯的」 |
| **執行證據取代判斷** | 任何票。不問「這樣對嗎」，改問「跑出來是什麼」 |
| **反向舉證式自審** | 便宜、每票都做。已經寫進 reviewer 的協定 |

### 整合：rebase + fast-forward，一張一張來

```bash
git -C "$WT" rebase <base>
git -C "$MAIN" merge --ff-only <branch>
```

**這一段不外包，也不能平行。** 兩個 pane 同時寫 base 分支會互相覆蓋，而覆蓋掉的東西不在任何一條分支上，事後找不回來。

**合併順序照第 1 步的風險分析**：低風險先進；共用檔的票**新增內容少的先合、多的 rebase 上去**。

**base 分支有未提交改動時的 stash dance**：`--ff-only` 不允許被合併動到的檔案帶有本地改動。

```bash
git stash push -m "<描述>" -- <只有那個衝突檔>
git merge --ff-only <branch>
git stash pop
```

只 stash 真正衝突的那個檔。pop 之後**實查使用者的改動是否完整還原**。

**共用檔的 add/add 衝突有個固定形狀**：兩張票都在檔尾同一個插入點追加，git 會把兩者共用的結尾行合在一起而報衝突。**解法是兩塊都保留、各自補回自己的結尾行**。解完後 `grep -c "^<<<<<<<\|^=======$\|^>>>>>>>"` 確認無殘留。

**每張 ff 後只跑編譯**（閘門分層那張表）。完整測試交給 verifier。

### 整合後驗證：外包給 verifier

整波都合完之後，把驗證丟給 verifier 就繼續做收尾：

```bash
herdr agent prompt verifier "波 2 已全部合進 <base>，跑完整閘門並比對斷言數。基準：<上一波的數字>。<協定見 references>"
```

**verifier 回報紅燈時的處置順序**：先看是不是已知排除項 → 再看是不是斷言數變少（回歸訊號，最嚴重）→ 再二分是哪一張票造成的。**二分很便宜，因為每張票都是一個 ff commit**，`git bisect` 或直接逐個 `git reset --hard HEAD~1` 都能定位。

verifier 還沒回報就開下一波是**可以的**——下一波的 worktree 從當前 base 拉出去，若 verifier 之後回報紅燈，那一波要跟著 rebase。**只有在 verifier 回報「斷言數變少」時才必須停下來**，那代表 base 現在是壞的，繼續往上疊只會擴大污染面。

### 收尾

寫**整合註解**，標題 `## 整合與複查（主控）`。它與 pane 那則是兩份不同的東西：**pane 那則回答「當時是怎麼想的」，你這則回答「現在能不能信」。**

**你的職責是收斂、加註、修正 pane 的判斷，不是把 `RESULT.md` 重講一遍。** 正文照結論在前的順序：

| 順序 | 寫什麼 |
| --- | --- |
| 1 | **這張票現在是什麼狀態**：已進哪個分支、能不能信。一句話 |
| 2 | **我對 pane 判斷的修正**：哪裡它想錯了、我改了什麼。沒這段就只是複讀 |
| 3 | **複查抓到的真問題**：每條一行（抓到什麼 → 怎麼處置）。**註明是 reviewer 抓的還是你抓的**，以及用了哪個對抗來源 |
| 4 | **人工驗收結果**：幾項、使用者實驗幾項、哪幾項不符與怎麼處置、哪幾項他沒驗 |
| 5 | **仍未驗證**：原樣保留 pane 標的未驗證項與使用者沒驗到的清單項 |
| 6 | 下游影響（有才寫） |

**這些一律進 `<details>` 摺疊區**：rebase 前後兩個 commit hash、逐條閘門結果與實際斷言數、被排除的閘門與理由、人工驗收清單全文、複查發現的逐條推導。

判準一句話：**讀者不追問「你怎麼知道」就不需要的東西，不該在正文。**

然後推 `states.done`，照 `.claude/linear-workflow.md` 檢查下游解鎖：取 `blocks` 的下游，逐一實查它們**自己的**所有 `blockedBy`，全清才推 `states.todo`。

**解鎖註解是這個工作流的複利引擎，v2 尤其如此**——因為下一波是你自己開的，沒有人會在中間幫你補脈絡。要寫：現在可以直接用什麼（具體檔案路徑與匯出名稱、可以照抄的既有實作）、該避開的坑、上游有哪些未驗證項目。

**收 worktree 的時機被人工驗收綁住**：合併可以立刻做，`git worktree remove` 要等使用者回報驗收結果。順序是：使用者回覆 → `kill $(cat <worktree>/.dev-server.pid)` → `git worktree remove` → `herdr workspace close <id>`。

使用者一直沒回就把 worktree 留著。**其餘不需要開頁的票維持原則：合併完立刻收。**

---

## 6. 波次交棒：不問人，直接開下一波

v1 到這裡就結束了。v2 的迴圈在這裡繼續。

### 開下一波之前，寫一份波次交棒紀錄

寫到 `.claude/report/<日期>/wave-log.md`，**每波追加一段，不要覆蓋**：

```markdown
## 波 2（PROJ-12 / PROJ-13 / PROJ-17）

- 合併：3 張全進 <base>，ff commit a1b2c3d / e4f5g6h / i7j8k9l
- 閘門：verifier 回報 457 tests / 0 failures，斷言數與基準線一致
- reviewer 抓到：PROJ-13 動了不在票面內的 3 個檔（判定為必要，逐行比對後只差函式名）
- 未驗證：PROJ-17 的畫面，使用者未回報驗收
- 與原計畫的差異：無
- 下一波：PROJ-14 / PROJ-15 / PROJ-16（原計畫波 3），共用 UiState 的歸屬已由波 2 的 PROJ-13 決定，寫進派工指令
```

**這份紀錄有三個讀者**：使用者（他不在旁邊，這是他唯一的進度來源）、下一波的你（context 可能已經被 compact）、接手的你（見下）。

### context 預算與主動交接

**每波結束檢查一次自己的用量。超過 60% 就主動交接，不要撐。**

理由是撐下去的失敗形式很難看：auto-compact 會在半波中途發生，而那時你手上握著「哪張票已 ff、哪張還沒、reviewer 說了什麼、verifier 還在跑什麼」——這些全是壓縮時最容易被判定為過程細節而丟掉的東西，丟了之後你會重複 merge 或漏掉一張票。

交接的做法：把 `wave-log.md` 補到最新，然後起一個新的主控 pane，開場指令指向那份 log 與波次計畫。**常駐 reviewer / verifier 不用換**，它們的脈絡與主控無關。

### 收斂與收工

**收斂條件**：波次計畫跑完，或看板上沒有 blocker 全清的票了。

跑完最後一波要多做一件事：**回頭檢查整份計畫執行下來與原計畫的差異**，把差異與原因寫進 `wave-log.md` 的結尾。那是下次規劃波次時最有用的一份資料。

---

## 7. 收工回報

**例行成功用一兩行帶過**：幾波幾張票、commit 範圍、閘門結果、看板狀態。詳細內容寫在 Linear 註解與 `wave-log.md`，不要在對話裡重述。

**這幾件一定要單獨點出來**：

- **還欠的人工驗收**：哪幾張票的頁面還開著、在哪個 port、使用者還沒回報
- **需要使用者親自做的事**：外部主控台設定、憑證、Xcode 加 SPM 這類程式碼這側做不到的
- **中途曾停下來問人的那幾次**，以及最後怎麼解的
- **未驗證項目的總清單**——多波跑完之後這份清單會比單波長很多，散在各張票裡沒人看得到全貌
- 若曾把某個 pane 升級成 `--dangerously-skip-permissions`

發現值得記住的專案特定坑就寫進記憶。**閘門的真實形狀（哪個 task 實際可用、哪些本來就紅）是最值得寫的一項**，它每一波都會被用到。

---

## 反模式

v1 的反模式全部適用。**以下是 v2 特有的：**

| 別做 | 為什麼 |
| --- | --- |
| 只做多波授權，不外包審碼 | 主控會在第二波就把 context 燒光，然後在最糟的時機 auto-compact |
| 只外包審碼，仍然逐波問人 | 省下的時間全部還給等待，改造等於白做 |
| 把 reviewer / verifier 加進 `herdr agent wait` 清單 | 它們在波次之間是 idle，Monitor 會立刻返回，你失去完工訊號 |
| 每波重開常駐 pane | 它們的價值是累積的專案知識，每波重開等於每波重新學 |
| 等 reviewer 回報才開始 rebase | 那就退回 v1 的序列做法了。**平行做，用「可以退回」換「不必等待」** |
| 反過來：對「不能退回的票」也硬要平行 | 已經有別的票 rebase 上去、或分支要立刻 push 時，退回的成本不再是一個指令 |
| verifier 回報「斷言數變少」還繼續開下一波 | base 現在是壞的，往上疊只會擴大污染面。這是唯一必須停的紅燈 |
| 把「使用者沒回驗收」當成驗收通過 | 授權你連跑多波，不等於授權你替他宣告畫面驗過了 |
| 波次計畫變了就跑去問人 | 計畫本來就是預測。**記錄差異，繼續跑**——問人正是 v2 要消除的那件事 |
| context 到 80% 才想交接 | auto-compact 會在半波中途發生，丟掉的正是「哪張已 ff、哪張還沒」這種過程狀態 |
| 不寫 `wave-log.md` | 使用者不在旁邊，那是他唯一的進度來源；你自己被 compact 之後也靠它復原 |
| 閘門分層照抄本檔的表 | 那張表要照專案調整。判準是「這個階段最可能出現的錯，最便宜的偵測手段是什麼」 |
| pane 完工前那次完整測試也省掉 | 只有測試抓得到的錯會被拖到整波才發現，二分成本遠高於當場跑一次 |

---

## 參考檔

- `references/standing-panes.md` —— **v2 新增**：reviewer / verifier 的開場指令、回報格式、生命週期與換手時機
- `references/pane-prompt.md` —— 實作 pane 派工指令模板，逐段說明為什麼要有那一段
- `references/manual-verification.md` —— 完工開頁、port 分配與 server 生命週期、STE100 寫法的人工驗收清單模板
- `references/herdr-runtime.md` —— 已實查的 `herdr` CLI 契約與 Claude pane 特有的旗標
- `herdr-claude-wave`（同 plugin）—— 單波審慎版，每波停下來確認
- `parallel-wave`（同 plugin）—— 共用的盤點、前置、整合原則
- `herdr-codex-wave`（同 plugin）—— 換成 Codex 當實作者的版本
