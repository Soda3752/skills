# soda-skills

個人常用的 Claude Code skill 集散地。用官方 plugin marketplace 機制發佈，換機器時一次裝好。

## 安裝

在任何一台裝好 Claude Code 的機器上：

```
/plugin marketplace add Soda3752/skills
/plugin install workflow-init@soda-skills
/plugin install jira-flow@soda-skills
/plugin install linear-flow@soda-skills
/plugin install report-tools@soda-skills
/plugin install kmp-architecture@soda-skills
/plugin install agent-fleet@soda-skills
```

之後要更新：

```
/plugin marketplace update soda-skills
```

## 有哪些 plugin

| Plugin | 內容 | 適合誰 |
| --- | --- | --- |
| `workflow-init` | `jira-workflow-init`、`linear-workflow-init`、`gitnexus-init`、`obsidian-init`、`parallel-loop-init` | 常開新專案、需要固定流程接上外部系統 |
| `jira-flow` | `grill-to-jira`、`check-jira-status`、`jira-goal-loop` | 已接上 Jira，日常要開票、盤點看板，或想讓 loop 自己把票做完 |
| `linear-flow` | `grill-to-linear`、`check-linear-status`、`linear-goal-loop`，加上五個平行開發 skill：`parallel-wave`、`codex-wave`、`herdr-codex-wave`、`parallel-loop`、`parallel-ticket` | 同上，但票在 Linear。與 `jira-flow` 平行，可同時裝 |
| `report-tools` | `pm_report`、`whats-new` | 需要把調查結果或版本差異交付給非工程角色 |
| `kmp-architecture` | `kmp-mvvm-architecture` | 寫 Kotlin Multiplatform，想把專案統一到同一套 MVVM 架構 |
| `agent-fleet` | `init_telegram_agent` | 想在一台機器上養一群透過 Telegram 溝通的 Claude Code agent |

`jira-workflow-init` 的預設值放在 `plugins/workflow-init/skills/jira-workflow-init/config/defaults.env`，裡面的站台與 project key 是佔位符，裝完請先改成自己的。文件裡的 `PROJ` / `ACME` 是兩個真實專案的匿名代號。

`linear-flow` 是 `jira-flow` 的 Linear 版，行為刻意保持平行，但**不是換個名字的複製品**——兩邊資料模型差很多：Linear 沒有 transition id（狀態任意互轉，一律送 state id）、阻塞關係是 `save_issue` 的一級參數但**只能靠 `get_issue` 逐張讀**（`list_issues` 不回傳，成本是 N+1）、`labels` 是整組取代語意（不先讀就送會清光既有標籤）、`includeArchived` 預設 `true`。這些差異寫在 `linear-workflow-init/references/linear-workflow.md` 的地雷表與各 skill 內。預設值在 `plugins/workflow-init/skills/linear-workflow-init/config/defaults.env`，裝完先改 `DEFAULT_TEAM`。

Linear 預設 team 只有 `Backlog / Todo / In Progress / Done / Canceled / Duplicate`，這套工作流還需要 `In Review` / `Blocked` / `API Require`（goal loop 另需 `PENDING`）。**MCP 沒有建立狀態欄的工具**，`linear-workflow-init` 會偵測缺哪幾欄並給手順，但得你自己去 Linear 建。

### 平行開發那五個 skill 差在哪

`linear-flow` 底下除了「開票 / 盤點 / goal loop」三支，還有五支處理**同時做多張票**的 skill。它們的共同骨架都一樣——每張票一個 git worktree，Claude 不寫業務程式碼，只做盤點派工、審碼把關、`rebase` + fast-forward 序列整合、以及全部的 Linear 狀態與註解。差別只在「誰在 worktree 裡實作」和「你看不看得見它在做什麼」：

| Skill | 實作者 | 過程可見性 | 外部依賴 | 什麼時候選它 |
| --- | --- | --- | --- | --- |
| `parallel-wave` | Claude subagent | 看不到，只看回收結果 | **無**（只用內建 Agent tool） | 預設選這個。沒裝任何東西也能跑 |
| `codex-wave` | Codex CLI 背景 job | 看不到 | `codex` CLI + `openai-codex` plugin | 想讓 GPT-5 寫實作，但不需要盯過程 |
| `herdr-codex-wave` | Codex CLI，跑在 Herdr pane 裡 | **看得見、能 attach、能中途插話** | `HERDR_ENV=1` + `codex` CLI | 想在旁邊看著 Codex 做，隨時能打斷 |
| `parallel-loop` | Claude，跑在 Herdr pane 裡 | 看得見、能 attach | `HERDR_ENV=1` | 要**無人監督地清空整個看板**，而不是做完指定的一波就停 |
| `parallel-ticket` | —— | —— | —— | 不由你觸發。它是 `parallel-loop` 派進每個 pane 的單票 SOP（dev → codex 對抗式 review → 驗證 → rebase → 等主 Agent 合併） |

前三個是「**一波**」語意：你指定一批票，做完整合完就停，要不要開下一波由你決定。`parallel-loop` 是「**一直做**」語意，會自己補位下一張票直到看板收斂——所以它跟 goal loop 一樣屬於無人監督寫程式的範疇，同樣的安全前提適用（見下一段）。

`parallel-loop-init` 放在 `workflow-init` 而不是 `linear-flow`，理由跟其他 `*-init` 一致：它是**一次性的環境 doctor**，不是日常工具。它檢查 Herdr session 與 claude integration、兩個 skill 與腳本、主 repo 基準線乾淨、gitnexus 索引、`codex` CLI 實跑白老鼠、Playwright E2E 基建、worktree 根目錄與 port 區段、權限白名單、殘留現場對帳——列出缺口讓你確認後一次補齊。並行環境的失敗多半是靜默的（pane 起來了但搶不到 port、worktree 建了但基準線本來就髒），先跑一輪 doctor 比事後從一堆 pane 裡回推便宜得多。

`herdr-codex-wave` 與 `codex-wave` 有一條共同的分工紅線值得先知道：**Linear 的狀態與整合註解一律由 Claude 寫，不交給 Codex。** Codex 讀得到 Linear MCP（所以票的內容由它自己讀），但讓它同時具備「改程式」和「改看板」兩種權限，出錯時你會分不清看板反映的是真實進度還是 Codex 的樂觀回報。

同一個專案不要同時 import `jira-workflow.md` 與 `linear-workflow.md`——兩份規則對「更新票券」的預設含義都有定義，會直接打架。`linear-workflow-init` 偵測到這種情形會停下來問。

`jira-goal-loop`、`linear-goal-loop` 與 `parallel-loop` 會**在無人監督下寫程式並 commit**，裝了都不會自動啟動——要由使用者明確帶起來（前兩個用 `/loop`，`parallel-loop` 要有 `HERDR_ENV=1`）。兩個 goal loop 各自讀 `<專案>/.claude/jira-workflow.json` 或 `linear-workflow.json` 的 `goalLoop` 區塊決定每輪跑哪些驗證指令，所以那個區塊等於「授權它在本機執行什麼」：**第一次在某個專案跑之前，人眼看過那幾條指令**，不要因為 clone 下來的 repo 附了一份設定就照跑。skill 的「資安紅線」一節寫了完整約束（不 push、不改自己的規則檔、不 commit 憑證、貼進票券前先遮敏感值）。`parallel-loop` 同理，只是設定檔換成 `.claude/parallel-loop.json`，而且它多了一層：pane 裡的 Codex 是 Yolo Mode，跑之前先讓 `parallel-loop-init` 的 doctor 確認權限白名單與 worktree 根目錄是你預期的。

`agent-fleet` 和其他 plugin 性質不同：它是**設計與維運參考，不是裝了就能跑的工具**。它描述的那套 `~/agents/scripts/*`（`new-agent.sh`、`launch-agent.sh`、`seed-telegram-plugin.sh`…）沒有一起發佈，要自己寫。收錄它的價值在於那些踩過才知道的坑——例如手工安裝 plugin 時漏了 `known_marketplaces.json` 的 `installLocation`，Claude 會**完全不載入該 plugin 且不留任何錯誤訊息**。各機器自己的主機事實（agent 名冊、工具絕對路徑、bot handle）放在 `hosts/`，只有 `hosts/EXAMPLE-host.md` 骨架進版控，理由見下方「這個 repo 不收什麼」。

各 plugin 底下每個 skill 的觸發條件寫在自己的 `SKILL.md` frontmatter，Claude 會自行判斷何時載入，不需要手動呼叫。

## 目錄結構

```
.
├── .claude-plugin/
│   └── marketplace.json          # 宣告有哪些 plugin
├── plugins/
│   └── <plugin>/
│       ├── .claude-plugin/plugin.json
│       └── skills/<skill>/
│           ├── SKILL.md          # 觸發條件寫在 frontmatter
│           ├── references/       # 需要時才讀的深入說明（選用）
│           └── hosts/            # 每台機器的事實；只發 EXAMPLE 骨架（選用）
├── docs/
│   └── third-party-sources.md    # 不 vendor 的第三方來源清單
└── scripts/
    ├── sync-from-local.sh        # 從 ~/.claude/skills 搬進來
    ├── anonymize.sh              # 抹掉 jira 的真實值（sync 會自動呼叫）
    ├── .anonymize-map.json       # 真值對照表，不進版控
    ├── .anonymize-map.example.json
    └── check-secrets.sh          # 公開前掃內部資訊
```

## 維護流程

skill 平常還是在 `~/.claude/skills/` 底下改（改完即時生效，不用重裝）。要發佈時：

```bash
./scripts/sync-from-local.sh     # 依 SKILL_MAP 同步 + 自動匿名化
./scripts/check-secrets.sh       # 掃站台網域、票號、絕對路徑（含 Windows 形式）、email、token
git diff                         # 人眼再看一次
git commit && git push
```

`sync-from-local.sh` 裡的 `SKILL_MAP` 就是收錄清單，唯一的真實來源。**例外是 `agent-fleet`**，它不走這條線——見下方「兩種分岔，兩種處理」。

第一次 clone 到新機器時，要先建對照表才能跑 sync：

```bash
cp scripts/.anonymize-map.example.json scripts/.anonymize-map.json
# 填入自己的真實站台與 project key
```

沒有這個檔案時 `anonymize.sh` 會直接失敗而不是默默跳過——默默跳過的後果是把真值留在工作區。

### 兩種分岔，兩種處理

有兩個 skill 的 repo 版與本機版是**刻意分岔**的，但分岔的性質不同，所以處理方式也不同。

**一、值不同 → 自動匿名化（Jira 側與 Linear 側）**

本機用的是真實 Jira 站台與 project key、真實 Linear team 前綴與 handle（不然它們日常跑不動），repo 是公開的。檔案結構完全一樣，差別只在幾個字串。

涵蓋範圍寫在 `anonymize.sh` 的 `TARGET_DIRS`：Jira 側是 `jira-workflow-init`、`check-jira-status`、`jira-goal-loop`；Linear 側直接指**整個 `plugins/linear-flow` 目錄**加上 `linear-workflow-init`、`parallel-loop-init`。Linear 側之所以整包指定而不逐個 skill 列，是因為票號（`PROJ-93` 這種）散落在每個 skill 的範例、腳本 docstring 與 pane 指令樣板裡——逐個列的話，新增一個 skill 忘了加進表的後果是靜默的：sync 把真實票號搬進來，anonymize 走不到，要等 `check-secrets.sh` 才攔下。

`sync-from-local.sh` 用 `rsync --delete` 單向覆蓋，所以每次同步都會把真值帶回來。`anonymize.sh` 就掛在同步的最後一步自動抹掉，不依賴人記得手動改。它是冪等的，重複跑不會有副作用；如果上游檔案改到讓它找不到插入錨點，它會直接報錯而不是默默跳過。

**二、結構不同 → 退出同步線，人工維護（`init_telegram_agent`）**

這個不是換幾個字串就能發佈的。本機版有一整個 `hosts/<真實主機>.md` 目錄，記著各機器的 agent 名冊、工具絕對路徑、bot handle——那等於一台**停用權限確認在跑 agent** 的機器的完整配置圖。公開版根本不該有這些檔案，只發 `hosts/EXAMPLE-host.md` 骨架。

`anonymize.sh` 解的是「同一份檔案裡的值要換掉」，這裡的問題是「整個目錄不該存在」，`rsync --delete` 只會把真實 `hosts/` 原封不動帶回來。所以它**不列入 `SKILL_MAP`**，公開版由人工維護。（另一個現實原因：它住在 project scope 的 `~/agent/.claude/skills`，`sync-from-local.sh` 的 `SRC` 本來就掃不到。）

代價是要記得兩邊都改。架構層（`SKILL.md`、`references/`）的改動兩邊要同步；`hosts/` 的改動只留在本機。

**其他 skill 不該走這兩條路。** 發現內容有問題就改 `~/.claude/skills/` 的源頭，下次 sync 自然帶進來——分岔規則每多一條，就多一個「本機明明改了、repo 卻沒生效」的坑。

真值對照表放在 `scripts/.anonymize-map.json` 且不進版控。**對照表就是解碼表**——把「真實 project key → `PROJ`」這種映射 commit 上公開 repo，等於附一份還原說明書，匿名化整個白做。`check-secrets.sh` 也從這個檔案讀專案專屬樣式，所以兩支腳本本身都不含任何真實值。

改動 skill 內容後記得把該 plugin 的 `version` 往上加，其他機器 `/plugin marketplace update` 才知道有新版。

## 這個 repo 不收什麼

- **第三方 skill**：從別的 marketplace 裝的（官方、mattpocock、pm-skills…）不 vendor 進來，只在 `docs/third-party-sources.md` 記來源，換機器照表重裝。
- **`~/.claude/skills/` 底下的 symlink**：那些指向別處的第三方 skill，`sync-from-local.sh` 會自動略過。
- **機器專屬設定**：`settings.json` 裡有大量本機絕對路徑，不適合跨機器共用。
- **填好的主機檔**（`agent-fleet` 的 `hosts/<真實主機>.md`）：一份完整的主機檔會寫出這台機器跑哪些 agent、各自接什麼、binary 在哪、有哪些 bot——而這些 agent 是用 `--dangerously-skip-permissions` 在跑的。那是攻擊面清單，不是文件。只有 `hosts/EXAMPLE-host.md` 骨架進版控。

## 授權

MIT — 見 [LICENSE](LICENSE)。
