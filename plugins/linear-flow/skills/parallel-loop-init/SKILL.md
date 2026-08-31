---
name: parallel-loop-init
description: "把專案接上『並行 Linear loop』的 Herdr 版：先跑 doctor 診斷環境缺口（Herdr session 與 claude integration、兩個 skill 與腳本、主 repo 基準線乾淨、gitnexus 索引、codex CLI 實跑白老鼠、Playwright E2E 基建、worktree 根目錄與 port 區段、權限白名單、殘留現場對帳、parallel-loop.json），列出缺口讓使用者確認後一次補齊，收尾輸出開跑前檢查表。Use this whenever the user wants to set up or verify the parallel multi-agent Linear loop for a project, diagnose why the parallel loop won't start, re-verify the codex companion path after a plugin upgrade, or check whether the Playwright E2E infrastructure is ready for parallel testing. Triggers: \"初始化並行 loop\", \"parallel loop doctor\", \"檢查並行環境\", \"並行 loop 缺什麼\", \"設定多線 goal loop\", \"herdr loop 環境檢查\", \"set up the parallel linear loop\", \"diagnose parallel loop setup\", \"why won't the parallel loop start\". 帶參數 doctor 時只診斷不寫檔。"
---

# parallel-loop-init

> **⚠️ 主體已移除。** 本 skill 原本是為 `parallel-loop` 做環境 doctor 的，而 `parallel-loop` 已從本 plugin 刪除（連同 `scripts/wait-any.sh`）。因此**檢查 `${CLAUDE_PLUGIN_ROOT}/skills/parallel-loop/` 的那幾項一定會失敗，那是預期的，不是環境缺口**——跳過它們即可。其餘檢查（worktree 根目錄、port 區段、權限白名單、gitnexus 索引、E2E 基建、`.claude/parallel-loop.json`）對 `herdr-claude-wave` / `herdr-codex-wave` / `parallel-wave` 仍然適用。

把當前專案接上**並行 Linear loop（Herdr 版）**。先診斷、列缺口、等使用者確認，再一次補齊。

這是**機械式 SOP**。不要重新談判設計決策——水位、配額、收斂條件那些已經在 `.claude/parallel-loop.json` 裡定案了，使用者要改會自己去改那個檔。唯一該問使用者的是 § 問使用者 那幾件事。

> **架構前提**：這個 loop 現在跑在 **Herdr** 上，每張票一個 workspace + git worktree + 獨立的 Claude Code pane。主 Agent（`parallel-loop` skill）負責派發與 ff merge，實作 pane（`parallel-ticket` skill）負責 dev → codex review → test → rebase。
>
> 舊的 Workflow 版（`.claude/workflows/parallel-linear-loop.mjs`）是**同一套流程的另一個實作**。兩套共用 `.claude/parallel-loop.json`，但**不要同時跑** —— 它們會搶同一批 worktree 與 port。

> 這個 skill **不負責 Linear 的基礎設定**。team、六個狀態欄、`api-require` label 那些由 `linear-workflow-init` 管。本檔第 1 項只確認那份設定存在，缺了就叫使用者先去跑那個 skill——兩份 Linear 檢查邏輯一旦並存就會漂移，而漂移的症狀是靜默推錯狀態欄。

## 兩種呼叫

| 呼叫 | 行為 |
| --- | --- |
| 無參數 | doctor 掃描 → 列缺口表 → 問使用者要不要補 → 安裝 → 輸出開跑前檢查表 |
| 帶 `doctor` | **只輸出缺口表，一個檔都不寫**。使用者想先看現況再決定。 |

帶 `doctor` 時要守住「不寫檔」，**包括第 6 項那個 codex 白老鼠測試也不要跑**（它會在 tmp 建檔、會消耗 codex 額度）。使用者刻意用了唯讀模式，順手幫他做事是幫倒忙。

## 做完之後，環境長什麼樣

```
<linear-flow plugin>/skills/               # 裝在 user scope，跨專案共用
                                           # 路徑用 ${CLAUDE_PLUGIN_ROOT}/skills/ 取得
├── parallel-loop/
│   ├── SKILL.md                           # 主 Agent：派發 + ff merge
│   └── scripts/wait-any.sh                # 背景喚醒（等價 Promise.race）
└── parallel-ticket/
    ├── SKILL.md                           # 實作 pane：dev → review → test → rebase
    └── scripts/stage-lock.sh              # mkdir 階段配額鎖

<專案根>/.claude/                           # 設定與狀態留在各專案
├── parallel-loop.json                     # 水位、配額、port、衝突規則、命令
├── parallel-loop-state/                   # 結果檔與階段鎖（執行期產生）
├── settings.local.json                    # permissions.allow 白名單
├── linear-workflow.json                   # 既有，不動
└── linear-workflow.md                     # 既有，不動（兩套 loop 共用這份 Linear 行為規則）
```

單線的 `linear-goal-loop` skill 原封不動保留，當並行環境壞掉時的退路。

---

## doctor：十二項檢查

依序跑。每項用 ✅ 已備 / ❌ 缺 / ⚠️ 需人工處理 標記，最後彙整成一張表輸出。

### 1. Linear 工作流設定存在

`.claude/linear-workflow.json` 要存在，且 `states` 六個核心欄都不是 `null`。

缺了或有 `null` → **停下來，叫使用者先跑 `linear-workflow-init`**。不要自己補，不要挑一個相近的狀態欄硬填。

### 2. Herdr 環境

```bash
test "${HERDR_ENV:-}" = 1        # 你必須在 Herdr 管理的 pane 裡
command -v herdr                 # 二進位檔在 PATH 裡
herdr agent list                 # server 答得出話
herdr integration install claude # claude kind 已註冊（重跑是冪等的）
```

- **`HERDR_ENV` 不是 1 → blocker。** 整個架構靠 Herdr 開 pane，不在 Herdr 裡就不成立。這時**不要**建議改用舊的 Workflow 版當替代 —— 那是另一套架構，混用會兩邊都亂。
- `herdr agent list` 呼叫失敗 → server 沒起來。叫使用者跑 `herdr` 開 session。
- `claude` integration 沒裝 → `herdr agent start --kind claude` 起不來，也認不出 agent 狀態，`wait-any.sh` 會永遠等不到喚醒。

### 3. 兩個 skill 與腳本就位

```bash
ls ${CLAUDE_PLUGIN_ROOT}/skills/parallel-loop/SKILL.md
ls ${CLAUDE_PLUGIN_ROOT}/skills/parallel-ticket/SKILL.md
test -x ${CLAUDE_PLUGIN_ROOT}/skills/parallel-loop/scripts/wait-any.sh
test -x ${CLAUDE_PLUGIN_ROOT}/skills/parallel-ticket/scripts/stage-lock.sh
bash -n ${CLAUDE_PLUGIN_ROOT}/skills/parallel-loop/scripts/wait-any.sh
bash -n ${CLAUDE_PLUGIN_ROOT}/skills/parallel-ticket/scripts/stage-lock.sh
```

**缺執行權限就 `chmod +x`**（這是安全的寫入）。skill 檔本身缺了是 blocker，不要自己重寫。

順手驗一次階段鎖真的能運作（**這一項連 `doctor` 模式也可以跑，它只在 state 目錄下建再刪一個目錄，不消耗任何額度**）：

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/parallel-ticket/scripts/stage-lock.sh acquire smoke 1 DOCTOR --wait-min 0
bash ${CLAUDE_PLUGIN_ROOT}/skills/parallel-ticket/scripts/stage-lock.sh release smoke DOCTOR
```

### 4. 主 repo 基準線乾淨

```bash
git status --porcelain
git rev-parse --abbrev-ref HEAD
```

要求：工作區完全乾淨，且目前在 `parallel-loop.json` 的 `baseBranch` 上。

**這是最常見的缺口，也是唯一一個不乾淨就絕對不能開跑的。** 所有 worktree 都從 baseBranch 的 HEAD 長出來；工作區有未 commit 的變更，代表這些改動不在任何一條票分支的基準線裡，而它們最後仍會跟合併進來的票撞在一起。

不乾淨時**不要自己 commit**。列出檔案清單，問使用者這批屬於哪張票、要 commit 還是 stash（見 § 問使用者 Q1）。

### 5. gitnexus 已掛上且索引新鮮

- `mcp__gitnexus__*` 工具可用。gitnexus 通常掛在 user scope（全域 CLI），**不在專案的 `.mcp.json` 裡——不要去改 `.mcp.json`**。工具不可用才去查 `gitnexus setup`。

- `gitnexus status` 要顯示這個 repo 已索引。沒有就跑：

  ```bash
  gitnexus analyze --skip-agents-md
  ```

  **`--skip-agents-md` 是必要的**：預設行為會改寫 `AGENTS.md` 與 `CLAUDE.md`，那是追蹤檔，會弄髒工作區。
  同時確認 `.gitnexus/` 已被忽略——寫進 `.git/info/exclude`（本地專屬，不動追蹤中的 `.gitignore`）。

- 索引新鮮度：用 `mcp__gitnexus__detect_changes` 看落後幾個 commit，超過 `gitnexus.staleAfterCommits` 就要重建。

索引是派發時的衝突預測主判準（主 Agent 只對排序後的前 3 名候選跑 `impact`），索引過時等於預測失效，會讓衝突全部落到 ff merge 才爆。

### 6. codex CLI 實跑白老鼠

**這一項會真的跑一次 codex review，不是只檢查檔案存在。**

理由：「codex 裝了」跟「`--wait` 在這台機器上真的會回傳合法 JSON」是兩回事。背景執行缺 PATH、plugin 版本升級改了路徑、額度用完——這些的症狀都是回傳空字串，而 loop 會把空字串當成「沒有 finding」放行。跑了五路才發現全部 review 都是空的，一整晚就報廢了。

步驟：

1. 用 glob 解析實際路徑：`~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs`。
   找到的路徑跟 `parallel-loop.json` 的 `codex.companionPath` 不一致就更新設定（版本號會隨套件升級改變）。
2. 在一個 tmp worktree 裡造一個微小的假 diff（改一行註解就好），**用設定檔的 `codex.reviewArgs` 原樣跑**：
   ```bash
   node "<companionPath>" <codex.reviewArgs>
   ```
   **子指令必須是 `adversarial-review`，不是 `review`。** `review` 走 native reviewer，只回自由文字，`payload` 裡沒有 `result`、沒有 `severity` —— `blockingSeverities` 會靜默全放行，等於整個 review 閘門形同虛設。設定檔已經是對的，白老鼠測試若用別的參數，測到的就不是實際會跑的那條路徑。
3. 輸出必須能解析出 `payload.result`，形狀是 `{ verdict, summary, findings[], next_steps[] }`，且 `payload.parseError` 是 null。
4. 記下這次耗時，寫進報告——那是估算 review 階段吞吐的唯一依據。
5. 清掉 tmp worktree。

失敗就是 blocker，不要「應該沒問題吧」放行。

### 7. Playwright E2E 基建

照 `parallel-loop.json` 的 `e2eInfra` 逐項檢查 `baseBranch` 上：

- `requiredPaths` 每個檔案都在
- `package.json` 的 scripts 有 `requiredScripts` 列的每一條
- `requiredDeps` 都在 devDependencies

`e2eInfra.enabled` 為 `false` 時整段跳過，不當 blocker（測試階段會把 `automated` 條件降級成讀碼核對或人工項）。

不齊備時**不要自己裝**。到 Linear 找那張 Playwright 基建票（標題含 Playwright 或 E2E 基建）：

- 找到 → 標記 ⚠️，在報告寫明「開跑時主 Agent 會讓它獨占流水線先跑完，期間並行度為 1」。這不是 blocker。
- 找不到 → **是 blocker**。基建必須有票承載驗收條件並留下實作紀錄註解，不能無票施工。這時建議使用者用 `grill-to-linear` 或直接開一張，票的交付內容照設定的 `requiredPaths`。

### 8. worktree 與 Herdr 現場對帳

新架構下「殘局」有**兩種資源**，而且可能不同步。三個指令一起看：

```bash
git worktree list
herdr worktree list
herdr agent list
```

對每個殘留資源查它對應的 Linear 票狀態（目錄名就是票號），照下表判定：

| worktree | Herdr pane | 票在非終態 | 判定 |
| --- | --- | --- | --- |
| 在 | 無 | 是 | ✅ **正常重入現場**，不是缺口。開跑時主 Agent 會 `herdr worktree open` 接手續做 |
| 在 | working | 是 | ⚠️ **有 agent 還在跑**。列出來告訴使用者；開跑時主 Agent 會熱接管，不會重派 |
| 在 | idle | 是 | ⚠️ 做完了沒人收。檢查 `.claude/parallel-loop-state/<票>.attempt-*.json` 在不在 |
| 在 | 任意 | **否**（終態或查不到） | ❌ **孤兒**。列出來問使用者，**不要自己刪**——可能是刻意保留的失敗現場 |
| 無 | 有 | — | ❌ 孤兒 pane。列出來，**不要自動關**（可能是使用者自己開的） |

> **「有殘留 worktree」本身不是 blocker。** 舊版把所有殘留一律判 blocker，於是重入機制永遠觸發不了——票被退回 Todo 等重跑，而 loop 因為它的 worktree 還在就啟動不了，死鎖。判準是**票的狀態**，不是資源存不存在。

另外兩項：

- `worktreeRoot` 目錄可建立（不存在就建，這是安全的）。
- `worktreeRoot` 有沒有被忽略。它通常設在 repo 外（`../<repo>-wt` 之類），所以不用管；若使用者改成 repo 內就要確認 ignore。

**還要檢查 agent 名稱衝突**：Herdr 的 agent 名在**存活的 agent 之間必須唯一**。上一輪殘留的 `proj-xx` 還活著時，這一輪 `herdr agent start proj-xx` 會直接失敗。有這種情況就列進報告。

### 9. port 區段可用

從 `portBase` 起算 `waterline` 個 port 都沒被佔用。**port 範圍要從設定檔算，不要寫死**：

```bash
lsof -nP -iTCP -sTCP:LISTEN | awk '{print $NF}' | grep -oE ':[0-9]+$'
```

比對 `portBase` … `portBase + waterline - 1`。有被佔用的 → 問使用者要關掉還是換 `portBase`（Q3）。

### 10. 權限白名單

實作 pane 是**獨立的 Claude Code session**，不繼承你的 permission mode。撞到權限提示時 Herdr 會回報 `blocked`，主 Agent 得醒來處理——偶爾一次可以，每張票好幾次就會把主 Agent 的 context 燒光。

檢查 `.claude/settings.local.json` 的 `permissions.allow` 至少涵蓋：

- `commands.verify` 的每一條（或用 `npm run verify:*` 這類前綴）
- `commands.dbSetup`、`commands.e2e`
- git 子命令：`status` / `log` / `diff` / `add` / `commit` / `fetch` / `rebase` / `merge-base` / `reset --soft` / `rev-parse` / `branch`
- `node <codex.companionPath>`
- 兩支 skill 腳本的**絕對路徑**（skill 在 user level，寫專案相對路徑會對不上）
- `herdr`、`mkdir`、`rmdir`、`cp`

缺了就補（這是安全的加法寫入）。**同時確認主 Agent 起 pane 時會帶 `--permission-mode auto`** —— 那是白名單沒涵蓋到的雜項的第二道防線。

### 11. 狀態目錄

`.claude/parallel-loop-state/` 可建立可寫。**不需要另外加 gitignore** —— 多數專案整個 `.claude/` 已經被忽略了；先確認，真的沒被涵蓋才加。

順便看有沒有**孤兒階段鎖**：`.claude/parallel-loop-state/locks/` 底下的鎖若持有超過 45 分鐘，代表上一輪有 pane 崩在半路。腳本會自動回收，但列進報告讓使用者知道上次跑得不順。

### 12. 資源與設定一致性

- 核心數：`sysctl -n hw.ncpu`（macOS）或 `nproc`。
  `quotas.test` 若大於 `floor(核心數 / 4)` 就 ⚠️ 警告——每個 test agent 要 build + dev server + chromium，超配會讓單票測試時間反而變長。
- `quotas.dev` 不該超過 `waterline`。
- **`waterline` 現在的上限是機器資源，不是 Workflow 的並行上限**（那個限制已經不存在了）。但每張票是一個完整的 Claude Code session + 一個 worktree + 可能的 dev server，記憶體是實際瓶頸：`waterline × 約 2–3 GB` 若逼近實體記憶體就 ⚠️ 警告。
- `records` 列的檔案路徑，全部要出現在 `protectedPaths` 裡。漏了就補——那是防止實作 pane 寫紀錄檔造成每條分支尾端衝突的唯一防線。
- `progressComments` 為 true 時提醒使用者：每票會多三則 Linear 註解（由實作 pane 自己寫）。

---

## 問使用者

只有這幾件事需要問，其餘一律照設定檔跑。用 `AskUserQuestion`，每個問題都要有一個標「(推薦)」的選項。

**Q1（只在第 4 項不乾淨時問）**：主 repo 有未 commit 的變更，怎麼處理？
- commit 進 baseBranch（推薦）——先讀 diff 判斷它屬於哪張票、能不能過 `commands.verify`，並回報給使用者
- stash 起來
- 中止 doctor，使用者自己處理

**Q2（只在第 8 項有孤兒資源時問）**：這些 worktree / pane 要保留還是清掉？逐一列出對應的票號、票狀態、分支與最後 commit 讓使用者判斷。**正常重入現場不要問**——那是設計行為，問了只會製造誤刪的機會。

**Q3（只在第 9 項 port 被佔用時問）**：關掉佔用的 process，還是改 `portBase`？

**Q4（所有缺口都列完後）**：要現在補齊嗎？列出即將發生的每一個寫入動作再問。

---

## 輸出：開跑前檢查表

所有項目 ✅ 之後，輸出一張表告訴使用者接下來會發生什麼：

```
並行 Linear loop（Herdr 版）已就緒

  基準線      <baseBranch> @ <commit>
  候選票      <n> 張（其中 <m> 張 blockedBy 未清，不會被派）
  水位        <waterline> 張同時在飛 → <waterline> 個 Herdr workspace
  階段配額    review <n> / test <n>（mkdir 檔案鎖）｜merge 串行（主 Agent 獨佔）
  port        <portBase>–<portBase + waterline - 1>
  worktree    <worktreeRoot>/<票號>
  codex       單次 review 約 <t> 秒（白老鼠實測）
  重入現場    <k> 個（開跑時會接手續做，不是從頭重來）

  ⚠️ Playwright 基建票 <票號> 尚未完成，開跑後會獨占流水線先跑完

  成本量級    <waterline> 個並行的 Claude Code session，加上主 Agent
              每張票約 1–3 次主 Agent 喚醒（背景等待期間不燒 context）

啟動：說「開始並行 loop」，或 /parallel-loop [--hours N]
```

**成本量級一定要講，而且要講清楚它跟舊版不一樣。** 舊的 Workflow 版是「20 張票 × 4 個 subagent ≈ 80 個 agent」；Herdr 版是「同時 `waterline` 個**完整的 Claude Code session**」——單位不同，前者是短命子 agent，後者是各自帶完整 context 的獨立行程。使用者有權在按下去之前知道這個差別。

---

## 這個 skill 不做的事

| 不做 | 為什麼 | 誰做 |
| --- | --- | --- |
| Linear team / 狀態欄 / `api-require` label 的設定 | 兩份實作會漂移，症狀是靜默推錯欄 | `linear-workflow-init` |
| 安裝 Playwright 基建 | 需要驗收條件與實作紀錄註解，不能無票施工 | 那張基建票，由主 Agent 獨占跑 |
| 刪除殘留 worktree、關掉殘留 pane | 可能是刻意保留的失敗現場，或使用者自己開的 | 使用者裁決（Q2） |
| commit 主 repo 的髒變更 | 得先知道它屬於哪張票、完不完整 | 使用者裁決（Q1） |
| 修改 `waterline` / `quotas` 等調校值 | 那是設計決策，不是環境問題 | 使用者自己改 `parallel-loop.json` |
| 改寫兩個 skill 的內容 | 那是規則本體，要改得使用者在場 | 使用者 |
