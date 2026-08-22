---
name: herdr-claude-wave-v2
description: "herdr-claude-wave 的流水線版：一次取得整份波次計畫與授權，之後連跑多波不再逐波問人；主控在 pane 寫程式的期間做下一波的前置，閘門丟背景不阻塞，diff 分類讀，Linear 更新整波批次做。實作仍是每張 Linear 票一個 workspace + git worktree + 一個 Claude Code pane。不多開任何角色 pane——優化全部落在主控自己的行為上。Use this whenever the user wants a multi-wave Linear push to run with one upfront approval instead of stopping between waves, says the orchestrator idles while panes work or spends too long on integration, asks to speed up a wave-based workflow without adding more agents, or wants the next wave prepared while the current one is still running. Triggers: \"連跑多波\", \"不要每波問我\", \"一次授權跑完\", \"自主推進\", \"主控卡太久\", \"整合太慢\", \"主控在等 pane 的時候很閒\", \"流水線\", \"wave v2\", \"run several waves without asking\", \"autonomous wave\", \"the orchestrator is idle while panes work\". 需要 HERDR_ENV=1。要每波都停下來確認就用 herdr-claude-wave（單波審慎版）；實作者要換成 Codex 用 herdr-codex-wave；不要可見 pane 用 parallel-wave；要完全無人監督清空整個看板用 parallel-loop。"
---

# Herdr Claude Wave v2 —— 流水線版

與 v1 同一套骨架：一波 = 一批互相獨立的票，各自在專屬 worktree 裡由一個 Claude Code pane 做完。**差別全部在主控自己的行為上，不多開任何角色 pane。**

**你不寫業務程式碼。** 你做四件 pane 做不好的事：判斷哪些票能同時跑、把專案的隱性知識寫進派工指令、逐一審碼把關、序列整合進 base 分支並維護看板。

## v2 改了什麼，為什麼

一次實測（15 張票的架構重構專案，第一波單票）的時間軸：

```
14:33 派工 ──────────────── 14:53 pane commit ──── 15:08 主控收工 ──── 停住等人
      └── 主控閒置 20 分 ──┘└── 主控序列回收 15 分 ─┘└── 無限久 ──┘
```

三段裡有兩段可以消掉。六項改動，全部落在主控：

| # | 改動 | 消掉哪一段 |
| --- | --- | --- |
| 1 | 一次取得波次計畫與授權，波末不問人 | 「停住等人」整段 |
| 2 | pane 寫程式的期間，主控做下一波前置 | 「閒置 20 分」整段 |
| 3 | 閘門不重複跑：ff 後只編譯，整波合完才跑一次完整測試 | 回收段的 N-1 次完整測試 |
| 4 | 閘門丟背景，不在前景等 | 回收段的等待 |
| 5 | diff 分類讀：搬檔／改名只確認對應，只有改內容的逐行讀 | 回收段的讀碼時間與 context |
| 6 | Linear 更新整波批次做，不逐票做 | 回收段的重複往返 |

**曾經試過多開 reviewer / verifier pane，那是錯的。** 多開的 pane 也是 Claude，它讀 diff 一樣要五分鐘，而主控合併只要兩分鐘——一波只有一兩張票時，主控反而要等它，淨值是變慢。角色拆分只在波次夠大時才回本，而波次夠大時上面六項本來就已經把時間壓下來了。

## 選這個還是選別的

| 情境 | 用哪個 |
| --- | --- |
| 波次計畫已經清楚、票夠多、想讓它自己推完 | **本 skill** |
| 規格還不穩、第一次跑這個專案、想每波看一眼再決定 | `herdr-claude-wave`（單波審慎版） |
| 實作者要換成 Codex（不同模型、天然的對抗性） | `herdr-codex-wave` |
| 不需要可見 pane，用內建 Agent tool 就好 | `parallel-wave` |
| 要完全無人監督地清空整個看板 | `parallel-loop` / `linear-goal-loop` |

**盤點、審碼判準、整合原則與 `parallel-wave` 一致**——需要時讀同 plugin 的 `parallel-wave` 第 1、2、4 步。

票券工作流的行為（狀態 id、推票時機、註解規範、下游解鎖）一律遵守專案的 `.claude/linear-workflow.md`，**本 skill 不覆寫它**。

---

## 0. 一次性環境檢查

```bash
echo "$HERDR_ENV"                       # 必須是 1，否則整個 skill 不適用
claude --version
herdr integration status | grep claude
```

**`claude: not installed` 就先跑 `herdr integration install claude`。** 它讓 Herdr 認得 Claude pane 的 `working` / `idle` / `blocked` 轉換。沒裝的症狀是 `agent_status` 永遠停在 `unknown`，你只能讀畫面猜完工——而 Claude 思考久一點就會被誤判成做完了。

**v2 對這件事的依賴比 v1 更重**：波末不問人意味著沒有人在旁邊看畫面，`wait` 不可靠等於整條流程失去唯一的完工訊號。**它會改使用者的 `~/.claude/` 設定，先徵得同意。**

**確認 pane 能不能自己讀票**：Claude Code 的 MCP 來自 user scope（`~/.claude.json`）與專案的 `.mcp.json`。有 linear 就讓 pane 自己 `get_issue` + `list_comments` 讀票，不要把票券描述複製進指令——省你的 context，而且票是唯一權威。

---

## 1. 波次計畫與授權 —— 一次問完，之後不再問

依 `parallel-wave` 第 1 步做兩層判斷（依賴關係硬條件、共用檔衝突軟條件），但**不是只排出這一波，是排出到收斂為止的整份計畫**：

```
波 1  PROJ-11                      ← prefactor，所有票的上游
波 2  PROJ-12 + PROJ-13 + PROJ-17  ← 檔案面不交集
波 3  PROJ-14 + PROJ-15 + PROJ-16  ← 共用 UiState，等波 2 的結論
波 4  PROJ-18 + PROJ-19            ← 兩張 contract 票
```

計畫是**預測不是承諾**。每波收完要重算。**重算結果與原計畫不同時不必問人**，把差異寫進波次交棒紀錄即可（第 6 步）。

計畫還有第二個用途：**它是第 4 步「提前做下一波前置」的依據**。沒有計畫就不知道要先建哪些 worktree。

### 用一次 AskUserQuestion 問完全部

一次問完，附推薦選項：

1. **波次計畫**：整份給他看，問要不要調整
2. **授權範圍**：連跑到收斂，還是跑到第 N 波為止
3. **`manualVerification` 設定**（見第 2 步第五件）
4. **base 分支與未提交改動的處置**（見第 2 步第一件）
5. **要不要升級 `--dangerously-skip-permissions`**（預設不要）

**問完就不要再問。**

### 授權書：只有這三種情況才停下來

| 停 | 不停 |
| --- | --- |
| pane 卡在**規格歧義**（票券本身講不清楚，補正兩次仍不達標） | pane 卡在權限提示 → 你放行並補白名單 |
| 閘門紅了而且**查不出原因**（不是 pane 造成的、也不是已知排除項） | 閘門紅了但看得出是 pane 的問題 → 回 pane 補正 |
| 需要**使用者親自動手**（Xcode 加 SPM、憑證、外部主控台） | 波次計畫與原本不同 → 記錄下來繼續跑 |

停下來時一次講清楚：卡在哪、你需要什麼、**其他還在跑的 pane 現在是什麼狀態**——使用者要能判斷該先處理這件事還是先讓其他票跑完。

---

## 2. 開工前置：五件事

**1. 確認 base 分支狀態。** `git status --short`。有未預期改動就在第 1 步那次 AskUserQuestion 一起問。保留是常見選擇，那就在整合時做 stash dance（見第 5 步）。

**2. 跑一次基準線驗證，當對照組。** 這一步省的時間最多：

> **設定檔宣稱的閘門狀態經常與現實脫節。** 實測案例一：某專案設定檔寫「13 支驗證腳本全部通過」，實際在乾淨的 base 分支上有 4 支是紅的。實測案例二：專案設定寫閘門是 `:composeApp:allTests`，但那個 task 含 iOS target，而 iOS 端缺一個必須由人在 Xcode 加的 SPM 套件，於是它永遠紅——實際可用的閘門是 `:composeApp:testDebugUnitTest`。

照設定檔把全部閘門掛上的後果是**每個 pane 都撞到不是自己造成的紅燈，白燒一整輪去追不存在的 bug**。派工指令裡只列當下實際會綠的，並明講排除了哪幾條、理由是什麼、不要去修。

**發現一次就寫進記憶**，否則每一波都要重新踩。

**這一步就用背景跑**（第 4 步的原則提前適用）：基準線閘門丟 `run_in_background`，同時去建 worktree。

**3. 建 worktree。** 分支名照專案慣例（多數專案是 `feat/{TICKET}`），目錄名用簡短票號。

**4. 補齊所有未進版控的檔案。** worktree 只帶 tracked 檔案，`.gitignore` 的一律不繼承。**Claude pane 特有的空洞：worktree 裡沒有專案層的 `.claude/` 與 `CLAUDE.md`**，而且會一起消失且都沒有錯誤訊息：

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

`node_modules` 用 `cp -Rc`（APFS clonefile）幾乎瞬間完成。複製完印確認表，並實跑一次輕量指令確認工具鏈可用。

**5. 決定人工驗收要怎麼開頁，並分配 port。** 讀專案 `.claude/linear-workflow.json` 的 `manualVerification` 區塊。**port 由你分配，不能讓 pane 自己挑**：`portBase + 波內序號`。兩個 pane 撞同一個 port 時，使用者看到的畫面會屬於錯的那張票——而那個畫面「看起來是對的」，是最難察覺的一種錯。

`nohup`、`open`、`curl` 在 `--permission-mode auto` 下可能撞權限提示，先補進 worktree 的 `.claude/settings.local.json` 白名單。專案沒有可開的頁面（純 CLI／library）就整段略過。細節見 `references/manual-verification.md`。

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

**`--permission-mode auto`**：分類器自動放行低風險指令，白名單在 worktree 的 `.claude/settings.local.json`。**不要預設用 `--dangerously-skip-permissions`**——pane 的 cwd 旁邊就是使用者的主 repo。只有使用者在第 1 步明確同意時才升級。

**`--add-dir <主 repo>`**：Claude Code 的工具存取限於 cwd 及其子目錄，而規格文件、reference 專案、報告經常在主 repo 的 gitignore 目錄裡。不加這個旗標，pane 讀不到，然後它會自己編一套規格。加了之後主 repo 對 pane 是**可讀也可寫**的，所以**指令裡必須明令「主 repo 只能讀」**。

### 指令模板

見 `references/pane-prompt.md`。v1 那些段落全部保留，**v2 要多寫進去的有兩段**：

- **閘門分層**（見下）——不寫的話 pane 會在每次小改動後跑完整測試，一張票就浪費掉十幾分鐘
- **完工訊號要明確**：`RESULT.md` 寫完落地才算完工。你一收到完工訊號就會立刻開始回收，此時 `RESULT.md` 還沒寫完，你會對著半份文件審碼

### 閘門分層

v1 的做法是每個 pane 每次驗證都跑完整閘門，主控 ff 之後再跑一次。在測試數量大的專案（數百個測試、Gradle／Xcode 這類冷啟動昂貴的工具鏈）這是主要的時間去處，而且**同一份測試被跑了兩次**。

| 階段 | 跑什麼 | 誰跑 | 驗的是什麼 |
| --- | --- | --- | --- |
| pane 內迭代 | 只跑**編譯／型別檢查** | 實作 pane，每次改動後 | 有沒有寫壞 |
| pane 完工前 | 完整測試套件一次 | 實作 pane，寫 `RESULT.md` 之前 | **這張票**對不對 |
| 每張 ff merge 後 | 只跑編譯 | 主控（背景跑） | 合進去有沒有編壞 |
| 整波合完 | 完整測試 + 比對斷言數 | 主控（背景跑） | **合併後的組合效應** |

**每一列驗的東西都不一樣，所以沒有一列可以省。** 特別是最後一列——那是 pane 各自驗不到的，各自綠不代表合起來綠。但它只需要一次，不是 N 次。

**斷言數比對只在最後那一次做，但一定要做。** 少了它，回歸會被「反正都綠」蓋過去；測試沒被執行也會 exit 0。

**這張表要照專案調整。** 判準是「這個階段最可能出現的錯，最便宜的偵測手段是什麼」。

---

## 4. 等待期：主控不閒著

這是 v2 收益第二大的一步。實測那 20 分鐘的閒置每一波都會出現。

### 先掛好完工通知

```
Monitor({
  command: 'for a in proj-111 proj-112 proj-113; do ( herdr agent wait $a --timeout 3000000 >/dev/null 2>&1 \
             && echo "[$a] 已離開 working — 去對帳" || echo "[$a] wait 逾時或出錯" ) & done; wait',
  description: 'Claude panes 完工通知',
  timeout_ms: 3600000, persistent: false,
})
```

不要 `sleep` 輪詢，也不要反覆讀畫面。`herdr agent wait` 不帶 `--until` 時會等 idle / done / blocked 任一。**先回報的先進第 5 步**，不要等全部。

### 然後做下一波的前置

依第 1 步的波次計畫，**現在就做下一波的第 2 步**：

| 現在可以做 | 為什麼不必等 |
| --- | --- |
| 建下一波的 worktree | 純 I/O，從當前 base 拉出去 |
| 複製 gitignored 檔案 | 同上 |
| 讀下一波票券的規格與上游解鎖註解 | 票已經在那裡了 |
| 寫下一波的派工指令草稿 | 只差「上一波的結論」那幾行，留空待填 |

**唯一要等的是「哪些票真的能進下一波」**，而波次計畫已經有預測值。**預測錯了頂多丟掉一個 worktree**——`git worktree remove` 一個指令，成本遠低於乾等 20 分鐘。

有兩件事**不要**提前做：把票推 `inProgress`（票還沒真的開工，看板會失真）、起 pane（base 還會前進，pane 會從舊基準開始）。

### 醒來第一件事：分辨「做完了」與「卡住了」

`--permission-mode auto` 下 `blocked` 是常態。**`wait` 返回不等於完工**，跑 `herdr agent list` 看實際狀態：

| 狀態 | 意義 | 動作 |
| --- | --- | --- |
| `idle` / `done` | 這一輪講完話了 | 讀 `RESULT.md` → 第 5 步。**沒有 RESULT.md = 沒做完**，回 pane 問 |
| `blocked` | 卡在權限提示或提問 | 見下 |
| `unknown` | Herdr 認不出來，**不代表完成** | `herdr agent read` 看畫面判斷 |
| 消失 | pane 被關 / 崩了 | 關 workspace、**留 worktree**、票退回 `states.todo` |

**`blocked` 的處理：** `herdr agent read proj-111 --source detection --lines 40` 看它在問什麼。**權限提示**：判斷該指令是否落在合理範圍 → 是就 `herdr agent send-keys` 放行，並**把該指令補進 worktree 的白名單**。**規格提問**：依授權書，**先補正兩次再決定要不要停下來問人**。

### 醒來第二件事：把人工驗收清單搬進對話

pane 完工時已經起好 dev server、把測試頁 `open` 在使用者的瀏覽器裡，並把清單寫進 `RESULT.md`。**原樣搬進對話**，不要摘要成「請驗一下訂單功能」。一波多票就標明哪個 port 屬於哪張票：

```
PROJ-111 訂單列表 → http://localhost:5173/orders （4 項，約 3 分鐘）
PROJ-112 設定頁   → http://localhost:5174/settings（3 項，約 2 分鐘）
```

**人工驗收是唯一不受授權書覆蓋的等待。** 授權你連跑多波，不等於授權你替使用者宣告畫面驗過了。使用者沒回覆就繼續跑下一波，但那些項目在票上一律標「未驗證」，並在收工回報列出還欠哪幾張。

---

## 5. 回收：分類讀、不阻塞、批次收尾

### 先看 worktree 實況，不要只讀 RESULT.md

```bash
git -C "$WT" log --oneline <base>..HEAD    # 有沒有 commit
git -C "$WT" status --short                 # 工作區乾淨嗎、有沒有誤 commit
git -C "$WT" diff --stat -M <base>...HEAD   # 改了什麼、範圍有沒有超出票券
```

### diff 要分類讀，不要整份吞

實測案例：一張純搬檔的票動了 387 個檔案，全部是 rename。主控把整份 diff 讀進 context，**燒掉 21%，而且讀了沒有資訊量**——rename 要確認的是「對應關係對不對」，不是「內容寫得好不好」。

```bash
git diff --stat -M <base>...HEAD                    # 先看形狀與比例
git diff --diff-filter=R -M --name-status <base>...HEAD  # 純 rename：只核對應
git diff --diff-filter=M <base>...HEAD              # 只有這部分逐行讀
git diff --diff-filter=A --name-only <base>...HEAD  # 新增檔：看清單 + 挑重點讀
```

機械式重構票（搬檔、改名、內聯）的 diff 有九成落在第一類。**分開處理，context 消耗差一個數量級。**

判斷 rename 是否忠實的方法不是讀 diff，是**抽樣比對**：挑三五個檔案跑 `git show HEAD:<新路徑> | diff - <(git show <base>:<舊路徑>)`，全部無差異就可以相信整批。

### 審碼：四項照做，加四項

`parallel-wave` 第 4 步那四項照做（看 diff 本身、看 log 實際結尾、確認測試真的執行過並數斷言數、確認 gitignored 檔沒被 commit）。再加四項：

| # | 加查什麼 | 判準 |
| --- | --- | --- |
| 5 | 超出票面範圍的改動是必要還是順手 | 判準不是「有沒有超出」而是「有沒有正當理由」。**驗證方式是逐行比對**——拆檔前後只差一個函式名就是忠實搬移，風險警示可以解除 |
| 6 | 落在**被排除閘門盲區**的改動 | 本工作流最大的結構性風險。改動落在你第 2 步排除的閘門本該覆蓋的範圍，那段程式碼就是**零執行期覆蓋**。親自讀碼推資料流，並在整合註解裡明講「這段沒有任何一次真實執行」 |
| 7 | 地基票的未驗證項 | 型別定義、共用演算法、核心 helper 錯了會污染所有下游，而錯誤形式往往是「編譯過、測試過、語意錯」。**pane 標未驗證而下游會直接踩到的，就是你該補測的那一項** |
| 8 | 對抗來源 | pane 是 Claude、你是 Claude、它的自審也是 Claude，**「它覺得對」與「你覺得對」高度相關**。至少用一個：**Codex 對抗複查**（地基票／演算法票／安全相關，明講「請證明這段是錯的」而不是「請 review」）、**執行證據取代判斷**（不問「這樣對嗎」，問「跑出來是什麼」）、**反向舉證**（讀 diff 時問「給我一組會讓它壞掉的輸入」，舉不出來才算過） |

**「RESULT.md 說驗收條件全過」的證據力很低**——它的判準和你的判準來自同一個分布。要嘛有執行證據，要嘛有異質來源背書，兩者皆無就標「未驗證」。

### 整合：rebase + fast-forward，一張一張來

```bash
git -C "$WT" rebase <base>
git -C "$MAIN" merge --ff-only <branch>
```

**這一段不能平行。** 兩個東西同時寫 base 分支會互相覆蓋，而覆蓋掉的內容不在任何一條分支上，事後找不回來。

**合併順序照第 1 步的風險分析**：低風險先進；共用檔的票**新增內容少的先合、多的 rebase 上去**。

**base 分支有未提交改動時的 stash dance**：`--ff-only` 不允許被合併動到的檔案帶有本地改動。

```bash
git stash push -m "<描述>" -- <只有那個衝突檔>
git merge --ff-only <branch>
git stash pop
```

只 stash 真正衝突的那個檔。pop 之後**實查使用者的改動是否完整還原**。

**共用檔的 add/add 衝突有個固定形狀**：兩張票都在檔尾同一個插入點追加，git 會把兩者共用的結尾行合在一起而報衝突。**解法是兩塊都保留、各自補回自己的結尾行**。解完後 `grep -c "^<<<<<<<\|^=======$\|^>>>>>>>"` 確認無殘留。

### 閘門丟背景，不在前景等

```bash
# ff 之後立刻丟出去，然後去做下一張的 rebase
./gradlew :composeApp:assembleDebug > /tmp/wave2-ff1.log 2>&1 &
```

用 `run_in_background`（或 Monitor）跑，**不要 foreground 等 Gradle**。一張票的編譯要幾分鐘，那幾分鐘足夠做完下一張的 rebase 與 ff。

**整波合完才跑完整測試**，同樣丟背景，然後你去寫這一波的 Linear 收尾。回報紅燈時的處置順序：先看是不是已知排除項 → 再看斷言數是否變少（**回歸訊號，最嚴重**）→ 再二分是哪一張票造成的。

**二分很便宜，因為每張票都是一個 ff commit**，`git bisect` 或逐個 `git reset --hard HEAD~1` 都能定位。

**只有「斷言數變少」時才必須停下來**——那代表 base 現在是壞的，繼續往上疊只會擴大污染面。其餘紅燈可以邊修邊往下走。

### Linear 收尾：整波批次做，不逐票做

v1 是每張票做完就推狀態 → 寫註解 → 查下游解鎖。下游查詢是 N+1 次 `get_issue`，而**三張票的下游經常重疊，逐票做會重複查同一張票**。

整波合完之後一次做完：

1. **一次讀完所有下游**：把這一波所有票的 `blocks` 併成一個集合去重，再逐一 `get_issue({ includeRelations: true })` 查它們自己的 `blockedBy`
2. **一次推完所有 Done**
3. **一次寫完所有註解**
4. **一次推完所有解鎖的 `todo`**

**唯一不能批次的是整合註解的內容**——每張票的複查發現不同，那要各寫各的。批次的是**呼叫次數**，不是內容。

### 整合註解

標題 `## 整合與複查（主控）`。它與 pane 的實作紀錄是兩份不同的東西：**pane 那則回答「當時是怎麼想的」，你這則回答「現在能不能信」。**

**你的職責是收斂、加註、修正 pane 的判斷，不是把 `RESULT.md` 重講一遍。** 正文照結論在前的順序：

| 順序 | 寫什麼 |
| --- | --- |
| 1 | **這張票現在是什麼狀態**：已進哪個分支、能不能信。一句話 |
| 2 | **我對 pane 判斷的修正**：哪裡它想錯了、我改了什麼。沒這段就只是複讀 |
| 3 | **複查抓到的真問題**：每條一行（抓到什麼 → 怎麼處置），用了哪個對抗來源一句帶過 |
| 4 | **人工驗收結果**：幾項、使用者實驗幾項、哪幾項不符與怎麼處置、哪幾項他沒驗 |
| 5 | **仍未驗證**：原樣保留 pane 標的未驗證項與使用者沒驗到的清單項 |
| 6 | 下游影響（有才寫） |

**這些一律進 `<details>` 摺疊區**：rebase 前後兩個 commit hash、逐條閘門結果與實際斷言數、被排除的閘門與理由、人工驗收清單全文、複查發現的逐條推導。

判準一句話：**讀者不追問「你怎麼知道」就不需要的東西，不該在正文。**

**解鎖註解是這個工作流的複利引擎，v2 尤其如此**——下一波是你自己開的，沒有人會在中間幫你補脈絡。要寫：現在可以直接用什麼（具體檔案路徑與匯出名稱、可以照抄的既有實作）、該避開的坑、上游有哪些未驗證項目。

### 收 worktree

**合併可以立刻做，`git worktree remove` 要等使用者回報驗收結果**——worktree 一刪，dev server 的 cwd 就消失、使用者手上的頁面當場壞掉。順序是：使用者回覆 → `kill $(cat <worktree>/.dev-server.pid)` → `git worktree remove` → `herdr workspace close <id>`。

使用者一直沒回就把 worktree 留著。**其餘不需要開頁的票（純 CLI／library）維持原則：合併完立刻收。**

---

## 6. 波次交棒：不問人，直接開下一波

v1 到這裡就結束了。v2 的迴圈在這裡繼續。

下一波的 worktree 與派工指令**在第 4 步已經備好了**，所以交棒只剩三件事：把上一波的結論填進派工指令的留白處、推 `inProgress`、起 pane。

### 寫一份波次交棒紀錄

寫到 `.claude/report/<日期>/wave-log.md`，**每波追加一段，不要覆蓋**：

```markdown
## 波 2（PROJ-12 / PROJ-13 / PROJ-17）

- 合併：3 張全進 <base>，ff commit a1b2c3d / e4f5g6h / i7j8k9l
- 閘門：457 tests / 0 failures，斷言數與基準線一致
- 複查抓到：PROJ-13 動了不在票面內的 3 個檔（判定為必要，逐行比對後只差函式名）
- 未驗證：PROJ-17 的畫面，使用者未回報驗收
- 與原計畫的差異：無
- 下一波：PROJ-14 / PROJ-15 / PROJ-16（worktree 已在波 2 期間建好），
  共用 UiState 的歸屬已由波 2 的 PROJ-13 決定，已填進派工指令
```

**這份紀錄有三個讀者**：使用者（他不在旁邊，這是他唯一的進度來源）、下一波的你（context 可能已被 compact）、接手的你（見下）。

### context 預算與主動交接

**每波結束檢查一次自己的用量。超過 60% 就主動交接，不要撐。**

撐下去的失敗形式很難看：auto-compact 會在半波中途發生，而那時你手上握著「哪張票已 ff、哪張還沒、哪個背景閘門還在跑」——這些全是壓縮時最容易被判定為過程細節而丟掉的東西，丟了之後你會重複 merge 或漏掉一張票。

交接的做法：把 `wave-log.md` 補到最新，然後起一個新的主控 pane，開場指令指向那份 log 與波次計畫。

**第 5 步的 diff 分類讀是 context 預算的主要手段**，先做好它，交接的頻率會低很多。

### 收斂

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
| 波次計畫變了就跑去問人 | 計畫本來就是預測。**記錄差異，繼續跑**——問人正是 v2 要消除的那件事 |
| 在 pane 寫程式的期間乾等 | 實測那是 20 分鐘，而且每一波都會出現。下一波的 worktree 與派工指令現在就能備好 |
| 提前把下一波的票推 `inProgress`，或提前起 pane | 票還沒真的開工，看板會失真；base 還會前進，pane 會從舊基準開始 |
| foreground 等 Gradle／Xcode 跑完 | 那幾分鐘足夠做完下一張的 rebase 與 ff |
| 把整份 diff 讀進 context | 實測 387 個檔的 rename 燒掉 21%，而且沒有資訊量。**分類讀** |
| 用讀 diff 來判斷 rename 是否忠實 | 抽樣跑 `git show` 比對三五個檔就夠，讀 diff 只是把同樣的內容看兩遍 |
| pane 跑過完整測試，主控 ff 後又跑一次同一份 | 那兩次驗的是同一件事。ff 後只需要編譯 |
| 反過來：整波合完那次完整測試也省掉 | 那一次驗的是**合併後的組合效應**，pane 各自驗不到，各自綠不代表合起來綠 |
| 逐票查下游解鎖 | 幾張票的下游經常重疊，逐票做會重複查同一張票。整波去重後一次查 |
| 斷言數變少還繼續開下一波 | base 現在是壞的，往上疊只會擴大污染面。這是唯一必須停的紅燈 |
| 把「使用者沒回驗收」當成驗收通過 | 授權你連跑多波，不等於授權你替他宣告畫面驗過了 |
| context 到 80% 才想交接 | auto-compact 會在半波中途發生，丟掉的正是「哪張已 ff、哪張還沒」這種過程狀態 |
| 不寫 `wave-log.md` | 使用者不在旁邊，那是他唯一的進度來源；你自己被 compact 之後也靠它復原 |
| **多開 reviewer / verifier pane 來加速** | 它們也是 Claude，讀 diff 一樣要五分鐘，而你合併只要兩分鐘——小波次時你反而要等它。試過了，是淨損失 |

---

## 參考檔

- `references/pane-prompt.md` —— 實作 pane 派工指令模板，逐段說明為什麼要有那一段
- `references/manual-verification.md` —— 完工開頁、port 分配與 server 生命週期、STE100 寫法的人工驗收清單模板
- `references/herdr-runtime.md` —— 已實查的 `herdr` CLI 契約與 Claude pane 特有的旗標
- `herdr-claude-wave`（同 plugin）—— 單波審慎版，每波停下來確認
- `parallel-wave`（同 plugin）—— 共用的盤點、前置、整合原則
- `herdr-codex-wave`（同 plugin）—— 換成 Codex 當實作者的版本
