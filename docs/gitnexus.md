[← 回目錄](README.md)

# gitnexus

把專案接上 GitNexus 程式碼索引。

## 作用

這個 plugin 只有一個 skill：`gitnexus-init`。它是**一次性設定工具**。你在一個新專案執行一次，之後就不再需要它。

索引建好後，Claude 可以查詢呼叫關係、追蹤執行流程、分析改動影響範圍。

## 安裝

```
/plugin marketplace add Soda3752/skills
/plugin install gitnexus@soda-skills
```

## 前置條件

- 當前目錄在一個 git repo 內。
- Node.js 可用。

---

## gitnexus-init

### 使用方式

```
/gitnexus-init
```

### 它只問你三個問題

1. **要啟用語意搜尋（embeddings）嗎？** 啟用後可以用中文或模糊概念查詢。需要 `OPENAI_API_KEY`。
2. **要同時建立 Obsidian 骨架嗎？**
3. **`.mcp.json` 已有其他 obsidian server 時，要怎麼處理？**（只在第 2 題選「是」時才問）

其他設定全部用預設值。skill 不會再問你。

第 2 題選「是」時，它會把 vault 的建立委派給 `obsidian` plugin 的 `obsidian-init`。詳見 [obsidian](obsidian.md)。

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

### 相關

`linear-flow` 的 `parallel-loop-init` 會檢查 gitnexus 索引是否存在。要跑平行開發時，先在這裡把索引建好。見 [linear-flow](linear-flow.md#parallel-loop-init)。
