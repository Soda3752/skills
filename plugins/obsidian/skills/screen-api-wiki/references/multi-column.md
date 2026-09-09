# Multi-Column Markdown：安裝與語法

兩欄版面（左截圖、右表格）靠社群外掛 **Multi-Column Markdown**（作者 ckRobinson）。
沒裝的話，閱讀模式會直接把 `--- start-multi-column` 這些行當成普通文字印出來——版面會比不分欄還糟。所以它是硬需求，Step 0 要先確認。

## 為什麼不用別的做法

先前實測過三條路，只有外掛能同時滿足「巢狀表格」與「wiki link 可點」：

| 做法 | 巢狀表格 | `[[wiki link]]` | 欄寬可調 |
|---|---|---|---|
| 兩欄 Markdown 表格（左格放圖） | ❌ 只能用 `<br>` 攤平 | ✅ | ❌ 固定 50/50 |
| HTML `<div style="display:flex">` | ❌ | ❌ Obsidian 不解析 HTML 區塊裡的 wikilink | ✅ |
| **Multi-Column Markdown** | ✅ | ✅ | ✅ |

`<br>` 攤平的版本可以當成沒裝外掛時的降級輸出，但要明講「裝了外掛會好很多」，不要默默降級。

## 引導使用者安裝

檢查：

```bash
ls -d <vault>/.obsidian/plugins/multi-column-markdown 2>/dev/null
```

沒有的話，請使用者在 Obsidian 裡做四件事（不要試圖幫他改 `community-plugins.json`，Obsidian 執行中時寫進去不會生效）：

1. 設定 → 第三方外掛 → 關閉「安全模式」
2. 瀏覽 → 搜尋 `Multi-Column Markdown`
3. 安裝 → 啟用
4. 回到筆記按 `Cmd+E` 切閱讀模式

裝好後請他回報，再繼續產頁。

## 語法

```
--- start-multi-column: <唯一ID>
```column-settings
Number of Columns: 2
Column Size: [34%, 66%]
border: off
```

<左欄內容>

--- column-break ---

<右欄內容>

--- end-multi-column
```

要點：

- **ID 必須全 vault 唯一。** 重複的話後面那個不會渲染。取名用 `<頁面>-<區塊>`，例如 `api-saveline`、`list-card`。
- `Column Size: [34%, 66%]` 是實測下來的比例：280px 截圖剛好填滿左欄，右欄容得下三欄表格不換行。
- `border: off` 去掉外掛預設的粗框。有框時整頁會像被切成一格一格的表單。
- 開頭三行 `--- start` / `--- column-break ---` / `--- end` **必須各自獨占一行且頂格**，前面有空白就不會被辨識。
- 區塊裡可以放巢狀表格、mermaid、程式碼區塊——這正是選它的理由。

## 標題放在區塊外

```markdown
### 商品卡

--- start-multi-column: list-card
...
--- end-multi-column
```

不要把 `###` 寫進欄位裡。標題留在外面，`[[頁面#商品卡]]` 這種 anchor 連結才穩，大綱面板也才看得到。

## 截圖尺寸

```markdown
![[03-採購中.png|280]]
```

`|280` 是寬度（px）。手機直式截圖原圖多半 1080×2400，不指定寬度會佔滿整欄、右邊表格被擠成一長條。
280 是預設值；使用者嫌大或嫌小，改這個數字就好，全 vault 一次 sed 就換完。
