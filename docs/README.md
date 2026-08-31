# soda-skills Wiki

這是 `soda-skills` 的說明文件目錄。每個 plugin 有一頁。每頁說明該 plugin 的作用與使用方式。

## 寫作規則

本 wiki 用簡化技術寫作原則（ASD-STE100 精神）：

- 一個句子只講一件事。
- 用主動語態。
- 同一個東西只用同一個名稱。
- 步驟用祈使句。
- 不用比喻。

## 名詞

先看懂這五個詞，其餘頁面才好讀。

| 名詞 | 意思 |
| --- | --- |
| **plugin** | 一組 skill 的安裝單位。你用 `/plugin install` 安裝一個 plugin。 |
| **skill** | 一份寫給 Claude 的操作手冊。Claude 讀懂它，然後照著做。 |
| **觸發** | 你說出某些話，Claude 自己判斷要載入哪個 skill。你不需要記指令。 |
| **票** | 工作項目。在 Jira 叫「議題」或「卡片」，在 Linear 叫「issue」。本 wiki 一律叫「票」。 |
| **worktree** | Git 的功能。它讓同一個 repo 在多個資料夾各自簽出不同分支。平行開發用它隔離每張票。 |

## Plugin 一覽

| Plugin | 一句話說明 | 說明頁 |
| --- | --- | --- |
| `linear-flow` | 票在 Linear 時的初始化與日常工作流。含平行開發。 | [linear-flow](linear-flow.md) |
| `jira-flow` | 票在 Jira 時的初始化與日常工作流。 | [jira-flow](jira-flow.md) |
| `gitnexus` | 把專案接上 GitNexus 程式碼索引。一次性設定。 | [gitnexus](gitnexus.md) |
| `obsidian` | 在專案內建 Obsidian vault 與 MCP。一次性設定。 | [obsidian](obsidian.md) |
| `report-tools` | 產生繁體中文報告。 | [report-tools](report-tools.md) |
| `kmp-architecture` | Kotlin Multiplatform 的 MVVM 架構規格。 | [kmp-architecture](kmp-architecture.md) |
| `agent-fleet` | 用 Telegram 管理一群 Claude Code agent 的設計參考。 | [agent-fleet](agent-fleet.md) |
| `herdr` | 在 Herdr 裡開新 pane，把工作派給另一個 agent。 | [herdr](herdr.md) |

其他文件：

- [第三方來源清單](third-party-sources.md) — 本 repo 不收錄、但需要另外安裝的 skill。

## 我該裝哪些

依你的情況選。

**情況 1：我用 Linear 管理工作。**
裝 `linear-flow`。先執行 `/linear-workflow-init` 設定專案，再開始日常使用。初始化與日常在同一個 plugin 裡。

**情況 2：我用 Jira 管理工作。**
裝 `jira-flow`。先執行 `/jira-workflow-init` 設定專案。

**情況 3：我兩種都用。**
兩個都裝。但是**同一個專案只能接一種**。原因見 [linear-flow](linear-flow.md#不要在同一個專案接兩套工作流)。

**情況 4：我只要報告功能。**
只裝 `report-tools`。它不需要任何票券系統。

**情況 5：我寫 Kotlin Multiplatform。**
裝 `kmp-architecture`。它與票券系統無關。

**情況 6：我要平行開發（`linear-flow` 的 parallel 系列）。**
除了 `linear-flow`，再裝 `gitnexus`。`parallel-loop-init` 會檢查 gitnexus 索引是否存在。

**情況 7：我要在專案內放 Obsidian 筆記。**
裝 `obsidian`。它與票券系統無關。裝了 `gitnexus` 的話，`gitnexus-init` 會在你同意時自動委派給它。

**情況 8：我用 Herdr，想把長工作派給另一個 pane。**
裝 `herdr`。它與票券系統無關，單裝就能用。你同時用 `linear-flow` 的 wave 系列時，兩個一起裝——用 `herdr` 開 pane 派工，讓那個 agent 去跑 wave。

## 安全須知

有兩個 skill 會在**無人監督**的情況下寫程式並 commit：

- `jira-goal-loop`
- `linear-goal-loop`

這兩個都不會自動啟動。你必須明確啟動它們。啟動前先讀對應說明頁的「安全前提」一節。
