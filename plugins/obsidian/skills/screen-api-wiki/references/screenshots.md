# 截圖來源：三條路與它們的代價

截圖是這份 wiki 最貴的素材。各來源的成本差一個數量級，**一定要讓使用者選**，不要自己挑最完整的那條然後花掉他半小時。

用 `AskUserQuestion` 問，選項裡標出時間成本。

| 專案型別 | 可用來源 |
|---|---|
| KMP / Compose | 現有資料夾、Roborazzi Preview、Appium 實機 |
| 網頁 | 現有資料夾、**Playwright**（見下方專節） |

## 1. 現有截圖資料夾（最便宜，優先掃）

先掃過再問——如果專案裡本來就有一批可用的圖，使用者通常直接選它。

```bash
find . -path ./build -prune -o -name "*.png" -print 2>/dev/null \
  | grep -iv "mipmap\|drawable\|\.gradle\|AppIcon" | head -40
```

常見位置：

- `.claude/report/**/screenshots/`（先前的報告或 Appium 場次留下的）
- `docs/`、`design/`、`screenshots/`
- 使用者自己指定的路徑

**代價**：可能已經過時。把資料夾的日期跟 `git log -1 --format=%cd -- <UI 目錄>` 對一下，若 UI 比截圖新，講出來讓使用者決定要不要重跑。

## 2. Roborazzi Preview 截圖（中等，最容易重跑）

`kmp-architecture:preview-screenshot` skill 用 Robolectric 在純 JVM 渲染 `@Preview`，不用模擬器。

```bash
grep -rn "roborazzi" --include='*.gradle*' . | head
```

有結果 → 直接呼叫該 skill。
沒結果 → 它自己的 `references/setup.md` 會裝工具鏈，約 10 分鐘。

先確認有多少 Preview 可用：

```bash
grep -rln "@Preview" --include='*.kt' . | head -30
```

**優點**：之後改 UI 可以一行指令重出全部的圖，是三者裡唯一真正可維護的。
**代價**：只拍得到 Preview 有涵蓋的狀態。對話框、BottomSheet、錯誤狀態常常沒有 Preview，這些畫面會缺圖。

## 3. Appium 實機跑一輪（最貴，但最真）

起模擬器 → 裝 APK → 依畫面清單逐頁操作截圖。

**優點**：拍得到真實資料、真實狀態轉換、Preview 涵蓋不到的中間過程。
**代價**：20–40 分鐘，而且中途卡住的機率不低（模擬器沒起來、APK 版本不對、資料狀態不符）。事前先跟使用者確認：要用哪個 build variant、有沒有可用的測試帳號或 mock 通道。

有 mock / 假資料通道時走那個。它的資料通常刻意涵蓋各種邊界情境（缺圖、載圖失敗、超長名稱、部分已購），拍出來的圖反而比連生產後端更有說明力。

## 4. Playwright（網頁專案）

網頁版的預設選擇。相較 APP 的三條路，它同時便宜又可重跑——瀏覽器不用模擬器、登入可以存成 storageState 重用、改完 UI 一行指令重出全部。

用 skill 自帶的腳本：

```bash
node <skill>/scripts/shoot-web.mjs routes.json
node <skill>/scripts/shoot-web.mjs routes.json --only 03,04   # 只重拍幾張
node <skill>/scripts/shoot-web.mjs routes.json --headed       # 看著它跑，除錯用
```

### 前置

```bash
ls node_modules/playwright 2>/dev/null || echo "要裝"
npm i -D playwright && npx playwright install chromium
```

專案已經有 `playwright.config.ts` 也照樣用這支腳本——它跟既有的 E2E 測試互不干擾，不會動到 `playwright/` 目錄。

### routes.json

樣板在 `scripts/routes.example.json`。**跟使用者一起把它填出來**，不要自己猜路徑與選擇器：

1. 從 `references/scan-web.md` 得到的畫面清單，逐頁給一個 `path`
2. 每頁挑一個「畫面真的長好了」的選擇器當 `waitFor`（表格第一列、標題、按鈕），不要靠 `wait` 硬等毫秒——CI 或慢機器上會拍到骨架屏
3. 需要點開才看得到的（modal、drawer、精靈的第 2 步）用 `actions` 逐步操作後再拍
4. 需要登入的專案填 `auth`，**帳密一律寫 `"env:APP_PASSWORD"`**，不要寫死

### 幾個實務要點

- **`hide` 遮掉會變的東西**（時鐘、隨機頭像、相對時間）。不遮的話每次重跑截圖都不一樣，vault 的 git diff 永遠是髒的。
- **`fullPage` 預設 false。** 整頁截圖在很長的頁面會變成一條細長圖，塞進兩欄版面完全看不清。真的需要看完整內容的頁面才逐張開。
- **`--only` 是主力用法。** 改了一頁 UI 只重拍那一張，其餘不動。
- **失敗不中斷。** 腳本會跑完全部再列失敗清單。失敗多半是選擇器改了、需要先建資料、或 storageState 過期（刪掉 `.playwright-auth.json` 重跑）。
- **`.playwright-auth.json` 與 `routes.json` 的處置**：前者含登入憑證，一定要進 `.gitignore`；後者不含密碼（都走 env）可以進 repo，讓下次重拍不用重填。

### 手機版

`"mobile": true` 會多拍一張 `-mobile.png`（`iPhone 13` device + 390×844）。
預設只拍桌機——**RWD 差異明顯的畫面才開**，全開會讓圖檔數量與跑的時間都加倍。
兩張圖在頁面上並列，見 `vault-layout.md` 的網頁專案版面。

## 命名與擺放

一律複製進 `vault/attachments/`，用**序號 + 中文描述**：

```
01-未開工主控台.png
02-開工對話框.png
03-採購中.png
```

序號給的是**動線順序**，不是字母順序——之後有人想照著圖走一遍流程時，檔名排序就是流程。

名字一旦寫進頁面就會散佈在幾十處，改名等於全 vault 改連結。第一次就取定。

## 對應到畫面的哪一段

一張圖常常只對應畫面的一個區塊（清單狀態 vs. 對話框 vs. BottomSheet）。產頁前先列一張對照表給使用者確認：

| 檔名 | 畫面 | 區塊 |
|---|---|---|
| 01-未開工主控台.png | 今日採購 | 頁首與開工卡 |
| 02-開工對話框.png | 今日採購 | 開工對話框 |
| 04-回報面板.png | 回報採購 BottomSheet | 讀進來 / 送出去 |

歸錯畫面的圖會安靜地污染每一條指向它的交叉連結，而且很難用工具檢查出來——只有人看得出「這張圖不是這一頁」。

## 沒有圖的畫面

照樣產頁，在該區塊寫一行「無截圖（原因）」。

**不要**產 ASCII 線框或佔位圖去補。假圖會被當成真的 UI，比缺圖有害。
