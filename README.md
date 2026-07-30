# soda-skills

個人常用的 Claude Code skill 集散地。用官方 plugin marketplace 機制發佈，換機器時一次裝好。

## 安裝

在任何一台裝好 Claude Code 的機器上：

```
/plugin marketplace add Soda3752/skills
/plugin install workflow-init@soda-skills
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
| `report-tools` | `pm_report`、`whats-new` | 需要把調查結果或版本差異交付給非工程角色 |
| `kmp-architecture` | `kmp-mvvm-architecture` | 寫 Kotlin Multiplatform，想把專案統一到同一套 MVVM 架構 |

`jira-workflow-init` 的預設值放在 `plugins/workflow-init/skills/jira-workflow-init/config/defaults.env`，裡面的站台與 project key 是佔位符，裝完請先改成自己的。文件裡的 `PROJ` / `ACME` 是兩個真實專案的匿名代號。

各 plugin 底下每個 skill 的觸發條件寫在自己的 `SKILL.md` frontmatter，Claude 會自行判斷何時載入，不需要手動呼叫。

## 目錄結構

```
.
├── .claude-plugin/
│   └── marketplace.json          # 宣告有哪些 plugin
├── plugins/
│   └── <plugin>/
│       ├── .claude-plugin/plugin.json
│       └── skills/<skill>/SKILL.md
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
./scripts/check-secrets.sh       # 掃站台網域、票號、絕對路徑、token
git diff                         # 人眼再看一次
git commit && git push
```

`sync-from-local.sh` 裡的 `SKILL_MAP` 就是收錄清單，唯一的真實來源。

第一次 clone 到新機器時，要先建對照表才能跑 sync：

```bash
cp scripts/.anonymize-map.example.json scripts/.anonymize-map.json
# 填入自己的真實站台與 project key
```

沒有這個檔案時 `anonymize.sh` 會直接失敗而不是默默跳過——默默跳過的後果是把真值留在工作區。

### 為什麼 sync 之後會自動跑 anonymize

`jira-workflow-init` 是唯一一個 repo 版與本機版**刻意分岔**的 skill：本機用的是真實 Jira 站台與 project key（不然它日常跑不動），repo 是公開的。

`sync-from-local.sh` 用 `rsync --delete` 單向覆蓋，所以每次同步都會把真值帶回來。`anonymize.sh` 就掛在同步的最後一步自動抹掉，不依賴人記得手動改。它是冪等的，重複跑不會有副作用；如果上游檔案改到讓它找不到插入錨點，它會直接報錯而不是默默跳過。

**其他 skill 不該走這條路。** 發現內容有問題就改 `~/.claude/skills/` 的源頭，下次 sync 自然帶進來——分岔規則每多一條，就多一個「本機明明改了、repo 卻沒生效」的坑。

真值對照表放在 `scripts/.anonymize-map.json` 且不進版控。**對照表就是解碼表**——把「真實 project key → `PROJ`」這種映射 commit 上公開 repo，等於附一份還原說明書，匿名化整個白做。`check-secrets.sh` 也從這個檔案讀專案專屬樣式，所以兩支腳本本身都不含任何真實值。

改動 skill 內容後記得把該 plugin 的 `version` 往上加，其他機器 `/plugin marketplace update` 才知道有新版。

## 這個 repo 不收什麼

- **第三方 skill**：從別的 marketplace 裝的（官方、mattpocock、pm-skills…）不 vendor 進來，只在 `docs/third-party-sources.md` 記來源，換機器照表重裝。
- **`~/.claude/skills/` 底下的 symlink**：那些指向別處的第三方 skill，`sync-from-local.sh` 會自動略過。
- **機器專屬設定**：`settings.json` 裡有大量本機絕對路徑，不適合跨機器共用。

## 授權

MIT — 見 [LICENSE](LICENSE)。
