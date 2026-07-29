# Navigation 3 導航架構（KMP）

本文件記載 本架構的 Navigation 3（Nav3）導航架構：路由定義、back stack 管理、
NavDisplay 組裝，以及「Dialog 即路由」的設計模式。所有 API 用法均忠於本架構實際程式碼。

---

## 目的與原則

1. **單一 back stack、單一導航中樞**：整個 App 只有一條 back stack，由全域導航 ViewModel
   （本架構為 `MainNavViewModel`）以 Compose `SnapshotStateList`（`mutableStateListOf`）持有。
   **禁止在個別 Screen 直接操作 back stack**，所有畫面切換邏輯集中於導航 ViewModel。
2. **路由即型別**：所有路由定義為 `@Serializable sealed interface AppRoute : NavKey`，
   無參數頁用 `data object`，帶參數頁用 `data class`。編譯期即可窮舉所有頁面。
3. **Dialog 即路由**：Dialog 定義為 `sealed interface Dialog : AppRoute` 的子路由，
   以 back stack push/pop 控制顯示/隱藏，系統返回鍵天然優先關閉 Dialog。
4. **導航職責邊界**：
   - 只有 **Screen 層**（`XxxScreen` Composable，非 Content）可觸發導航——實際做法是
     App.kt 的 `entryProvider` 接線時把導航 lambda（`onLoginSuccess` 等）傳給 Screen。
   - **各畫面 ViewModel 不直接導航**，而是透過事件/回呼通知 Screen（例如
     `MainScreen` 以 `MainScreenNavEvent` sealed 事件回拋，由 App.kt 的 entry 轉譯為
     `navViewModel.navXxx()` 呼叫）。
   - 例外：**導航 ViewModel 本身可注入其他基礎設施元件**。本架構 `MainNavViewModel`
     注入 `DataSyncManager` 與 `IotHubConnectionController`，讓「登入後啟動同步」、
     「登出時停止同步/斷開 IoT Hub」等副作用與導航動作綁定在同一個具名方法中。
5. **具名導航方法**：導航 ViewModel 對外只暴露具名方法（`navFromLoginToGameSetting()`、
   `navToMainScreen()`…），底層的 `navigate` / `replaceCurrent` / `navigateAndClear`
   一律為 `private`，避免呼叫端任意組合 back stack 操作。

---

## 依賴

`gradle/libs.versions.toml`（本架構實際條目）：

```toml
[versions]
androidx-lifecycle-navigation3 = "2.10.0"
# Navigation (Phase 5)
multiplatform-nav3 = "1.1.1"

[libraries]
androidx-lifecycle-viewmodelNavigation3 = { module = "org.jetbrains.androidx.lifecycle:lifecycle-viewmodel-navigation3", version.ref = "androidx-lifecycle-navigation3" }
# Navigation 3 KMP (Phase 5)
jetbrains-navigation3-ui = { module = "org.jetbrains.androidx.navigation3:navigation3-ui", version.ref = "multiplatform-nav3" }
```

`composeApp/build.gradle.kts` 的 `commonMain.dependencies`：

```kotlin
implementation(libs.androidx.lifecycle.viewmodelNavigation3)  // ViewModelStore entry decorator
implementation(libs.jetbrains.navigation3.ui)                 // NavDisplay、entryProvider、NavKey
```

> 注意：使用的是 **JetBrains KMP 版**（`org.jetbrains.androidx.*`），不是 Android 原生的
> `androidx.navigation3`。import 路徑仍是 `androidx.navigation3.*` / `androidx.lifecycle.viewmodel.navigation3.*`。

---

## AppRoute 範本

```kotlin
package com.example.app.ui.navigation

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

/**
 * 全域路由定義
 *
 * 採用 Navigation 3 sealed interface 方案（單一模組）
 * - 主畫面路由：繼承 [AppRoute]
 * - Dialog 路由：繼承 [AppRoute.Dialog]，以 back stack 方式控制顯示/隱藏
 */
@Serializable
sealed interface AppRoute : NavKey {

    // ──────────────────────────────────────────
    // 主畫面路由
    // ──────────────────────────────────────────

    @Serializable
    data object Splash : AppRoute

    @Serializable
    data object Home : AppRoute

    /**
     * @param id 詳細頁目標資料 ID（KDoc 說明每個參數的用途與影響）
     */
    @Serializable
    data class Detail(val id: String) : AppRoute

    // ──────────────────────────────────────────
    // Dialog 路由（透過 back stack 控制顯示/隱藏）
    // ──────────────────────────────────────────

    @Serializable
    sealed interface Dialog : AppRoute {

        @Serializable
        data object Confirm : Dialog

        @Serializable
        data object Setting : Dialog
    }
}
```

慣例重點：

- 每個路由（含 sealed interface 本身）都標 `@Serializable`——Nav3 的狀態保存需要它。
- 帶參數路由（如本架構 `Overview(val isFromLogin: Boolean)`）以 KDoc 註明參數語意，
  特別是會影響返回行為/後續流程的旗標。
- 以 `// ──` 分隔線 + 區塊註解分組（主畫面 / Dialog / Dialog 再依所屬畫面分小組）。

## 導航 ViewModel 範本（back stack 持有與操作）

```kotlin
package com.example.app.ui.navigation

import androidx.compose.runtime.mutableStateListOf

class MainNavViewModel : BaseViewModel() {

    /** Navigation 3 back stack，初始為 Splash 畫面 */
    val backStack = mutableStateListOf<AppRoute>(AppRoute.Splash)

    // ── 內部導航輔助方法（一律 private）─────────────────

    /**
     * 替換當前畫面（先推入新的，再彈出舊的）
     * 注意：先 add 再 remove，確保 Compose 在同一幀看到兩個 entry，轉場動畫才能正確執行
     */
    private fun replaceCurrent(route: AppRoute) {
        val old = backStack.lastOrNull()
        backStack.add(route)
        old?.let { backStack.remove(it) }
    }

    /** 標準導航（推入新畫面，保留返回堆疊） */
    private fun navigate(route: AppRoute) {
        backStack.add(route)
    }

    /**
     * 清空並導航（先推入新畫面，再清空舊的堆疊）——登入成功後等不可返回的場景
     * 注意：同樣先 add 再清空其他元素，理由同上（轉場動畫）
     */
    private fun navigateAndClear(route: AppRoute) {
        backStack.add(route)
        while (backStack.size > 1) {
            backStack.removeAt(0)
        }
    }

    // ── 系統返回行為 ─────────────────────────────────

    /**
     * @return true 表示成功返回；false 表示已到達根畫面（改為顯示退出確認對話框）
     */
    fun goBack(): Boolean {
        // Dialog 路由優先處理
        if (backStack.lastOrNull() is AppRoute.Dialog) {
            backStack.removeAt(backStack.lastIndex)
            return true
        }
        return if (backStack.size > 1) {
            backStack.removeAt(backStack.lastIndex)
            true
        } else {
            showExitConfirmDialog()   // 根畫面：不 pop，改出退出確認
            false
        }
    }

    // ── 對外只暴露具名方法 ────────────────────────────

    fun navFromSplashToHome() = replaceCurrent(AppRoute.Home)
    fun navToDetail(id: String) = navigate(AppRoute.Detail(id))
    fun navToHomeAndClear() = navigateAndClear(AppRoute.Home)

    // ── Dialog 導航（透過 back stack 控制）─────────────

    /** 推入 Dialog 路由至 back stack（去重：已在 stack 中則不重複推入） */
    fun showDialog(dialog: AppRoute.Dialog) {
        if (backStack.none { it == dialog }) {
            navigate(dialog)
        }
    }

    /** 關閉最上層的 Dialog（僅當最上層確為 Dialog 時） */
    fun dismissTopDialog() {
        if (backStack.lastOrNull() is AppRoute.Dialog) {
            backStack.removeAt(backStack.lastIndex)
        }
    }

    /** 關閉指定的 Dialog（不管它在 stack 哪個位置） */
    fun dismissDialog(dialog: AppRoute.Dialog) {
        backStack.remove(dialog)
    }
}
```

back stack 的實際操作方式總結：**沒有任何 Navigator/Controller 物件**，就是直接對
`SnapshotStateList<AppRoute>` 做 `add` / `remove` / `removeAt`，NavDisplay 觀察此 list 重組。

---

## NavDisplay 組裝範本

App 根 Composable 中組裝（package/route 為範例，API 與參數忠於本架構 `App.kt`）：

```kotlin
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay

@Composable
fun App() {
    val navViewModel: MainNavViewModel = koinViewModel()

    NavDisplay(
        backStack = navViewModel.backStack,
        onBack = { navViewModel.goBack() },
        entryDecorators = listOf(
            rememberSaveableStateHolderNavEntryDecorator(),  // rememberSaveable 狀態隔離
            rememberViewModelStoreNavEntryDecorator()        // 每個 entry 有自己的 ViewModelStore
        ),
        transitionSpec = { fadeIn() togetherWith fadeOut() },
        popTransitionSpec = { fadeIn() togetherWith fadeOut() },
        predictivePopTransitionSpec = { fadeIn() togetherWith fadeOut() },
        entryProvider = entryProvider {

            // ── 主畫面路由 ─────────────────────────────
            entry<AppRoute.Home> {
                HomeScreen(
                    // Screen 只拿到「導航 lambda」，不認識 back stack
                    onOpenDetail = { id -> navViewModel.navToDetail(id) }
                )
            }

            // 帶參數路由：entry lambda 收到 route 實例，直接取參數
            entry<AppRoute.Detail> { route ->
                DetailScreen(
                    id = route.id,
                    backEvent = { navViewModel.goBack() }
                )
            }

            // ViewModel 以事件回拋、Screen（entry 接線處）轉譯為導航的範式
            entry<AppRoute.Main> {
                MainScreen(
                    mainScreenNavEvent = { event ->
                        when (event) {
                            MainScreenNavEvent.EditScorecard -> navViewModel.navFromScoreToEditScore()
                            MainScreenNavEvent.Logout -> navViewModel.logoutWith(LogoutReason.Manual)
                        }
                    }
                )
            }

            // ── Dialog 路由 ────────────────────────────
            entry<AppRoute.Dialog.Confirm> { /* Dialog 內容或留空，見下節 */ }
        }
    )
}
```

組裝要點（皆為本架構實況）：

- `backStack` 直接傳入導航 ViewModel 的 `SnapshotStateList`。
- `onBack` 統一導到 `navViewModel.goBack()`。本架構在此有一段攔截：若當前是
  `Overview(isFromLogin = true)` 且已註冊 `OverviewViewModel` 參考，改呼叫
  `vm.onBackPressed()` 讓畫面先出確認彈窗（以 `remember { mutableStateOf<OverviewViewModel?>(null) }`
  + entry 內 `DisposableEffect` 註冊/清除參考來實作）。
- `entryDecorators` 兩件套是必配：沒有 `rememberViewModelStoreNavEntryDecorator()`，
  entry 內的 `koinViewModel()` 不會隨頁面銷毀而清除。
- 三種 transitionSpec（前進/pop/predictive pop）本架構統一用 `fadeIn() togetherWith fadeOut()`。
- **SavedStateConfiguration**：`AppRoute.kt` 的 KDoc 寫「SavedStateConfiguration 設定於 App 中」，
  但目前 `App.kt` 實際上**未**顯式傳入 `SavedStateConfiguration`——狀態保存僅靠上述兩個
  entryDecorators。移植時照實跟隨現況即可，勿發明不存在的參數。

---

## Dialog 路由模式

機制設計（三段式）：

1. **定義**：Dialog 宣告為 `AppRoute.Dialog` 的 `data object` 子路由（見 AppRoute 範本）。
2. **顯示/隱藏 = push/pop**：
   - 顯示：`navViewModel.showDialog(AppRoute.Dialog.Confirm)`（內建去重）。
   - 關閉：`dismissTopDialog()`（只關最上層）或 `dismissDialog(x)`（指定關閉）。
   - 系統返回鍵：`goBack()` 先檢查 `backStack.lastOrNull() is AppRoute.Dialog`，
     是則 pop Dialog 並回傳 true——**返回鍵天然優先關 Dialog、不會誤退畫面**。
3. **渲染**：每個 Dialog 路由都要在 `entryProvider` 註冊 `entry<AppRoute.Dialog.Xxx>`，
   entry 內容即 Dialog 的 Composable（可用 `androidx.compose.ui.window.Dialog` 包裹內容
   疊在畫面上）。

**本架構目前實況（照實記載）**：Dialog 路由與 back stack API 已完整建好，但
`App.kt` 中所有 `entry<AppRoute.Dialog.*>` 的內容目前為空或 TODO（標註 P5-21 / P5-24），
例如 Score 系列 Dialog 附註「Score dialogs are rendered inside ScoreScreen by
ScoreScreenViewModel dialog state」——即**實際的 Dialog 顯示目前是由各畫面 ViewModel 的
`DialogUiState` 狀態在畫面內渲染**（`OverviewViewModel.showDialog(DialogUiState.X)`、
`MainScreenViewModel.dismissDialog()` 等），back stack Dialog 路由是預留的目標機制。
移植新 Dialog 時：優先沿用該畫面既有的 DialogUiState 模式；若要走路由模式，
必須同時補上 entry 渲染內容，否則 push 之後畫面會是空 entry。

另外還有一類**不進 back stack 的系統級 Dialog**：例如退出確認對話框，由
`MainNavViewModel` 的 `showExitDialog: StateFlow<Boolean>` 控制，`App.kt` 在 NavDisplay
**之外**以 `if (showExitDialog) { Dialog(...) { TwoButtonDialogContent(...) } }` 渲染。
適用於「不屬於任何頁面、也不該被路由狀態保存」的全域對話框。

---

## 常見錯誤

1. **replace / clear 時先 remove 再 add** → 轉場動畫壞掉。必須**先 `add` 新 entry**，
   讓 Compose 在同一幀同時看到新舊兩個 entry，再移除舊的（`replaceCurrent` /
   `navigateAndClear` 的註解即為此而寫）。
2. **在 Screen 或各畫面 ViewModel 直接改 backStack** → 違反單一導航中樞原則。
   Screen 只能呼叫接線進來的導航 lambda；ViewModel 只能發事件請 Screen 轉發。
3. **忘記 `rememberViewModelStoreNavEntryDecorator()`** → entry 內 `koinViewModel()`
   取得的 ViewModel 生命週期不跟頁面走，返回後狀態殘留。
4. **路由或 sealed interface 忘記標 `@Serializable`** → NavKey 狀態保存失敗。
5. **Dialog 路由 push 了但 entry 沒有內容** → NavDisplay 頂層變成空白 entry，畫面「消失」。
   走路由 Dialog 模式時 entry 渲染與 push/pop 必須成對完成。
6. **對外暴露泛用 `navigate(route)`** → 呼叫端任意組合導致 back stack 不可預期。
   一律包成具名方法（`navFromXxxToYyy()`），把流程語意與副作用（同步啟停、狀態更新）封在方法裡。
7. **用 `androidx.navigation3` 的 Android-only 座標** → iOS 編不過。必須用
   `org.jetbrains.androidx.navigation3:navigation3-ui` 與
   `org.jetbrains.androidx.lifecycle:lifecycle-viewmodel-navigation3`。

---

## 命名與位置範例（相對結構）

| 主題 | 檔案 |
|------|------|
| 路由定義（8 個主畫面 + 13 個 Dialog 路由） | `commonMain: ui/navigation/AppRoute.kt` |
| 導航 ViewModel（back stack、goBack、Dialog API、登出流程、同步事件監聽） | `commonMain: ui/navigation/MainNavViewModel.kt` |
| NavDisplay 組裝、entryProvider 接線、退出確認 Dialog | `commonMain: App.kt` |
| ViewModel 事件回拋範例（`MainScreenNavEvent`） | `commonMain: screen/main/MainScreen.kt` |
| 畫面內 DialogUiState 模式範例 | `commonMain: screen/overview/OverviewViewModel.kt` |
| 依賴版本 | `gradle/libs.versions.toml`（`multiplatform-nav3 = "1.1.1"`、`androidx-lifecycle-navigation3 = "2.10.0"`） |

實例補充：

- `MainNavViewModel` 建構子注入 `DataSyncManager` 與 `IotHubConnectionController`；
  `navFromLoginToGameSetting()` 在導航前呼叫 `dataSyncManager.startAll()` 並啟動 IoT Hub 連線，
  `performLogoutTo()` 在 `navigateAndClear` 前 `stopAll()` + `iotHubConnectionController.stop()`。
- 帶參數路由實例：`AppRoute.Overview(val isFromLogin: Boolean)`——同一畫面依來源
  （登入流程 vs. 比賽中編輯）呈現不同返回行為與下一步（`navToWelcomePage()` vs. `navToMainScreen()`）。
- back stack 初始值為 `AppRoute.Splash`；根畫面按返回不 pop，改觸發 `showExitConfirmDialog()`，
  由 App.kt 在 NavDisplay 外層渲染退出確認 Dialog，確認後呼叫 `onExitApp()`。
