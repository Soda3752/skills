[← 回目錄](README.md)

# obsidian

在專案內建立 Obsidian 筆記庫與對應的 MCP server。

## 作用

這個 plugin 只有一個 skill：`obsidian-init`。它是**一次性設定工具**。你在一個新專案執行一次，之後就不再需要它。

## 安裝

```
/plugin marketplace add Soda3752/skills
/plugin install obsidian@soda-skills
```

---

## obsidian-init

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

### 相關

`gitnexus` plugin 的 `gitnexus-init` 在你選擇建立 Obsidian 骨架時，會委派給這個 skill 處理 vault 建立、`.gitignore` 與 `.mcp.json` 註冊。見 [gitnexus](gitnexus.md)。
