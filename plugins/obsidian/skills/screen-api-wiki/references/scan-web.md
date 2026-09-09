# 掃描網頁前端專案

目標與 KMP 版相同：先產出**清單**（畫面 / API / 型別 / 呼叫關係）給使用者確認，再開始寫頁。

網頁專案與 APP 有兩個結構性差異，會改變掃描方式：

- **畫面邊界模糊。** APP 有 `Screen` 檔可數；網頁的 modal、drawer、tab、展開區塊往往都在同一個 route 元件裡。
- **API 呼叫散落。** APP 集中在 Repository；網頁可能散在元件、hook、react-query key、RTK slice、server action 裡。

所以下面的順序是先鎖路由，再往下追資料流。

## 1. 路由 → 畫面

先認框架：

```bash
cat package.json | grep -E '"(next|react-router|@tanstack/react-router|vue-router|@sveltejs/kit|nuxt)"'
```

| 框架 | 路由在哪 |
|---|---|
| React Router | `createBrowserRouter` / `<Route>`，常在 `src/App.tsx`、`src/routes.tsx` |
| Next.js App Router | `app/**/page.tsx` 的檔案結構本身 |
| Next.js Pages Router | `pages/**/*.tsx` |
| TanStack Router | `src/routes/**` 或 `routeTree.gen.ts` |
| Vue Router | `src/router/index.ts` |
| SvelteKit | `src/routes/**/+page.svelte` |

```bash
ls src/pages/ src/routes/ app/ 2>/dev/null
grep -rn "createBrowserRouter\|<Route \|defineRoutes" --include='*.tsx' --include='*.ts' src | head -30
```

**路由清單只是起點。** 一樣要問「使用者會不會覺得到了另一個地方」：

- 佔一頁的：獨立 route、全螢幕 modal、多步驟精靈的每一步
- 通常併進母頁的一個區塊：drawer、下拉、inline 展開、同頁 tab
- 需要判斷的：查詢參數驅動的狀態（`?status=pending` 的清單分頁）——如果它在畫面上是一顆明顯的分頁鈕，就當一個區塊寫

順手把每個畫面的**進入路徑**記下來（`/orders/:id`），Playwright 截圖時要用。

## 2. 畫面 → 狀態

網頁沒有 `UiState` 這種單一容器，狀態分三處，三處都要看：

```bash
grep -rn "useState\|useReducer" src/pages/Xxx.tsx | head
grep -rn "useQuery\|useMutation\|useSWR" src/ | head -30
grep -rn "createSlice\|useStore\|defineStore\|zustand" src/ | head
```

- **本機 UI 狀態**（`useState`）→ 搜尋字串、展開與否、目前分頁
- **伺服器狀態**（react-query / SWR / RTK Query）→ **這一層就是畫面與 API 的接點**，最重要
- **全域 store**（zustand / redux / pinia）→ 跨頁共用的東西，例如目前使用者、購物車

寫進 wiki 的「看到的」那一欄要抄**畫面上實際的字串**，不是變數名。從 JSX / template 裡抓，不是從 state 名稱推。i18n 的專案就去 locale 檔撈實際文案。

## 3. API 呼叫點

這是網頁版最容易漏的一段。至少掃四種寫法：

```bash
# 直接呼叫
grep -rn "fetch(\|axios\.\|\$fetch(" --include='*.ts' --include='*.tsx' src | head -40
# 集中的 api client
ls src/api/ src/services/ src/lib/api* 2>/dev/null
# react-query / SWR
grep -rn "queryKey\|useQuery(\|useSWR(" src | head -30
# Next.js server action / route handler
grep -rn "\"use server\"" src app 2>/dev/null | head
ls app/api/**/route.ts 2>/dev/null
```

集中在 api client 的專案最好處理——那個模組本身就是端點清單。散落的專案就得逐頁追。

追到端點後，**順手把型別讀掉**：api client 的泛型參數、`zod` schema、`types/` 底下的 interface，通常就是 request / response 的完整欄位表。

還要記錄呼叫的**時機**：

- 掛載時（`useQuery` 預設就會）
- 使用者動作（`useMutation` 的 `mutate`）
- 背景（`refetchInterval`、`refetchOnWindowFocus`）
- 快取失效連鎖（`invalidateQueries` 之後會自動重打哪幾支）

最後那項是網頁專屬且很有價值：「送出表單後，清單會自己重抓」在 wiki 上要寫出來，否則讀者會以為是自己手動刷新的。

## 4. 用後端原始碼校正

前端呼叫點告訴你「打了什麼」，後端原始碼告訴你「真的會發生什麼」。兩者衝突時**以後端為準**，並在頁面上註記。

```bash
ls ../<backend-repo>/src/controllers/ ../<backend-repo>/src/routes/ 2>/dev/null
```

值得從後端補進 wiki 的，通常是前端看不出來的那幾類：

- 欄位沒送時後端的預設值（前端以為不填就是 0，後端其實填了 10）
- 同一個資源有兩支端點，其中一支的回傳欄位不完整（前端選了哪支、為什麼）
- 前端沒處理但真的會發生的錯誤碼
- 後端的副作用（呼叫這支會連帶啟動某個排程）

沒有後端存取權就跳過這一步，並在頁面上標明「未經後端校正」——不要假裝驗證過。

## 5. 純前端的東西

跟 APP 版同一個道理，找出**不來自後端**的畫面內容並明確標記：

- 前端算出來的（小計、差額、百分比）
- URL query / hash 驅動的狀態
- `localStorage` / cookie（主題、側欄收合、草稿）
- 建置期常數（`import.meta.env.VITE_*`、`process.env.NEXT_PUBLIC_*`）
- 樂觀更新（畫面先變、請求還在飛）——這個要特別標，否則讀者對不上時間軸

## 6. 輸出清單

```
畫面（9）：登入 / 儀表板 / 訂單列表 / 訂單詳情 / 建立訂單精靈(3 步) / 設定 / …
API（14）：POST /api/login、GET /api/orders、…
型別（12）：User、Order、OrderListResponse、…
機制（3）：認證與 refresh、錯誤攔截器、react-query 快取失效鏈

⚠ 待確認：
- /orders?status=pending 的三個分頁：算三個畫面還是一頁的三個區塊？
- 建立訂單是 modal 不是 route，要獨立成頁嗎？
- 有沒有後端原始碼可以校正？沒有的話頁面會標「未經後端校正」
```

那個「待確認」區塊是重點。網頁專案的畫面邊界比 APP 模糊得多，這幾題只有使用者答得了。
