# MVVM View 層：Screen / ScreenContent 雙檔分離模式

本文件定義本架構中 View 層（Compose UI）的標準寫法。所有新畫面、Dialog、以及從既有 Android 專案移植過來的 UI 都必須遵循此模式。

## 目的與原則

- **雙檔分離**：每個畫面拆成兩個檔案——
  - `XxxScreen.kt`：**接線層**。負責取得 ViewModel（`koinViewModel()`）、收集 UiState（`collectAsStateWithLifecycle()`）、把 UiEvent 轉發給 ViewModel、用 `LaunchedEffect` 收集一次性事件並執行導航 callback、以及根據 dialog 狀態掛載 Dialog。
  - `XxxScreenContent.kt`：**純 UI 層**。只接收 `UiState` 資料與 `(XxxScreenEvent) -> Unit` 事件 lambda，不認識 ViewModel、不認識 Koin、不做導航。因此可以直接 `@Preview`。
- **雙向資料流（UDF）**：State 下行（ViewModel → Content）、Event 上行（Content → Screen → ViewModel）。Content 內部不持有業務狀態，只允許持有純動畫/暫時性 UI 狀態（`remember { mutableStateOf(...) }`）。
- **一次性事件用 Channel**：導航、Toast 等只該發生一次的事件，在 ViewModel 以 `Channel<Unit>().receiveAsFlow()` 曝露，由 Screen 在 `LaunchedEffect` 中 `collect` 後呼叫外部傳入的導航 lambda（如 `onLoginSuccess: () -> Unit`）。Screen 本身不知道導航目的地，只呼叫 caller 給的 callback。
- **定義位置慣例**：
  - `XxxScreenEvent` sealed class → 定義在 `XxxScreenContent.kt` 檔案頂部。
  - `XxxUiState` data class → 定義在 `XxxViewModel.kt` 檔案內（ViewModel class 之後）。
- **例外**：極簡單、無互動表單的畫面（如 `WelcomeScreen`）目前允許 Screen 單檔直接寫 UI，但**新畫面一律採雙檔分離**。

## 目錄結構

每個 feature 一個目錄，位於 `commonMain/kotlin/.../screen/<feature>/`：

```
screen/login/
├── LoginScreen.kt          # 接線層（ViewModel、事件轉發、一次性事件、Dialog 掛載）
├── LoginScreenContent.kt   # 純 UI + LoginScreenEvent sealed class + @Preview
├── LoginViewModel.kt       # ViewModel + LoginScreenUiState
├── component/              # 該頁專屬的可重用元件（如 TopSystemBar.kt）
├── dialog/                 # 該頁的 Dialog；每個 dialog 自成子目錄，同樣三件套
│   ├── LoginConfirmDialog.kt        # 簡單 dialog 可單檔
│   ├── erpselect/
│   │   ├── ErpSelectDialog.kt           # Dialog 接線層
│   │   ├── ErpSelectDialogContent.kt    # Dialog 純 UI
│   │   └── ErpSelectDialogViewModel.kt  # Dialog 專屬 ViewModel
│   └── selecthole/
│       ├── SelectHoleDialog.kt
│       └── SelectHoleViewModel.kt
└── domain/                 # 該頁專屬 UseCase（如 FetchAllInfoUseCase.kt）
```

- 跨頁共用元件放 `ui/component/`（如 `GradientButton`、`LoadingIcon`），跨頁共用 UseCase 放共用 `usecase/`；**只有該頁使用**的才放進 feature 目錄的 `component/`、`domain/`。
- Screen、ScreenContent、ViewModel 三檔平放在 feature 目錄根層，不再包子目錄。

## 範本程式碼

以下以虛構的 `Sample` feature 示範，欄位簡化為 `name`、`isLoading`。骨架（函式簽名、collect 方式、事件轉發、Preview 參數）忠於 `LoginScreen.kt` / `LoginScreenContent.kt` 原始寫法，可直接改名套用。

### SampleScreen.kt（接線層）

```kotlin
package com.example.app.screen.sample

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import org.koin.compose.viewmodel.koinViewModel

@Composable
fun SampleScreen(
    modifier: Modifier = Modifier,
    viewModel: SampleViewModel = koinViewModel(),
    onSubmitSuccess: () -> Unit,          // 導航 callback 由外部（NavHost 層）注入
) {
    // 慣例：畫面頂部掛共用效果，例如 BindApiError(viewModel)、KeepScreenOnEffect(...)
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val dialogUiState by viewModel.dialogUiState.collectAsStateWithLifecycle()

    // 一次性事件：以 viewModel 為 key，收集 Channel-backed Flow 後呼叫導航 callback
    LaunchedEffect(viewModel) {
        viewModel.submitSuccessEvent.collect {
            onSubmitSuccess.invoke()
        }
    }

    SampleScreenContent(
        modifier = modifier,
        uiState = uiState,
        onEvent = { event ->
            when (event) {
                SampleScreenEvent.NameClick -> viewModel.onNameClick()
                SampleScreenEvent.SubmitClick -> viewModel.onSubmitClick()
            }
        },
    )

    // Dialog 掛載：由 ViewModel 的 dialogUiState（sealed class，null = 不顯示）驅動
    dialogUiState.let { state ->
        when (state) {
            is SampleViewModel.DialogEvent.EditName -> {
                // EditNameDialog(
                //     initialName = state.name,
                //     onDismiss = viewModel::onDismissDialog,
                //     onConfirm = { viewModel.onNameChanged(it) },
                // )
            }

            null -> Unit
        }
    }
}
```

### SampleScreenContent.kt（純 UI + Event 定義 + Preview）

```kotlin
package com.example.app.screen.sample

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview

/** 本畫面所有使用者操作事件（Event 上行），定義在 Content 檔案頂部 */
sealed class SampleScreenEvent {
    data object NameClick : SampleScreenEvent()
    data object SubmitClick : SampleScreenEvent()
}

@Composable
fun SampleScreenContent(
    modifier: Modifier = Modifier,
    uiState: SampleUiState,
    onEvent: (SampleScreenEvent) -> Unit,
) {
    // 衍生狀態直接在 Content 內用 UiState 計算，不回頭問 ViewModel
    val isSubmitEnabled = uiState.name.isNotEmpty() && !uiState.isLoading

    // 慣例：Content 最外層包主題（例如 AppTheme { ... }）
    Box(modifier = modifier.fillMaxSize()) {
        Column(modifier = Modifier.align(Alignment.Center)) {
            Text(
                text = uiState.name,
                modifier = Modifier,
            )
            Button(
                enabled = isSubmitEnabled,
                onClick = { onEvent(SampleScreenEvent.SubmitClick) },
            ) {
                Text("Submit")
            }
        }
    }
}

// Preview 慣例：device spec 固定為平板橫向（1280x800 / 240dpi / landscape），
// 直接餵假 UiState 與空 onEvent，照抄自 LoginScreenContentPreview
@Preview(device = "spec:width=1280dp,height=800dp,dpi=240,isRound=false,chinSize=0dp,orientation=landscape")
@Composable
private fun SampleScreenContentPreview() {
    SampleScreenContent(
        uiState = SampleUiState(
            name = "Preview Name",
            isLoading = false,
        ),
        onEvent = {},
    )
}
```

### SampleViewModel.kt（節錄：UiState 與一次性事件的曝露方式）

```kotlin
package com.example.app.screen.sample

import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class SampleViewModel : BaseViewModel() {

    private val _uiState = MutableStateFlow(SampleUiState())
    val uiState: StateFlow<SampleUiState> = _uiState.asStateFlow()

    // Dialog 狀態：sealed class + null 表示無 Dialog（複雜頁面才需要）
    private val _dialogUiState = MutableStateFlow<DialogEvent?>(null)
    val dialogUiState: StateFlow<DialogEvent?> = _dialogUiState.asStateFlow()

    // 一次性事件：Channel + receiveAsFlow，收集一次就消費掉
    private val _submitSuccessEvent = Channel<Unit>()
    val submitSuccessEvent = _submitSuccessEvent.receiveAsFlow()

    fun onNameClick() {
        _dialogUiState.update { DialogEvent.EditName(name = _uiState.value.name) }
    }

    fun onDismissDialog() {
        _dialogUiState.update { null }
    }

    fun onSubmitClick() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            // ... 呼叫 UseCase ...
            _submitSuccessEvent.send(Unit)
        }
    }

    sealed class DialogEvent {
        data class EditName(val name: String) : DialogEvent()
    }
}

// UiState 定義在 ViewModel 檔案內，欄位全部給預設值以便 Preview 建構
data class SampleUiState(
    val name: String = "",
    val isLoading: Boolean = false,
)
```

## 常見錯誤（改寫時易犯）

1. **Content 拿 ViewModel**：`SampleScreenContent(viewModel: SampleViewModel)` 或在 Content 內呼叫 `koinViewModel()` / `koinInject()`——**禁止**。Content 只能收 `UiState` + `(Event) -> Unit`，否則 Preview 會壞、UI 無法單獨測試。
2. **Content 做導航**：在 Content 裡收 navigator / NavController，或直接呼叫導航 callback——**禁止**。導航一律走「Content 發 Event → Screen 轉發 VM → VM 發 Channel 事件 → Screen 的 `LaunchedEffect` 呼叫外部 callback」。
3. **在 Screen 直接寫業務判斷**：Screen 的 `onEvent` 只做 `when (event) -> viewModel.onXxx()` 一對一轉發，不在 lambda 內夾業務邏輯。條件式事件（如 ERP 鎖定欄位改發別的事件）判斷放在 **Content** 依 UiState 決定發哪個 Event（參考 `LoginScreenContent` 的 `onCaddieClick`）。
4. **用 StateFlow 表達一次性事件**：導航成功旗標放進 UiState 會在重組/旋轉時重複觸發。必須用 `Channel<Unit>().receiveAsFlow()`。
5. **`LaunchedEffect` key 用錯**：收集 ViewModel 事件時 key 用 `viewModel`（`LaunchedEffect(viewModel)`），不要用 `Unit` 以外的易變值導致重複訂閱。
6. **Event 定義位置錯誤**：`XxxScreenEvent` 不要另開檔案、也不要放進 ViewModel；固定放在 `XxxScreenContent.kt` 頂部。
7. **Dialog 用 Boolean flag 疊加**：多個 `showXxxDialog: Boolean` 會出現同時顯示兩個 Dialog 的狀態。用單一 `dialogUiState: StateFlow<DialogEvent?>`（sealed class）保證互斥。
8. **Preview 忘記裝置參數**：若目標裝置為橫向平板，`@Preview` 必須帶 device spec（見範本），否則預覽比例失真、排版判斷失準。

## 命名與目錄範例（相對結構）

以一個 `login` 功能頁為例，各角色對應的相對路徑命名慣例：

| 角色 | 相對路徑命名 |
|------|------|
| 標準雙檔 Screen（含多 Dialog 掛載、雙 Channel 事件） | `screen/login/LoginScreen.kt` |
| 標準 Content（Event sealed class、條件式事件、Preview） | `screen/login/LoginScreenContent.kt` |
| ViewModel + UiState + Channel 事件 | `screen/login/LoginViewModel.kt` |
| 極簡畫面的單檔例外寫法 | `screen/welcome/WelcomeScreen.kt` |
| Dialog 三件套（Dialog / Content / ViewModel） | `screen/login/dialog/<dialogName>/` |
| 頁面專屬元件目錄 | `screen/login/component/` |
| 頁面專屬 UseCase 目錄 | `screen/login/domain/` |

另有兩個共用掛載慣例（Screen 頂部呼叫）：`BindApiError(viewModel)` 統一綁定 API 錯誤顯示、`KeepScreenOnEffect(keepOn = ...)` 控制螢幕常亮。移植新畫面時比照標準 Screen 範本掛上即可。
