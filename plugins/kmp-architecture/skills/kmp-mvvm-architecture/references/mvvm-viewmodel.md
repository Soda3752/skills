# MVVM ViewModel 模式（BaseViewModel + UiState + 統一錯誤處理）

本文件定義 本架構中 ViewModel 層的標準寫法。所有 ViewModel 一律放在
`commonMain`，繼承 `BaseViewModel`，透過 `StateFlow` 暴露 UiState、`Channel` 發送
一次性事件；錯誤與 Loading 全走 BaseViewModel 事件流，由 UI 層的
`ApiErrorHost` + `BindApiError` 統一呈現。

## 目的與原則

1. **ViewModel 100% 共享**：ViewModel 定義在 `commonMain`，Android / iOS 共用同一份，
   使用 `androidx.lifecycle:lifecycle-viewmodel` KMP 版的 `ViewModel` / `viewModelScope`。
2. **單向資料流**：UI 只讀 `StateFlow<XxxUiState>`，透過呼叫 ViewModel 的
   `onXxxClick()` 方法觸發狀態變更；ViewModel 用 `MutableStateFlow.update {}` 改狀態。
3. **錯誤不落地在 ViewModel**：業務程式碼裡不寫 error dialog / toast 的 UI 邏輯，
   只呼叫 `emitApiRetryError()` / `emitToast()`，剩下交給全域的 `ApiErrorHost` 呈現。
4. **一次性事件與狀態分離**：導航、跳頁、Dialog 開關這種「消費一次」的事件，
   用 `Channel.receiveAsFlow()` 或 nullable `StateFlow<DialogEvent?>`，不要塞進 UiState。
5. **平台無關**：ViewModel 內禁止出現任何 Android / iOS 平台型別（見「常見錯誤」）。

---

## BaseViewModel 範本

以下骨架忠於本架構 `base/BaseViewModel.kt`（僅改 package、移除 參考專案專屬的 FCM
雷擊通知業務），搭配的 `ToastData` / `NotificationData` / `FullScreenWarningEvent` 一併列出。

```kotlin
package com.example.app.base

import androidx.compose.ui.graphics.Color
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.app.api.core.ApiResponse
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

abstract class BaseViewModel : ViewModel() {

    // ── 對 UI 層暴露的事件流（由 BindApiError 統一收集）──────────────
    private val _apiErrorEvent = MutableSharedFlow<APIError>()
    val apiErrorEvent: SharedFlow<APIError> get() = _apiErrorEvent.asSharedFlow()

    private val _toastEvent = MutableSharedFlow<ToastData>()
    val toastEvent: SharedFlow<ToastData> get() = _toastEvent.asSharedFlow()

    private val _loadingState = MutableStateFlow(false)
    val loadingState: StateFlow<Boolean> get() = _loadingState.asStateFlow()

    private val _notificationEvent = MutableSharedFlow<NotificationData>()
    val notificationEvent: SharedFlow<NotificationData> get() = _notificationEvent.asSharedFlow()

    private val _fullScreenWarningEvent = MutableSharedFlow<FullScreenWarningEvent>()
    val fullScreenWarningEvent: SharedFlow<FullScreenWarningEvent> = _fullScreenWarningEvent.asSharedFlow()

    // ── API 結果攔截 helper ─────────────────────────────────────────
    /**
     * 統一展開 Result<ApiResponse<T>>：
     * - HTTP 成功且 data != null → onSuccess(data)
     * - HTTP 成功但 data == null → onDataEmpty（未提供時視為失敗）
     * - HTTP / 網路失敗 → onFailure(e)
     */
    protected inline fun <T> Result<ApiResponse<T>>.handleApiResult(
        onSuccess: (data: T) -> Unit,
        onFailure: (e: Throwable) -> Unit,
        noinline onDataEmpty: (() -> Unit)? = null
    ) {
        this.fold(
            onSuccess = {
                if (it.data != null) {
                    onSuccess(it.data)
                } else {
                    onDataEmpty?.invoke() ?: run {
                        onFailure(IllegalStateException("Data is empty"))
                    }
                }
            },
            onFailure = { onFailure(it) }
        )
    }

    /** 發出「可重試」的 API 錯誤，UI 端顯示 Retry / Cancel 兩鍵 Dialog */
    protected suspend fun emitApiRetryError(
        message: String,
        onRetry: (() -> Unit)? = null,
        onCancel: (() -> Unit)? = null
    ) {
        _apiErrorEvent.emit(APIError(message, onRetry, onCancel))
    }

    // ── Toast / 通知 ────────────────────────────────────────────────
    fun emitToast(title: Any?, message: Any) {
        viewModelScope.launch {
            _toastEvent.emit(ToastData(title, message, isTransparentBackground = true))
        }
    }

    fun emitToastInDialog(title: Any?, message: Any) {
        viewModelScope.launch {
            _toastEvent.emit(ToastData(title, message, isTransparentBackground = false))
        }
    }

    fun emitToast(message: Any) = emitToast(null, message)
    fun emitToastInDialog(message: Any) = emitToastInDialog(null, message)

    fun emitNotification(
        title: Any?,
        message: Any,
        background: Color = Color(0x80333333L.toInt()),
        dismissOnClick: Boolean = true,
    ) {
        viewModelScope.launch {
            _notificationEvent.emit(NotificationData(title, message, background, dismissOnClick))
        }
    }

    // ── 全螢幕警告 ─────────────────────────────────────────────────
    protected fun emitFrontCartWarning() {
        viewModelScope.launch { _fullScreenWarningEvent.emit(FullScreenWarningEvent.FrontCart) }
    }

    protected fun showBatteryWarning() {
        viewModelScope.launch { _fullScreenWarningEvent.emit(FullScreenWarningEvent.Battery(true)) }
    }

    protected fun hideBatteryWarning() {
        viewModelScope.launch { _fullScreenWarningEvent.emit(FullScreenWarningEvent.Battery(false)) }
    }

    protected fun showBatteryLowWarning(isFromSdk: Boolean = false) {
        viewModelScope.launch { _fullScreenWarningEvent.emit(FullScreenWarningEvent.BatteryLow(true, isFromSdk)) }
    }

    protected fun hideBatteryLowWarning() {
        viewModelScope.launch { _fullScreenWarningEvent.emit(FullScreenWarningEvent.BatteryLow(false)) }
    }

    // ── 全螢幕 Loading ─────────────────────────────────────────────
    protected fun showLoading() { _loadingState.value = true }
    protected fun hideLoading() { _loadingState.value = false }

    data class APIError(
        val message: String,
        val retryEvent: (() -> Unit)? = null,
        val cancelEvents: (() -> Unit)? = null
    )
}
```

```kotlin
// ToastData.kt
data class ToastData(
    val title: Any?,          // 可為 compose Res.string.xxx、StringRes 或純字串
    val message: Any,
    val isTransparentBackground: Boolean
)

data class NotificationData(
    val title: Any?,
    val message: Any,
    val background: Color = Color(0x80333333L.toInt()),
    val dismissOnClick: Boolean = true,  // false = 鎖定型通知，點擊不可關閉
)

// FullScreenWarningEvent.kt
sealed class FullScreenWarningEvent {
    data object FrontCart : FullScreenWarningEvent()
    data class Battery(val visible: Boolean) : FullScreenWarningEvent()
    data class BatteryLow(val visible: Boolean, val isFromSdk: Boolean = false) : FullScreenWarningEvent()
}
```

### Protected helper 用途一覽

| 方法 | 何時使用 |
|------|---------|
| `handleApiResult(onSuccess, onFailure, onDataEmpty)` | 每次 Repository 回傳 `Result<ApiResponse<T>>` 後統一展開；取代手寫 `fold` + null 檢查 |
| `emitApiRetryError(message, onRetry, onCancel)` | API 失敗且「使用者可重試」時；`onRetry` 傳入原方法自身形成重試閉包 |
| `emitToast` / `emitToastInDialog` | 輕量提示（1.5 秒自動消失）；`InDialog` 版用於 Dialog 之上（不透明背景） |
| `emitNotification` | 全螢幕覆蓋式通知（如推播內容） |
| `showLoading()` / `hideLoading()` | 呼叫 API 前後包夾，顯示全螢幕 Loading 遮罩 |
| `emitFrontCartWarning` / `showBatteryWarning` 等 | 特定全螢幕警告 Dialog 的開關 |

> 注意：本架構**沒有** `launchWithLoading` 之類的封裝方法。標準寫法是
> `viewModelScope.launch { showLoading(); ... ; hideLoading() }` 手動包夾，請勿自行發明。

---

## ViewModel 範本

慣例三件套：**單一 `data class XxxUiState`（定義在同檔案底部）+ `MutableStateFlow` +
`update {}`**；一次性事件用 `Channel`；Dialog 導向用 nullable 的
`StateFlow<DialogEvent?>` 搭配巢狀在 ViewModel 內的 sealed class。

```kotlin
package com.example.app.screen.sample

import androidx.lifecycle.viewModelScope
import com.example.app.base.BaseViewModel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class SampleViewModel(
    private val sampleRepository: SampleRepository,   // 建構子注入（Koin）
) : BaseViewModel() {

    // 1) 畫面狀態：單一 UiState + StateFlow
    private val _uiState = MutableStateFlow(SampleUiState())
    val uiState: StateFlow<SampleUiState> = _uiState.asStateFlow()

    // 2) Dialog 導向：nullable StateFlow<DialogEvent?>，null 表示無 Dialog
    private val _dialogUiState = MutableStateFlow<DialogEvent?>(null)
    val dialogUiState: StateFlow<DialogEvent?> = _dialogUiState.asStateFlow()

    // 3) 一次性事件（導航等）：Channel + receiveAsFlow，保證只被消費一次
    private val _submitSuccessEvent = Channel<Unit>()
    val submitSuccessEvent = _submitSuccessEvent.receiveAsFlow()

    // 開 Dialog：直接 update 成對應的 DialogEvent
    fun onItemClick(item: String) {
        _dialogUiState.update { DialogEvent.ItemDetail(item) }
    }

    fun onDismissDialog() {
        _dialogUiState.value = null
    }

    // 標準 API 呼叫：launch + showLoading/hideLoading + handleApiResult
    fun onSubmitClick() {
        viewModelScope.launch {
            showLoading()
            val result = sampleRepository.submit(_uiState.value.inputText)
            hideLoading()
            result.handleApiResult(
                onSuccess = { data ->
                    _uiState.update { it.copy(items = data.items) }
                    _submitSuccessEvent.send(Unit)
                },
                onFailure = { e ->
                    // 錯誤只往上拋給 ApiErrorHost，onRetry 形成重試閉包
                    emitApiRetryError(e.message ?: "Submit Failed", onRetry = {
                        onSubmitClick()
                    })
                }
            )
        }
    }

    // Dialog 一次性事件的 sealed class（照 LoginViewModel 慣例：巢狀在 ViewModel 內）
    sealed class DialogEvent {
        data class ItemDetail(val item: String) : DialogEvent()
        data object Setting : DialogEvent()
    }
}

// UiState 定義在 ViewModel「同檔案底部」，欄位全部給預設值
data class SampleUiState(
    val inputText: String = "",
    val items: List<String> = emptyList(),
    val isLoading: Boolean = false,
)
```

UI 端消費方式：

```kotlin
@Composable
fun SampleScreen(viewModel: SampleViewModel = koinViewModel(), onNavigateNext: () -> Unit) {
    BindApiError(viewModel)                       // 掛載統一錯誤處理（見下節）
    val uiState by viewModel.uiState.collectAsState()
    val dialogEvent by viewModel.dialogUiState.collectAsState()

    LaunchedEffect(Unit) {
        viewModel.submitSuccessEvent.collect { onNavigateNext() }   // 一次性事件
    }
    when (val event = dialogEvent) {
        is SampleViewModel.DialogEvent.ItemDetail ->
            ItemDetailDialog(item = event.item, onDismiss = viewModel::onDismissDialog)
        else -> Unit
    }
    // ... 畫面內容讀取 uiState
}
```

---

## 統一錯誤處理

錯誤處理鏈（文字流程）：
```
ViewModel 業務方法
  └─ result.handleApiResult(onFailure = { emitApiRetryError(...) })
       └─ BaseViewModel._apiErrorEvent (SharedFlow<APIError>)
            └─ BindApiError(viewModel)          ← 每個 Screen 掛一次
                 └─ LocalApiErrorController.current.showError(...)
                      └─ ApiErrorHost           ← App 根部掛一次
                           └─ ApiErrorDialog（Retry / Cancel 全域 Dialog）
```

Toast、Loading、Notification、FullScreenWarning 也走同一條鏈：
`emitToast` / `showLoading` → 對應 Flow → `BindApiError` 收集 →
`ApiErrorController` → `ApiErrorHost` 渲染對應 Dialog / 覆蓋層。三個角色：

1. **`ApiErrorController`（interface）**：定義 `showError` / `dismiss` / `showToast` /
   `showNotification` / `showFullScreenWarning` / `showLoading` / `hideLoading`。
   透過 `staticCompositionLocalOf` 的 `LocalApiErrorController` 提供給整棵 UI 樹；
   未包在 `ApiErrorHost` 內取用會直接 `error(...)`。
2. **`ApiErrorHost`（App 根部，掛一次）**：持有所有錯誤/Toast/Loading 的
   `mutableStateOf` 狀態，建立 controller 實作並以
   `CompositionLocalProvider(LocalApiErrorController provides controller)` 往下提供，
   在最外層渲染 `ApiErrorDialog`、`FullScreenLoadingDialog`、`ToastDialog` 等。
3. **`BindApiError`（每個 Screen 掛一次）**：橋接器，用多個 `LaunchedEffect(viewModel)`
   收集 ViewModel 的五條事件流，轉呼叫 controller。

掛載範例：

```kotlin
// App 根部（如 App.kt / MainViewController 內容）— 全 App 只掛一次
@Composable
fun App() {
    AppTheme {
        ApiErrorHost { safePadding ->
            // NavDisplay / Navigator 與所有畫面
            AppNavigation(safePadding)
        }
    }
}

// 每個使用 BaseViewModel 子類的 Screen — 各掛一次
@Composable
fun SampleScreen(viewModel: SampleViewModel = koinViewModel()) {
    BindApiError(viewModel)
    // ... 其餘 UI
}
```

`BindApiError` 內部即是五個 `LaunchedEffect(viewModel)`，分別收集 `apiErrorEvent` /
`toastEvent` / `loadingState` / `notificationEvent` / `fullScreenWarningEvent`
並轉呼叫 controller 對應方法；新增事件流時須同步在此補收集。

### DialogViewState（Dialog 內部狀態的輔助型別）

Dialog 自身若需要「初始化完成才可顯示」的狀態，用 `base/DialogViewState.kt`：

```kotlin
sealed class DialogViewState<out T> {
    data object Idle : DialogViewState<Nothing>()            // 尚未初始化，不應顯示
    data class Ready<T>(val data: T) : DialogViewState<T>()  // 已就緒，可顯示
}
val <T> DialogViewState<T>.dataOrNull: T? get() = (this as? DialogViewState.Ready)?.data
```

---

## 常見錯誤

1. **在 ViewModel 內散落 try-catch 並自己組錯誤 UI 狀態**。
   錯誤一律 `emitApiRetryError()` / `emitToast()` 上拋，UI 呈現交給 `ApiErrorHost`。
2. **import 平台型別**。ViewModel 位於 `commonMain`，禁止：
   `android.content.Context`、`android.content.Intent`、`androidx.activity.*`、
   `platform.UIKit.*`、`platform.Foundation.*` 等。平台能力一律抽介面
   （expect/actual 或 commonMain interface + 平台實作）由 Koin 注入。
3. **持有 Composable / Context / View 參考**。ViewModel 不可接收
   `@Composable` lambda 或 `LocalContext.current` 的產物；需要觸發 UI 行為時
   改用事件流（Channel / SharedFlow）通知 UI 層自行處理。
4. **把一次性事件塞進 UiState**（如 `navigateToNext: Boolean`）。
   旋轉 / 重組會重複觸發；請用 `Channel.receiveAsFlow()`。
5. **忘記掛 `BindApiError`**。ViewModel 有發 `emitApiRetryError` 但畫面沒反應，
   九成是該 Screen 沒掛 `BindApiError(viewModel)`，或 App 根部沒包 `ApiErrorHost`。
6. **`MutableStateFlow` 直接 `.value = _uiState.value.copy(...)` 多執行緒競態**。
   一律用 `_uiState.update { it.copy(...) }`。
7. **自行發明 `launchWithLoading` 等封裝**。維持
   `viewModelScope.launch { showLoading(); ...; hideLoading() }` 顯式寫法，與既有風格一致。
8. **時間邏輯直接呼叫 `kotlinx.datetime.Clock`**。時間函數寫在 `TimeUtil`，用 `kotlin.time.Clock`。

---

## 命名與位置範例（相對結構）

| 檔案 | 角色 |
|------|------|
| `commonMain: base/BaseViewModel.kt` | 基底類別本體（另含 參考專案專屬的 `collectFcmEvent` FCM 雷擊通知處理，範本已略去） |
| `commonMain: base/ApiErrorController.kt` | Controller 介面 + `LocalApiErrorController` |
| `commonMain: base/ApiErrorHost.kt` | 全域錯誤/Toast/Loading/通知的宿主 Composable |
| `commonMain: base/BindApiError.kt` | ViewModel 事件流 → Controller 的橋接 Composable |
| `commonMain: base/DialogViewState.kt` | Dialog Idle/Ready 狀態輔助型別 |
| `commonMain: base/ToastData.kt` | `ToastData` / `NotificationData` / `StringRes`（帶 fallback 的多語系過渡型別） |
| `commonMain: base/FullScreenWarningEvent.kt` | 全螢幕警告事件 sealed class |
| `commonMain: screen/welcome/WelcomeViewModel.kt` | 最簡實例：單一 UiState + `Channel<Unit>` 一次性 skip 事件 |
| `commonMain: screen/login/LoginViewModel.kt` | 完整實例：多 StateFlow（`uiState` / `systemBarUiState` / `dialogUiState`）、巢狀 `DialogEvent` sealed class、`handleApiResult` / `emitApiRetryError` 重試閉包、UiState 定義於檔案底部 |
