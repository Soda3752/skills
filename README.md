# soda-skills

個人常用的 Claude Code skill 集散地。用官方 plugin marketplace 機制發佈，換機器時一次裝好。

## 安裝

在任何一台裝好 Claude Code 的機器上：

```
/plugin marketplace add Soda3752/skills
/plugin install workflow-init@soda-skills
/plugin install jira-flow@soda-skills
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
| `workflow-init` | `jira-workflow-init`、`gitnexus-init`、`obsidian-init` | 常開新專案、需要固定流程接上外部系統 |
| `jira-flow` | `grill-to-jira`、`check-jira-status`、`jira-goal-loop` | 已接上 Jira，日常要開票、盤點看板，或想讓 loop 自己把票做完 |
| `report-tools` | `pm_report`、`whats-new` | 需要把調查結果或版本差異交付給非工程角色 |
| `kmp-architecture` | `kmp-mvvm-architecture` | 寫 Kotlin Multiplatform，想把專案統一到同一套 MVVM 架構 |
| `agent-fleet` | `init_telegram_agent` | 想在一台機器上養一群透過 Telegram 溝通的 Claude Code agent |

`jira-workflow-init` 的預設值放在 `plugins/workflow-init/skills/jira-workflow-init/config/defaults.env`，裡面的站台與 project key 是佔位符，裝完請先改成自己的。文件裡的 `PROJ` / `ACME` 是兩個真實專案的匿名代號。

`jira-goal-loop` 是唯一會**在無人監督下寫程式並 commit** 的 skill，裝了不會自動啟動——要由使用者明確用 `/loop` 帶起來。它讀 `<專案>/.claude/jira-workflow.json` 的 `goalLoop` 區塊決定每輪跑哪些驗證指令，所以那個區塊等於「授權它在本機執行什麼」：**第一次在某個專案跑之前，人眼看過那幾條指令**，不要因為 clone 下來的 repo 附了一份設定就照跑。skill 的「資安紅線」一節寫了完整約束（不 push、不改自己的規則檔、不 commit 憑證、貼進 Jira 前先遮敏感值）。

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

**一、值不同 → 自動匿名化（`jira-workflow-init`）**

本機用的是真實 Jira 站台與 project key（不然它日常跑不動），repo 是公開的。檔案結構完全一樣，差別只在幾個字串。

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
