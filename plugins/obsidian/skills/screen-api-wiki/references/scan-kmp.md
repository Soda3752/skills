# 掃描 KMP / Compose 專案

目標是產出一份**清單**（畫面 / API / 模型 / 呼叫關係），拿給使用者確認之後才開始寫頁。
先確認清單再寫，是因為「你漏了相機那頁」在清單階段是一行字，在 40 頁都寫完之後是重做。

## 順序

### 1. 路由 → 畫面

```bash
find . -name "AppRoute.kt" -o -name "*Route*.kt" -o -name "*Navigation*.kt" | head
ls */src/commonMain/kotlin/**/screen/*/
```

路由檔給的是「哪些畫面佔一個返回堆疊項」。但**畫面清單不等於路由清單**——BottomSheet、對話框、底部分頁、相機常常刻意不佔路由，卻各自是使用者眼中的一頁。

判斷標準：**使用者會不會覺得「我到了另一個地方」**。會，就值得一頁。

一個典型的落差：4 個路由，但值得寫 8 頁。

### 2. 畫面 → ViewModel → UiState

```bash
ls **/screen/*/
```

慣例是三件一組：`XxxScreen.kt`（接線）、`XxxScreenContent.kt`（純 UI）、`XxxViewModel.kt`（狀態與動作）。

從 ViewModel 讀三件事：

- `XxxUiState` 的每個欄位，特別是 **衍生屬性**（`val canSubmit get() = …`）——那些通常就是畫面上「按鈕為什麼是暗的」的答案
- 公開方法 `onXxxClick()` —— 這些是使用者的操作
- 一次性事件（`Channel` / `Flow`）—— 導航與 Toast

`ScreenContent.kt` 讀畫面元素的文案。頁面裡「看到的」那一欄要寫**使用者實際看到的字串**（`剩 6`、`買 6`、`收工結帳`），不是變數名。這一點決定了這份 wiki 好不好查。

### 3. Repository → 端點

```bash
find . -path "*api/core/*" -name "*Endpoint*"
ls **/api/repository/*/
```

端點常集中在一個 `sealed class ApiEndpoint`。從 Repository 實作讀出每支端點的 request / response 型別。

**順手把 KDoc 全部讀掉。** 這類專案的地雷幾乎都寫在註解裡：為什麼用 A 端點不用 B、哪個欄位不送會被後端預設成別的值、哪支不能自動重試。這些是 wiki 最有價值的內容，而且已經寫好了，只是沒人看得到。

### 4. 模型

```bash
ls **/model/*/
grep -rn "@Serializable" --include='*.kt' | head -40
```

`@SerialName` 是**線上真實欄位名**，wiki 一律寫這個，不要寫 Kotlin 的 camelCase 屬性名。讀者是拿它去對後端或看封包的。

順便記下衍生屬性（`val displayName get() = productName.replace("<br>", "\n")`）——它們解釋了「為什麼畫面顯示的跟 API 回的不一樣」。

### 5. 純本機的東西

不是所有畫面上的數字都來自後端。找出這幾類，在 wiki 裡標成 **純本機**：

- StateHolder 裡的暫存（採購地點、缺貨紀錄）
- 本機算出來的（差額 = A − B）
- 編譯期常數（build variant、版本號）
- Room 快取與待上傳佇列

沒標的話，讀者會去後端找一個不存在的欄位。這是這份 wiki 最常被感謝的一類註記。

### 6. 呼叫關係

對每個畫面回答：**進頁時打什麼、每個按鈕打什麼、背景打什麼。**

背景那類最容易漏，也最容易造成誤會（例如心跳成功時畫面完全不動——這件事本身就值得寫進 API 頁）。

## 輸出：先給使用者看的清單

```
畫面（8）：啟動頁 / 登入 / 主畫面 / 今日採購 / 回報 BottomSheet / 收工結帳 / 相機 / 我
API（15）：POST /login、GET /me、GET /orders?status=0 …
模型（14）：User、Order、PurchaseGroup …
機制（4）：加密封包、錯誤恢復鏈、心跳、超買防護

⚠ 待確認：
- PurchaseGroup 是純 APP 端計算，後端沒有這個概念——要不要獨立一頁？
- POST /release 有 Repository 實作但沒有 UI 呼叫——列為「無 UI 入口」？
```

那個「待確認」區塊才是重點。清單本身使用者掃一眼就過，模稜兩可的判斷才需要他拍板。

## 不是 KMP 的專案

照樣可以做，但要先講清楚：這支 skill 的掃描規則是照 Screen/ScreenContent/ViewModel + Repository + Ktor 寫的，換技術棧就得靠推論，畫面與 API 的對應可能抓不齊。

講完再問要不要繼續。不要默默降級然後交出一份有洞的 wiki。
