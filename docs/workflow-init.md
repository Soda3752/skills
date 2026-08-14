[← 回目錄](README.md)

# workflow-init

把新專案接上外部系統。

## 作用

這個 plugin 有五個 skill。每一個都是**一次性設定工具**。你在一個新專案執行一次，之後就不再需要它。

每個 skill 都用同一個模式工作：

1. **診斷**（doctor）。它檢查目前缺什麼。
2. **列缺口**。它列出一張表給你看。
3. **問你**。它問你要不要補。
4. **安裝**。你同意後，它一次補齊。

這個模式的好處是：你在任何東西被寫入之前，先看到完整清單。

## 安裝

```
/plugin marketplace add Soda3752/skills
/plugin install workflow-init@soda-skills
```

## 含哪些 skill

| Skill | 接上什麼 | 需要什麼 |
| --- | --- | --- |
| `linear-workflow-init` | Linear 票券工作流 | Linear MCP 已授權 |
| `jira-workflow-init` | Jira 票券工作流 | Atlassian MCP 已授權 |
| `gitnexus-init` | GitNexus 程式碼索引 | Node.js |
| `obsidian-init` | Obsidian 筆記庫 | 無 |
| `parallel-loop-init` | 平行開發環境 | Herdr、Codex CLI |

---

## linear-workflow-init

### 作用

它把當前專案接上 Linear。完成後，Claude 知道你的票在哪個 team、每個狀態欄的 id 是什麼、什麼時候該推票。

### 使用方式

在專案根目錄輸入：

```
/linear-workflow-init
```

只想看現況，不要寫任何檔案時，加上 `doctor`：

```
/linear-workflow-init doctor
```

`doctor` 模式**一個檔案都不寫**。你在確認別人的專案時用這個模式。

### 它會檢查八項

1. Linear MCP 是否已授權。
2. workspace 是否正確。
3. team 是否存在。
4. 六個核心狀態欄是否齊全。
5. `api-require` label 是否存在。
6. 規則檔是否存在。
7. 設定檔是否存在。
8. `CLAUDE.local.md` 是否已 import 規則檔。

### 產出

```
<專案根>/
├── CLAUDE.local.md              # 多一行 @.claude/linear-workflow.md
└── .claude/
    ├── linear-workflow.md       # 工作流規則。跨專案完全相同。
    └── linear-workflow.json     # 這個專案的 team 與狀態 id。
```

規則與值分開存放。規則檔跨專案一字不改。換專案時只換 JSON。所以規則檔日後可以整檔升版，不會弄壞任何專案的設定。

### 你必須自己動手的部分

Linear 的新 team 只有六個預設狀態欄：

```
Backlog / Todo / In Progress / Done / Canceled / Duplicate
```

這套工作流另外需要三欄：

```
In Review / Blocked / API Require
```

**Linear MCP 沒有建立狀態欄的工具。** 所以缺欄時，你必須自己到 Linear 網頁建立。路徑是 `Settings → Teams → <team> → Workflow`。

skill 會偵測缺哪幾欄，並給你手動步驟。這是最常見的缺口。

### 常見錯誤

**把 Project 當成票的歸屬單位。** Linear 的 Project 是工作分組容器。它對應 Jira 的 Epic。票的歸屬單位是 **Team**。票號前綴由 team 決定。搞混會查到空的看板。

---

## jira-workflow-init

### 作用

它把當前專案接上 Jira。行為與 `linear-workflow-init` 對齊。

### 使用方式

```
/jira-workflow-init          # 診斷 + 安裝
/jira-workflow-init doctor   # 只診斷，不寫檔
```

### 它會檢查九項

比 Linear 版多一項：**transition id 的實查校正**。

Jira 的狀態轉換有圖。你不能任意從一個狀態跳到另一個狀態。每一條轉換有自己的 id，而且**每個 project 的 id 不同**。所以 skill 必須實際抓一張票，查它有哪些 transition，再反推 id。

### 產出

```
<專案根>/
├── CLAUDE.local.md              # 多一行 @.claude/jira-workflow.md
└── .claude/
    ├── jira-workflow.md         # 工作流規則
    └── jira-workflow.json       # 站台、project key、transition id
```

### 安裝後第一件事

預設值放在：

```
plugins/workflow-init/skills/jira-workflow-init/config/defaults.env
```

裡面的站台網址與 project key 是**佔位符**。第一次使用前，至少改掉 `JIRA_SITE` 與 `DEFAULT_PROJECT_KEY`。transition id 不用改，skill 會實查校正。

文件中的 `PROJ` 與 `ACME` 是兩個真實專案的匿名代號。

### 零票專案的處理

Jira 需要一張實體票才能查 transition id。專案還沒有任何票時，skill 會請你建一張探測票。**票號會被永久消耗。** 這是 Jira 的限制。

Linear 沒有這個問題。`list_issue_statuses` 不需要任何票就能查。

---

## gitnexus-init

### 作用

它在當前專案建立 GitNexus 程式碼索引。索引建好後，Claude 可以查詢呼叫關係、追蹤執行流程、分析改動影響範圍。

### 使用方式

```
/gitnexus-init
```

### 它只問你三個問題

1. **要啟用語意搜尋（embeddings）嗎？** 啟用後可以用中文或模糊概念查詢。需要 `OPENAI_API_KEY`。
2. **要同時建立 Obsidian 骨架嗎？**
3. **`.mcp.json` 已有其他 obsidian server 時，要怎麼處理？**（只在第 2 題選「是」時才問）

其他設定全部用預設值。skill 不會再問你。

### 前置檢查

執行任何寫入動作前，它先確認四件事：

| 檢查 | 失敗時 |
| --- | --- |
| 在 git repo 內 | 停止。GitNexus 不索引非 git 目錄。 |
| Node.js 可用 | 停止。請先安裝 Node。 |
| 當前目錄是專案根 | 自動切換到 git 根目錄。 |
| GitNexus 尚未初始化 | 問你要跳過還是重新索引。 |

### 產出

- `gitnexus` 註冊為 MCP server。重複執行不會產生重複項目。
- 專案根目錄多一個 `.gitnexus/` 資料夾。裡面是知識圖譜索引。
- 專案登記到 `~/.gitnexus/registry.json`。用 `npx gitnexus list` 可以驗證。
- `CLAUDE.md` 多一段 GitNexus 說明。

---

## obsidian-init

### 作用

它在當前專案建立一個 Obsidian 筆記庫，並註冊對應的 MCP server。

### 使用方式

```
/obsidian-init
```

這個 skill **不問你任何問題**。四個步驟固定執行。想要不同的設定時，事後再告訴 Claude 調整。

### 產出

- `./vault/` 資料夾，內含 `.obsidian/` 子資料夾。Obsidian 第一次開啟時就認得它。
- `.gitignore` 多一行 `/vault/`。個人筆記不會被 commit。
- `.mcp.json` 多一個 `obsidian` server。它在這個專案內覆蓋任何 user 層級的 `obsidian` server。

### 為什麼用 mcpvault

它選用 `@bitbonsai/mcpvault`。原因是這個套件**直接從檔案系統讀取筆記庫**。

所以：

- 不需要 Obsidian.app 在執行中。
- 不需要 Local REST API plugin。
- 不需要 API key。

其他常見的 Obsidian MCP server（cyanheads、MarkusPfundstein）透過 HTTP 與 Obsidian 溝通。它們需要更多設定，而且執行時 Obsidian 必須開著。

### 注意事項

`.mcp.json` 內的路徑必須是**絕對路徑**。mcpvault 不展開 `${workspaceFolder}` 或任何變數。Claude Code 把參數當成字面字串傳給子程序。

---

## parallel-loop-init

### 作用

它檢查平行開發環境是否可用。平行開發指的是 `linear-flow` 的 `parallel-loop`。詳見 [linear-flow](linear-flow.md#parallel-loop)。

### 使用方式

```
/parallel-loop-init          # 診斷 + 補齊
/parallel-loop-init doctor   # 只診斷，不寫檔
```

`doctor` 模式下，第 6 項的 Codex 實跑測試**也不會執行**。那項測試會建立暫存檔並消耗 Codex 額度。

### 它會檢查十二項

主要項目：

- Herdr session 與 claude integration 是否就緒。
- 兩個 skill 與腳本是否安裝在 user 層級。
- 主 repo 的基準線是否乾淨。
- gitnexus 索引是否存在。
- Codex CLI 是否能實際執行（實跑一次測試）。
- Playwright E2E 基建是否就緒。
- worktree 根目錄與 port 區段是否設定。
- 權限白名單是否設定。
- 是否有上一輪的殘留現場。

### 為什麼要先診斷

平行環境的失敗大多是**靜默的**。例如：

- pane 啟動了，但搶不到 port。
- worktree 建好了，但基準線本來就是紅的。

這兩種情況都不會報錯。你要等到很久以後才發現。先執行一次 doctor 比事後從一堆 pane 回推便宜。

### 它不做什麼

它**不設定 Linear**。team、狀態欄、label 由 `linear-workflow-init` 管。這個 skill 只確認那份設定存在。設定不存在時，它請你先執行 `linear-workflow-init`。

兩份 Linear 檢查邏輯一旦並存就會漂移。漂移的症狀是靜默推錯狀態欄。

### 產出

```
~/.claude/skills/                    # skill 在 user 層級，跨專案共用
├── parallel-loop/
└── parallel-ticket/

<專案根>/.claude/                     # 設定與狀態留在各專案
├── parallel-loop.json               # 水位、配額、port、衝突規則
├── parallel-loop-state/             # 執行期產生的結果檔與鎖
└── settings.local.json              # 權限白名單
```

skill 必須放在 user 層級。原因是：實作 pane 的工作目錄是 worktree，而 worktree 沒有 `.claude/` 資料夾。專案層級的 skill 在那裡看不到。
