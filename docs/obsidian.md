[← 回目錄](README.md)

# obsidian

在專案內建立 Obsidian 筆記庫與對應的 MCP server。

## 作用

兩支 skill：

| skill | 用途 | 次數 |
|---|---|---|
| `obsidian-init` | 建 vault + 註冊 MCP server | 一次性 |
| `screen-api-wiki` | 把手機或網頁專案整理成「以畫面為主軸」的 wiki | 建置一次，之後增量更新 |

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

---

## screen-api-wiki

### 使用方式

```
/screen-api-wiki
```

或直接說「整理這個專案的 obsidian wiki，我要每個畫面的操作與會打的 API」。

### 產出

以**畫面**為入口的 vault：

```
vault/
├─ 00-首頁.md              索引 + 全域動線圖
├─ 10-畫面/                一畫面一頁：截圖 | 元素↔欄位 | 流程 | UiState
├─ 20-API/                 一端點一頁：完整 req/res schema + 呼叫它的畫面截圖
├─ 30-資料模型/            一模型一頁：欄位 + 「顯示在哪個畫面」
├─ 40-機制/                跨頁的：加密、錯誤恢復、領域鐵律
├─ 50-對照/欄位對照總表.md  一張大表：畫面 | 元素 | 欄位 | API
└─ attachments/*.png
```

核心是**雙向、欄位級**的連結。看到畫面上的 `¥850`，點過去知道它是 `GET /orders` 的 `unit_price`；看 `unit_price`，知道它長在商品卡的價格那一行。

畫面頁與 API 頁都是**左截圖、右表格**的兩欄版面。

### 三個階段

1. **doctor** — 檢查 vault、MCP、Multi-Column Markdown 外掛、截圖來源、專案結構認不認得，列出缺口讓你確認後才補
2. **建置** — 掃程式碼 → 出清單給你確認 → 依 模型 → API → 畫面 → 機制 → 總表 的順序產頁
3. **增量更新** — 已有 vault 時只補新增與真的改過的區塊，**不覆蓋你手改過的內容**；被刪掉的頁標記而不刪除

### 支援兩種專案

skill 會自己偵測，走對應的掃描規則與截圖方式：

| 專案 | 偵測 | 掃描規則 | 截圖 |
|---|---|---|---|
| 手機 | `*/src/commonMain/kotlin` | `scan-kmp.md`：路由 → Screen/ViewModel → Repository → 端點 | 現有資料夾 / Roborazzi Preview / Appium |
| 網頁 | `package.json` 有 react·vue·svelte·next·nuxt | `scan-web.md`：路由 → 狀態三層 → fetch/react-query 呼叫點 → 後端校正 | 現有資料夾 / **Playwright** |

版面也跟著調整：手機截圖 `|280` + 欄寬 `[34%, 66%]`，網頁桌機 `|460` + `[46%, 54%]`。

### Playwright 截圖（網頁專案）

```bash
node scripts/shoot-web.mjs routes.json
node scripts/shoot-web.mjs routes.json --only 03,04   # 只重拍幾張
node scripts/shoot-web.mjs routes.json --headed       # 看著它跑
```

`routes.json`（樣板：`scripts/routes.example.json`）由你跟 Claude 一起填：每頁一個 path、一個「畫面真的長好了」的 `waitFor` 選擇器，需要點開的畫面用 `actions`。

幾個刻意的設計：

- **登入只做一次**，存成 storageState 重用。帳密走 `"env:APP_PASSWORD"`，不寫進 json。
- **`hide` 可以遮掉時鐘、隨機頭像**這類每次都變的元素，否則 vault 的 git diff 永遠是髒的。
- **單頁失敗不中斷**，跑完統一列失敗清單。
- **`fullPage` 預設 false**——整頁截圖在長頁面會變一條細長圖，兩欄版面看不清。
- `"mobile": true` 才多拍一張 390×844，預設只拍桌機。

### 前置需求

- Obsidian 的 **Multi-Column Markdown** 社群外掛（兩欄版面的硬需求，沒裝會看到一堆語法標記）
- 網頁專案：`npm i -D playwright && npx playwright install chromium`

### 驗證腳本

```bash
scripts/validate-vault.sh <vault 路徑>
```

查斷鏈、缺 anchor、缺圖、分欄區塊不配對，外加警告「標題裡塞了 wiki link」（會讓 anchor 失效，實測踩過）。

### 適用範圍

掃描規則是照上表那兩種形狀寫的。其他技術棧可以跑，但會退回通用推論，skill 會先講明再問你要不要繼續。

同一個 repo 同時有 APP 與前端時，skill 會問這份 wiki 是要做哪一邊——兩邊混在同一個 vault 會讓畫面索引失去意義。
