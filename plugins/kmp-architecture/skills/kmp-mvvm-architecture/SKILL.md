---
name: kmp-mvvm-architecture
description: 將任何 Android / KMP 專案（或其中的頁面）改寫成這套 KMP MVVM 標準架構：Compose Multiplatform 共享 UI、MVVM 雙向資料流（Screen/ScreenContent 分離 + UiState/UiEvent）、Koin DI、Ktor API 層、Navigation3 導航、統一錯誤處理。當使用者說「照這套架構改寫」、「架構移植」、「用這個架構重寫某專案/某頁面」、「建立符合本架構的新頁面」、「開多個 subagent 改寫頁面」，或任何要在專案複製本架構的需求時，必須使用本 skill。即使使用者只說「幫我把 XX 專案改成跟這個一樣的架構」也應觸發。
---

# KMP MVVM 架構移植

本 skill 是一套 KMP MVVM 架構的可移植規格書（Compose Multiplatform 共享 UI）。目的：讓主 agent 帶領多個 subagent，把一個目標專案（或新頁面）改寫成完全一致的架構。

> 本規格書萃取自一個實際運作中的 KMP 參考專案。所有範本已通用化（package 一律 `com.example.app`），可直接套用到任何目標專案；references 內的檔案路徑均為「相對結構命名範例」，不是任何特定專案的絕對路徑。

## 技術選型與版本基準

| 層面 | 方案 | 版本（基準） |
|------|------|------|
| 語言/平台 | Kotlin Multiplatform（Android minSdk 30 + iosArm64/iosSimulatorArm64） | Kotlin 2.3.20 |
| UI | Compose Multiplatform（單模組 `composeApp`，共享 UI） | — |
| DI | Koin | 4.2.0 |
| 網路 | Ktor（Android: OkHttp engine / iOS: Darwin engine） | 3.4.2 |
| 導航 | Navigation3（org.jetbrains.androidx.navigation3） | 1.1.1 |
| ViewModel | androidx.lifecycle KMP 版 | 2.10.0 |
| 序列化 | Kotlinx Serialization | 1.10.0 |
| 本地儲存 | Multiplatform Settings (russhwolf) | 1.3.0 |
| 日誌 | Napier | 2.7.1 |
| 圖片 | Coil 3 | 3.4.0 |
| 多語系 | Compose Multiplatform 內建資源（`Res.string` + `stringResource`）＋自寫 `LocalAppLocale` 執行期切換 | 見 references/platform-i18n-theme.md |

所有版本統一管理於 `gradle/libs.versions.toml`，禁止在 `build.gradle.kts` 寫死版本號。

> ⚠️ 多語系以本表與 `references/platform-i18n-theme.md` 為準（Compose 內建資源系統），**不要引入 Lyricist**——舊的專案選型文件曾列 Lyricist，但實際專案未使用。

## 分層架構總覽

```
composeApp/src/
├── commonMain/kotlin/<package>/
│   ├── api/
│   │   ├── core/          # ApiService、HttpClientFactory(expect)、ApiResponse、ApiEndpoints
│   │   └── repository/    # 每個領域一個資料夾：<domain>/XxxRepository.kt + XxxRepositoryImpl.kt
│   ├── base/              # BaseViewModel、ApiErrorController/Host、DialogViewState、Language、Toast
│   ├── di/                # AppModule.kt（sharedModule）
│   ├── model/<domain>/    # @Serializable data class
│   ├── localstorage/      # 儲存介面定義（ITokenStorage 等），實作放各平台
│   ├── screen/<feature>/  # 每頁一個資料夾（見下方「頁面單位結構」）
│   ├── ui/
│   │   ├── navigation/    # AppRoute.kt、MainNavViewModel.kt
│   │   ├── component/     # 跨頁共用元件
│   │   ├── dialog/        # 跨頁共用 Dialog
│   │   └── theme/         # Color、Typography、Shape、Theme
│   └── util/              # TimeUtil、平台抽象介面（expect 宣告）
├── androidMain/           # actual 實作、MainActivity、Android Service
└── iosMain/               # actual 實作、MainViewController、iOS 初始化
```

### 頁面單位結構（subagent 的產出單位）

```
screen/<feature>/
├── <Feature>Screen.kt         # 接 ViewModel、收集 UiState、轉發事件、處理導航與一次性事件
├── <Feature>ScreenContent.kt  # 純 UI + UiEvent sealed class 定義 + @Preview
├── <Feature>ViewModel.kt      # 繼承 BaseViewModel + UiState data class 定義
├── component/                 # 該頁專屬元件（每個也是純 UI）
├── dialog/                    # 該頁專屬 Dialog（同樣 Content + Preview 慣例）
└── domain/                    # 該頁 UseCase
```

## 資料流（單向下行、事件上行）

```
User 操作
  → ScreenContent 發出 UiEvent（(Event) -> Unit 上行）
    → Screen 轉發給 ViewModel.onEvent / 對應方法
      → ViewModel 呼叫 UseCase → Repository → ApiService / LocalStorage
        → ViewModel update UiState（StateFlow）
          → Screen collectAsStateWithLifecycle
            → ScreenContent 重組（UiState 下行）

API 錯誤 → BaseViewModel helper（handleApiResult / emitApiRetryError）→ ApiErrorController
  → UI 層三段掛載呈現：ApiErrorHost（App 根部掛一次）+ BindApiError(viewModel)（每個 Screen 掛一次）
一次性事件（導航/Toast）→ ViewModel 發 one-shot event（Channel）→ Screen 的 LaunchedEffect(viewModel) 消費
Dialog 顯示 → 單一 dialogUiState: StateFlow<DialogEvent?>（sealed class + null）驅動，不用多個 Boolean flag
```

Screen 頂部有固定掛載順序（照抄即可）：共用效果（如 KeepScreenOnEffect）→ `BindApiError(viewModel)` → 各 `collectAsStateWithLifecycle()` → `LaunchedEffect(viewModel)` 收集一次性事件。

## 核心鐵律（所有 subagent 必守）

1. **ScreenContent 是純函式 UI**：只吃 `UiState` + `(UiEvent) -> Unit`。禁止取得 ViewModel、禁止 `koinInject`、禁止導航、禁止平台 API。必附 `@Preview`。
2. **UiState 是單一 data class**，用 `MutableStateFlow` + `update {}` 維護，定義在 ViewModel 同檔案。
3. **UiEvent 是 sealed class/interface**，定義在 ScreenContent 檔案內，命名 `<Feature>ScreenEvent`。
4. **ViewModel 繼承 BaseViewModel**，不散落 try-catch——API 呼叫用 `viewModelScope.launch { showLoading(); …; hideLoading() }` 顯式包夾，結果交給 `handleApiResult` / `emitApiRetryError`（onRetry 傳方法自身形成重試閉包）。禁止 import 任何 Android/iOS 平台型別，也**禁止發明 BaseViewModel 沒有的 helper**（如 launchWithXxx——不存在）。
5. **業務邏輯抽 UseCase**（`screen/<feature>/domain/`，`suspend operator fun invoke` 慣例），資料存取走 **Repository 介面**（`api/repository/<domain>/`，interface + Impl 成對；Impl 內以 `toResult()` 收斂錯誤，上層只面對 `Result`）。
6. **一切依賴由 Koin 注入**：建構子注入；UseCase / Repository / StateHolder 一律 `single` 註冊。**ViewModel 之間禁止互相依賴**——跨頁執行期狀態抽成 StateHolder（純 class + Flow，`single`）。
7. **導航只發生在 Screen 層**，路由是 `@Serializable` 的 `AppRoute : NavKey` sealed interface，back stack 為 MainNavViewModel 持有的 `mutableStateListOf<AppRoute>`。Dialog 顯示走各頁 `dialogUiState`（AppRoute.Dialog 路由為預留機制，entry 未實作前勿使用）。
8. **commonMain 優先**：只有真正碰平台 API 的碼才進 androidMain/iosMain，以 expect/actual 或介面+平台實作橋接；平台介面綁定必須 Android/iOS **兩邊成對**，iOS 缺能力就給 NoOp 實作。
9. **時間函數一律寫在 TimeUtil**；用 `kotlin.time.Clock`，不用 `kotlinx.datetime.Clock`。
10. **命名/位置照本表**，不自創目錄或後綴。

## References 索引（按需閱讀）

| 檔案 | 內容 | 誰該讀 |
|------|------|--------|
| `references/mvvm-view.md` | Screen/ScreenContent/UiEvent/Preview 範本、screen 目錄慣例 | 改寫頁面的每個 subagent |
| `references/mvvm-viewmodel.md` | BaseViewModel 全文範本、UiState/DialogEvent、統一錯誤處理鏈 | 基礎設施 agent + 每個頁面 subagent |
| `references/usecase-repo.md` | UseCase、Repository interface+Impl、StateHolder、Model 慣例 | 每個頁面 subagent |
| `references/koin-di.md` | sharedModule/platformModule、KoinInit、新增頁面 DI checklist | 基礎設施 agent + 整合階段主 agent |
| `references/ktor-api.md` | HttpClientFactory(expect/actual)、ApiService、ApiResponse、Endpoints、serializer | 基礎設施 agent |
| `references/navigation3.md` | AppRoute、NavDisplay/entryProvider、Dialog 慣例、MainNavViewModel back stack | 基礎設施 agent + 整合階段主 agent |
| `references/platform-i18n-theme.md` | expect/actual 慣例、多語系（Compose Resources + LocalAppLocale）、Theme 結構 | 基礎設施 agent；頁面 subagent 需要字串/主題時 |

## 改寫工作流程（主 agent 執行）

### Phase 0 — 盤點與規格

1. 掃描目標專案：列出頁面清單、既有 API 呼叫、資料模型、導航關係。
2. 用 TaskCreate 建立任務：基礎設施 1 項 + 每頁 1 項 + 整合 1 項 + 驗收 1 項，並以 blockedBy 設定依賴（頁面任務 blockedBy 基礎設施）。
3. 與使用者確認頁面優先序與範圍後才動工。

### Phase 1 — 基礎設施先行（單一 agent，禁止平行）

所有頁面都依賴這一層，必須先完成並可編譯：

- `api/core/`（讀 `references/ktor-api.md`）
- `base/`（讀 `references/mvvm-viewmodel.md` 的 BaseViewModel 與錯誤處理章節）
- `di/AppModule.kt` 骨架 + 各平台 KoinInit（讀 `references/koin-di.md`）
- `ui/navigation/` 骨架 + App.kt NavDisplay（讀 `references/navigation3.md`）
- `ui/theme/` + 多語系（讀 `references/platform-i18n-theme.md`）

完成標準：專案能 build（Android 至少 `assembleDebug` 過）。

### Phase 2 — 頁面平行改寫（多 subagent）

每頁派一個 subagent。**衝突防線：subagent 禁止修改共用檔**（`AppModule.kt`、`AppRoute.kt`、`App.kt`、`ApiEndpoints.kt`、theme、任何 base/）。subagent 只在 `screen/<feature>/`、`api/repository/<domain>/`、`model/<domain>/` 內新增檔案，最後**回報**需要主 agent 集中登記的清單。

Subagent prompt 模板：

```
你負責將目標專案的「<頁面名>」改寫成本 KMP MVVM 架構。

先讀這些規格（skill 目錄 <skill-path>）：
- references/mvvm-view.md
- references/mvvm-viewmodel.md
- references/usecase-repo.md

原始頁面素材：<目標專案中該頁的檔案路徑清單>

產出（全部放 commonMain，package <package>）：
- screen/<feature>/<Feature>Screen.kt、<Feature>ScreenContent.kt、<Feature>ViewModel.kt
- screen/<feature>/domain/ 內的 UseCase
- api/repository/<domain>/ 的 Repository interface + Impl（若該頁有 API）
- model/<domain>/ 的 @Serializable model（若需要）

禁止事項：
- 不可修改 AppModule.kt、AppRoute.kt、App.kt、ApiEndpoints.kt、base/、ui/theme/
- 不可引入 skill 未列出的第三方依賴
- ScreenContent 內不可出現 ViewModel / koinInject / 導航

完成後回報（我會集中登記）：
1. Koin 待註冊清單（VM / UseCase / Repository，含建構子依賴）
2. AppRoute 待新增路由（含參數）與 entryProvider 接線碼
3. ApiEndpoints 待新增端點
4. 尚缺的共用元件或跨頁狀態（StateHolder）需求
```

### Phase 3 — 整合（主 agent 集中執行，避免衝突）

收齊各 subagent 回報後，由主 agent 一次性修改共用檔：

1. `AppModule.kt`：依 `references/koin-di.md` 的分區慣例登記所有 VM/UseCase/Repository。
2. `AppRoute.kt` + `App.kt` entryProvider：登記所有路由（讀 `references/navigation3.md`）。
3. `ApiEndpoints.kt`：登記所有端點。
4. 補跨頁共用元件/StateHolder。

### Phase 4 — 驗收

每頁逐項核對下方 checklist，最後跑 build：

```bash
JAVA_HOME="<Android Studio JBR 路徑>" ./gradlew :composeApp:assembleDebug
./gradlew :composeApp:linkDebugFrameworkIosSimulatorArm64   # 目標含 iOS 時
```

#### 每頁驗收 checklist

- [ ] 檔案齊備且位置正確：Screen / ScreenContent / ViewModel（+ domain/、dialog/、component/ 視需要）
- [ ] ScreenContent 只依賴 UiState + event lambda，無 ViewModel/DI/導航/平台 API
- [ ] UiEvent 為 sealed，命名 `<Feature>ScreenEvent`，定義於 ScreenContent 檔
- [ ] UiState 為單一 data class，StateFlow + `update {}`
- [ ] ViewModel 繼承 BaseViewModel，無 try-catch 散落、無平台 import
- [ ] Screen 已掛 `BindApiError(viewModel)`（漏掛 = 錯誤發了畫面沒反應）
- [ ] Dialog 由單一 `dialogUiState: StateFlow<DialogEvent?>` 驅動，非多個 Boolean
- [ ] UseCase/Repository 分層正確，Repository 有 interface、Impl 用 `toResult()` 收斂
- [ ] Koin 已註冊且建構子依賴可解析；用到的平台介面 Android/iOS 兩邊都有綁定
- [ ] AppRoute 已含該頁路由、entryProvider 已接線
- [ ] @Preview 存在且可渲染
- [ ] build 通過

## 常見翻車點（主 agent 要盯的）

- **平行 subagent 改到共用檔**造成互相覆蓋——嚴格執行「回報制」，共用檔只由主 agent 動。
- **漏掛錯誤處理鏈任一段**（App 根部 ApiErrorHost / 每頁 BindApiError）——ViewModel 有發錯誤但畫面無反應，編譯期不會發現。
- **Koin 平台介面只綁了一邊**——漏綁只在 runtime 第一次 `get()` 時 crash；iOS 缺對應能力用 NoOp 實作補齊。
- 目標專案原本的 Activity/Fragment 邏輯被原封搬進 ViewModel（夾帶 Context）——一律改為 expect/actual 或介面注入。
- 忘記 iOS：commonMain 用了 JVM 專屬 API（如 `java.util.*`）——build iOS framework 才會爆，Phase 4 必跑 iOS link。
- 導航依賴誤用 Android-only 的 `androidx.navigation3` 座標——必須用 JetBrains KMP 座標 `org.jetbrains.androidx.navigation3:navigation3-ui`。
- 雙層成功語意搞混：HTTP 2xx 不等於業務成功——Repository 必須用 `toResult(checkSuccessFlag = true)` 檢查回應信封的 `success` 欄位。
