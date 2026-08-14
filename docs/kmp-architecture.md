[← 回目錄](README.md)

# kmp-architecture

Kotlin Multiplatform 的 MVVM 架構規格。

## 作用

這個 plugin 只有一個 skill：`kmp-mvvm-architecture`。

它是一份**架構規格書**，不是工具。它告訴 Claude 你的 KMP 專案要長什麼樣子，然後由 Claude 照著改寫。

它適用於三種情況：

1. 把現有 Android 或 KMP 專案改寫成這套架構。
2. 只改寫其中幾個頁面。
3. 在既有專案新增一個符合這套架構的頁面。

## 安裝

```
/plugin marketplace add Soda3752/skills
/plugin install kmp-architecture@soda-skills
```

## 使用方式

說出你的目標。例如：

```
照這套架構改寫
把 XX 專案改成跟這個一樣的架構
用這個架構重寫登入頁
建立符合本架構的新頁面
開多個 subagent 改寫頁面
```

## 技術選型

所有版本統一管理在 `gradle/libs.versions.toml`。**禁止在 `build.gradle.kts` 寫死版本號。**

| 層面 | 方案 | 版本基準 |
| --- | --- | --- |
| 語言與平台 | Kotlin Multiplatform（Android minSdk 30 + iOS） | Kotlin 2.3.20 |
| UI | Compose Multiplatform，單模組 `composeApp` | — |
| DI | Koin | 4.2.0 |
| 網路 | Ktor（Android 用 OkHttp，iOS 用 Darwin） | 3.4.2 |
| 導航 | Navigation3 | 1.1.1 |
| ViewModel | androidx.lifecycle KMP 版 | 2.10.0 |
| 序列化 | Kotlinx Serialization | 1.10.0 |
| 本地儲存 | Multiplatform Settings | 1.3.0 |
| 日誌 | Napier | 2.7.1 |
| 圖片 | Coil 3 | 3.4.0 |
| 多語系 | Compose 內建資源 + 自寫 `LocalAppLocale` | — |

多語系**不要引入 Lyricist**。舊的選型文件曾列出它，但實際專案沒有使用。

## 十條核心鐵律

所有 subagent 都必須遵守這十條。

**1. ScreenContent 是純函式 UI。**
它只吃 `UiState` 和 `(UiEvent) -> Unit`。
禁止取得 ViewModel。禁止 `koinInject`。禁止導航。禁止平台 API。
必須附 `@Preview`。

**2. UiState 是單一 data class。**
用 `MutableStateFlow` 加 `update {}` 維護。定義在 ViewModel 同一個檔案。

**3. UiEvent 是 sealed class 或 interface。**
定義在 ScreenContent 檔案內。命名為 `<Feature>ScreenEvent`。

**4. ViewModel 繼承 BaseViewModel。**
不要散落 try-catch。API 呼叫用 `viewModelScope.launch { showLoading(); …; hideLoading() }` 顯式包夾。結果交給 `handleApiResult` 或 `emitApiRetryError`。
禁止 import 任何 Android 或 iOS 平台型別。
禁止發明 BaseViewModel 沒有的 helper。

**5. 業務邏輯抽 UseCase。**
放在 `screen/<feature>/domain/`。用 `suspend operator fun invoke` 慣例。
資料存取走 Repository 介面。interface 與 Impl 成對。Impl 內用 `toResult()` 收斂錯誤。上層只面對 `Result`。

**6. 一切依賴由 Koin 注入。**
用建構子注入。UseCase、Repository、StateHolder 一律註冊為 `single`。
**ViewModel 之間禁止互相依賴。** 跨頁的執行期狀態抽成 StateHolder。

**7. 導航只發生在 Screen 層。**
路由是 `@Serializable` 的 `AppRoute : NavKey` sealed interface。
back stack 由 MainNavViewModel 持有。

**8. commonMain 優先。**
只有真正碰平台 API 的程式碼才進 androidMain 或 iosMain。
平台介面綁定必須 Android 與 iOS **兩邊成對**。iOS 缺能力時給 NoOp 實作。

**9. 時間函數一律寫在 TimeUtil。**
用 `kotlin.time.Clock`。不要用 `kotlinx.datetime.Clock`。

**10. 命名與位置照規格表。**
不要自創目錄或後綴。

## 改寫流程

改寫分五個階段。主 agent 執行 Phase 0、3、4。Phase 2 由多個 subagent 平行執行。

### Phase 0 — 盤點與規格

1. 掃描目標專案。列出頁面清單、既有 API 呼叫、資料模型、導航關係。
2. 建立任務。基礎設施 1 項，每頁 1 項，整合 1 項，驗收 1 項。頁面任務 blockedBy 基礎設施。
3. **與你確認頁面優先序與範圍後才動工。**

### Phase 1 — 基礎設施先行

**這一階段只用一個 agent。禁止平行。**

所有頁面都依賴這一層。它必須先完成，而且可以編譯。

要建立的內容：

- `api/core/`
- `base/`
- `di/AppModule.kt` 骨架，以及各平台的 KoinInit
- `ui/navigation/` 骨架，以及 App.kt 的 NavDisplay
- `ui/theme/` 與多語系

完成標準：Android 的 `assembleDebug` 通過。

### Phase 2 — 頁面平行改寫

每一頁派一個 subagent。

**衝突防線：subagent 禁止修改共用檔。**

共用檔是這些：

```
AppModule.kt
AppRoute.kt
App.kt
ApiEndpoints.kt
ui/theme/
base/ 底下任何檔案
```

subagent 只在這三個位置**新增**檔案：

```
screen/<feature>/
api/repository/<domain>/
model/<domain>/
```

subagent 完成後**回報**四項清單，交給主 agent 集中登記：

1. Koin 待註冊清單。
2. AppRoute 待新增路由。
3. ApiEndpoints 待新增端點。
4. 尚缺的共用元件或跨頁狀態。

### Phase 3 — 整合

主 agent 收齊回報後，**一次性**修改共用檔。

這樣做的原因是：平行的 subagent 同時改同一個檔案會互相覆蓋。

### Phase 4 — 驗收

先逐頁核對檢查清單，再跑 build：

```bash
JAVA_HOME="<Android Studio JBR 路徑>" ./gradlew :composeApp:assembleDebug
./gradlew :composeApp:linkDebugFrameworkIosSimulatorArm64   # 目標含 iOS 時
```

**iOS link 一定要跑。** commonMain 誤用 JVM 專屬 API（例如 `java.util.*`）時，只有這一步會失敗。

### 每頁驗收清單

- [ ] 檔案齊備且位置正確。
- [ ] ScreenContent 只依賴 UiState 與 event lambda。
- [ ] UiEvent 為 sealed，命名正確，定義在 ScreenContent 檔。
- [ ] UiState 為單一 data class，用 StateFlow 加 `update {}`。
- [ ] ViewModel 繼承 BaseViewModel，沒有散落的 try-catch，沒有平台 import。
- [ ] Screen 已掛 `BindApiError(viewModel)`。
- [ ] Dialog 由單一 `dialogUiState` 驅動，不是多個 Boolean。
- [ ] Repository 有 interface，Impl 用 `toResult()` 收斂。
- [ ] Koin 已註冊，建構子依賴可解析。平台介面兩邊都有綁定。
- [ ] AppRoute 已含該頁路由，entryProvider 已接線。
- [ ] `@Preview` 存在且可以渲染。
- [ ] build 通過。

## 七個常見翻車點

這些錯誤**編譯期不會發現**。主 agent 要主動盯。

**1. 平行 subagent 改到共用檔。**
症狀是互相覆蓋。對策是嚴格執行回報制。

**2. 漏掛錯誤處理鏈。**
App 根部要有 ApiErrorHost，每頁要有 BindApiError。漏掛的症狀是 ViewModel 發了錯誤但畫面沒反應。

**3. Koin 平台介面只綁一邊。**
症狀是 runtime 第一次 `get()` 時 crash。iOS 缺能力時用 NoOp 實作補齊。

**4. 舊 Activity 邏輯被原封搬進 ViewModel。**
它會夾帶 Context。一律改成 expect/actual 或介面注入。

**5. 忘記 iOS。**
commonMain 用了 JVM 專屬 API。只有 build iOS framework 才會失敗。

**6. 導航用錯座標。**
不要用 Android-only 的 `androidx.navigation3`。必須用 `org.jetbrains.androidx.navigation3:navigation3-ui`。

**7. 雙層成功語意搞混。**
HTTP 2xx 不等於業務成功。Repository 必須用 `toResult(checkSuccessFlag = true)` 檢查回應信封的 `success` 欄位。

## References

skill 目錄下有七份深入說明。Claude 依需要讀取，你不必自己指定。

| 檔案 | 內容 |
| --- | --- |
| `mvvm-view.md` | Screen、ScreenContent、UiEvent、Preview 範本 |
| `mvvm-viewmodel.md` | BaseViewModel 全文範本、統一錯誤處理鏈 |
| `usecase-repo.md` | UseCase、Repository、StateHolder、Model 慣例 |
| `koin-di.md` | sharedModule、platformModule、新增頁面的 DI 清單 |
| `ktor-api.md` | HttpClientFactory、ApiService、ApiResponse、Endpoints |
| `navigation3.md` | AppRoute、NavDisplay、Dialog 慣例、back stack |
| `platform-i18n-theme.md` | expect/actual 慣例、多語系、Theme 結構 |
