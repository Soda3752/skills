# soda-skills

個人常用的 Claude Code skill 集散地。用官方 plugin marketplace 機制發佈，換機器時一次裝好。

## 安裝

在任何一台裝好 Claude Code 的機器上，先加入 marketplace：

```
/plugin marketplace add Soda3752/skills
```

再安裝你要的 plugin：

```
/plugin install linear-flow@soda-skills
/plugin install jira-flow@soda-skills
/plugin install gitnexus@soda-skills
/plugin install obsidian@soda-skills
/plugin install report-tools@soda-skills
/plugin install kmp-architecture@soda-skills
/plugin install agent-fleet@soda-skills
```

不確定要裝哪些時，看 [Wiki 的「我該裝哪些」](docs/README.md#我該裝哪些)。

之後要更新：

```
/plugin marketplace update soda-skills
```

## Wiki

每個 plugin 的作用與使用方式，看對應的說明頁。

| Plugin | 說明 | 文件 |
| --- | --- | --- |
| `linear-flow` | 票在 Linear 時的初始化與日常工作流。含平行開發。 | [開啟](docs/linear-flow.md) |
| `jira-flow` | 票在 Jira 時的初始化與日常工作流。 | [開啟](docs/jira-flow.md) |
| `gitnexus` | 把專案接上 GitNexus 程式碼索引。一次性設定。 | [開啟](docs/gitnexus.md) |
| `obsidian` | 在專案內建 Obsidian vault 與 MCP。一次性設定。 | [開啟](docs/obsidian.md) |
| `report-tools` | 產生繁體中文報告。 | [開啟](docs/report-tools.md) |
| `kmp-architecture` | Kotlin Multiplatform 的 MVVM 架構規格。 | [開啟](docs/kmp-architecture.md) |
| `agent-fleet` | 用 Telegram 管理一群 Claude Code agent 的設計參考。 | [開啟](docs/agent-fleet.md) |

其他文件：

- [Wiki 目錄](docs/README.md)
- [第三方來源清單](docs/third-party-sources.md)

## 授權

MIT — 見 [LICENSE](LICENSE)。
