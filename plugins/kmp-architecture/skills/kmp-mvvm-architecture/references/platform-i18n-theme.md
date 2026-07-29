# 平台抽象（expect/actual）、多語系與 Theme

本文說明 本架構的三大跨平台基礎建設慣例：expect/actual 平台抽象、執行期可切換的多語系機制、以及 Material3 Theme 結構。範例 package 以 `com.example.app` 表示，手法與本架構原始碼一致。

## expect/actual 慣例

### 檔案位置與命名

- `expect` 宣告一律放在 `commonMain`，`actual` 放在 `androidMain` / `iosMain` 的**同一個 package**（目錄結構完全鏡射）。
- 專案內存在兩種 actual 檔名慣例，兩者皆可，擇一即可：
  - **平台後綴**（較新檔案採用）：`Platform.kt` → `Platform.android.kt` / `Platform.ios.kt`；`AppTheme.kt` → `AppTheme.android.kt` / `AppTheme.ios.kt`
  - **同名檔案**（早期檔案採用）：`base/LocalAppLocale.kt` 在三個 source set 都叫同一個名字
- 新增檔案時建議統一用平台後綴，一眼可辨識 source set。

### 兩種平台抽象手法的取捨

**手法一：`expect fun`（無狀態的小工具 / 工廠函式）**

適用：純函式、一次性工廠、Composable 效果函式。專案實例：`getDefaultLocale()`、`createHttpClient()`、`md5Hex()`、`getPlatform()`、`KeepScreenOnEffect()`、`noFontPaddingPlatformStyle()`。

```kotlin
// commonMain/api/core/HttpClientFactory.kt
expect fun createHttpClient(json: Json): HttpClient

// androidMain：HttpClient(OkHttp) { ... }
// iosMain/api/core/HttpClientFactory.kt
actual fun createHttpClient(json: Json): HttpClient = HttpClient(Darwin) {
    install(ContentNegotiation) { json(json) }
    install(HttpTimeout) { requestTimeoutMillis = 30_000L }
    defaultRequest { contentType(ContentType.Application.Json) }
}
```

**手法二：interface（commonMain）+ 平台實作 + Koin 注入（有狀態 / 有生命週期 / 依賴平台服務）**

適用：儲存、GPS、需要 Android `Context` 或 iOS 系統物件的元件。專案實例：`IUserSettingStorage`、`ITokenStorage`、`IGpsStatusProvider`。介面定義在 commonMain 的 `localstorage/` 或 `util/`，實作放各平台，最後靠 `platformModule()` 這個 expect fun 把平台 Koin module 接進來：

```kotlin
// commonMain/di/AppModule.kt
expect fun platformModule(): Module

// androidMain/di/AndroidModule.kt
actual fun platformModule(): Module = module {
    single<IUserSettingStorage> { UserSettingStorage(get()) } // 可拿到 Context
}
```

**判斷準則**：
- 只是「一個平台一種寫法的函式」→ `expect fun`，最省事。
- 需要被 mock 測試、需要建構子注入依賴、有內部狀態 → interface + Koin。
- Composable 的平台差異（如 Theme、DialogProperties）→ `expect fun` Composable，**預設參數只能寫在 expect 端**，actual 端重覆參數但不得再寫預設值。

## 多語系（Compose Resources + LocalAppLocale，非 Lyricist）

> 注意：CLAUDE.md 技術選型表列 Lyricist，但**實際落地採用 Compose Multiplatform 內建資源系統**（`org.jetbrains.compose.components:components-resources`，隨 compose plugin 附帶），字串表為 XML，非 Lyricist KSP data class。新專案照此節做即可。

### 字串表定義

```
composeApp/src/commonMain/composeResources/
├── values/           # 預設語系（本架構 = 繁體中文 zh-TW，351 條）
│   └── strings.xml
├── values-en/        # 英文
├── values-ja/        # 日文
├── values-ko/        # 韓文
├── values-zh-rCN/    # 簡體中文（區域碼要加 r 前綴）
└── drawable/
```

```xml
<resources>
    <string name="action_cancel">取消</string>
    <string name="hint_change_car_c002">車牌 %1$s 已更換</string>  <!-- 支援位置參數 -->
</resources>
```

建置後自動產生 `Res` 物件（package 為 `<專案名>.composeapp.generated.resources`）。

### Composable 中取字串

```kotlin
import com.example.app.composeapp.generated.resources.Res
import com.example.app.composeapp.generated.resources.action_cancel
import org.jetbrains.compose.resources.stringResource

Text(text = stringResource(Res.string.action_cancel))
Text(text = stringResource(Res.string.hint_change_car_c002, cart.plate)) // 帶參數
```

### ViewModel（非 Composable）中取字串

```kotlin
import org.jetbrains.compose.resources.getString // suspend 函式，須在 coroutine 內

viewModelScope.launch {
    val msg = getString(Res.string.hint_change_car_c002, cart.plate)
}
```

### 執行期切換語言：三個角色

**1. `Language` enum + `LanguageStateHolder`（commonMain/base/，Koin single）**

```kotlin
enum class Language(val code: String) {
    TRADITIONAL_CHINESE("zh-TW"), SIMPLIFIED_CHINESE("zh-CN"),
    ENGLISH("en"), JAPANESE("ja"), KOREAN("ko");
    companion object {
        fun fromCode(code: String): Language =
            entries.find { it.code == code } ?: TRADITIONAL_CHINESE
    }
}

class LanguageStateHolder {
    private val _languageCode = MutableStateFlow(getDefaultLocale())
    val languageCode: StateFlow<String> = _languageCode.asStateFlow()
    fun setLanguage(code: String) { _languageCode.value = code }
}
// AppModule.kt： single { LanguageStateHolder() }
```

**2. `LocalAppLocale`（expect object，關鍵手法）**

```kotlin
// commonMain/base/LocalAppLocale.kt
expect object LocalAppLocale {
    val current: String @Composable get
    @Composable infix fun provides(value: String?): ProvidedValue<*>
}
```

Android actual：改寫 JVM 預設 Locale 並用新 Configuration 換掉 `LocalContext`，讓 compose resources 依新語系解析：

```kotlin
actual object LocalAppLocale {
    private var defaultLocale: Locale? = null
    actual val current: String @Composable get() = Locale.getDefault().toLanguageTag()

    @Composable
    actual infix fun provides(value: String?): ProvidedValue<*> {
        val configuration = LocalConfiguration.current
        if (defaultLocale == null) defaultLocale = Locale.getDefault()
        val newLocale = if (value == null) defaultLocale!! else Locale.forLanguageTag(value)
        Locale.setDefault(newLocale)
        configuration.setLocale(newLocale)
        val newContext = LocalContext.current.createConfigurationContext(configuration)
        return LocalContext provides newContext
    }
}
```

iOS actual：自建 `staticCompositionLocalOf` 並寫入 `NSUserDefaults` 的 `AppleLanguages`：

```kotlin
actual object LocalAppLocale {
    private val defaultLocale: String = getDefaultLocale()
    private val LocalLocale = staticCompositionLocalOf { defaultLocale }
    actual val current: String @Composable get() = LocalLocale.current

    @Composable
    actual infix fun provides(value: String?): ProvidedValue<*> {
        val newLocale = value ?: defaultLocale
        if (value == null) {
            NSUserDefaults.standardUserDefaults.removeObjectForKey("AppleLanguages")
        } else {
            NSUserDefaults.standardUserDefaults.setObject(listOf(newLocale), "AppleLanguages")
        }
        return LocalLocale provides newLocale
    }
}
```

搭配 `expect fun getDefaultLocale(): String`（Android：`Locale.getDefault().toLanguageTag()`；iOS：`NSLocale.preferredLanguages.firstOrNull() ?: "zh-TW"`）。

**3. App 根部串接（App.kt）**

```kotlin
@Composable
fun App() {
    val languageStateHolder: LanguageStateHolder = koinInject()
    val userSettingStorage: IUserSettingStorage = koinInject()
    val languageCode by languageStateHolder.languageCode.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { // 啟動時還原已儲存的語系偏好
        languageStateHolder.setLanguage(
            userSettingStorage.getLanguage() ?: Language.TRADITIONAL_CHINESE.code
        )
    }

    AppTheme {
        CompositionLocalProvider(LocalAppLocale provides languageCode) {
            // NavDisplay / 全部畫面放在這層之下，語系變更即整棵樹 recompose
        }
    }
}
```

切換入口（如語言設定畫面的 ViewModel）同時寫入儲存與狀態：

```kotlin
fun onLanguageSelected(language: Language) = viewModelScope.launch {
    userSettingStorage.setLanguage(language.code)   // 持久化
    languageStateHolder.setLanguage(language.code)  // 觸發 UI 即時切換
}
```

## Theme 結構

`commonMain/ui/theme/` 固定四檔：

| 檔案 | 內容 |
|------|------|
| `Color.kt` | 純 `val` 平面清單，命名慣例 `Color<語意>_<HEX>`（如 `ColorGreen_217151`、`ColorButtonDisable_80_EFEFEF`，80 表 alpha 0xCC），依功能區塊註解分組（Base / Component / Score / Tee ...） |
| `Typography.kt` | `val AppTypography = Typography(bodyLarge = TextStyle(...))`，僅覆寫必要樣式 |
| `Shape.kt` | `val AppShapes = Shapes(extraSmall = RoundedCornerShape(4.dp), ...)` |
| `AppTheme.kt` | `expect fun` Composable（見下） |

Theme 本身是 expect/actual：Android 端保留 dynamic color 分支，iOS 端忽略：

```kotlin
// commonMain/ui/theme/AppTheme.kt
@Composable
expect fun AppTheme(
    darkTheme: Boolean = false,    // 強制 LightMode：忽略系統深色模式
    dynamicColor: Boolean = false, // 關閉 Android 12+ 動態取色，避免桌布色覆蓋
    content: @Composable () -> Unit
)

// androidMain (.android.kt)：dynamicColor && SDK>=S 時用 dynamicLightColorScheme，
// 否則 lightColorScheme/darkColorScheme；iOS (.ios.kt)：只有 light/dark 兩組。
// 兩端最後都是：
MaterialTheme(
    colorScheme = colorScheme,
    typography = AppTypography,
    shapes = AppShapes,
    content = content
)
```

**Screen 用色慣例**：畫面與 Dialog **直接引用 `Color.kt` 的具名色**（如 `ColorGray1_333333`），不透過 `MaterialTheme.colorScheme` 語意色。colorScheme 僅為 Material 元件預設值兜底。新增顏色時加進 `Color.kt` 對應區塊，命名帶 HEX 以便比對設計稿。

## 接入 checklist（新專案）

1. **依賴**（`gradle/libs.versions.toml` 統一管理，勿寫死版本）：
   - `org.jetbrains.compose` plugin（字串資源 `compose.components.resources` 隨附，`build.gradle.kts` 的 commonMain 加 `implementation(compose.components.resources)`）
   - Koin：`koin-core`、`koin-compose`、`koin-compose-viewmodel`
   - 不需要 Lyricist。
2. **建立檔案**：
   - `commonMain/composeResources/values/strings.xml`（預設語系）+ 各 `values-<lang>/strings.xml`
   - `commonMain/.../base/Language.kt`、`LanguageStateHolder.kt`、`LocalAppLocale.kt`（expect）、`DefaultLocaleProvider.kt`（expect）
   - `androidMain` / `iosMain` 對應 actual：`LocalAppLocale.kt`、`DefaultLocaleProvider.kt`
   - `commonMain/ui/theme/`：`Color.kt`、`Typography.kt`、`Shape.kt`、`AppTheme.kt`（expect）+ 兩平台 `AppTheme.android.kt` / `AppTheme.ios.kt`
   - 語系持久化：`IUserSettingStorage`（interface）+ 平台實作 + `platformModule()` 註冊
3. **App.kt 根部**：`AppTheme { CompositionLocalProvider(LocalAppLocale provides languageCode) { ... } }`，並在 `LaunchedEffect(Unit)` 還原儲存語系。
4. **Koin**：`single { LanguageStateHolder() }` 註冊於共用 module。

## 常見錯誤

- **actual 放錯 package**：actual 必須與 expect 同 package，否則編譯期 `Expected declaration has no actual`。目錄要完整鏡射。
- **actual 重寫預設參數**：expect Composable 的預設值（如 `darkTheme: Boolean = false`）只能宣告在 expect 端，actual 端寫了會編譯錯誤。
- **`CompositionLocalProvider` 放太低層**：`LocalAppLocale provides languageCode` 必須包住整個 NavDisplay/畫面樹，只包局部會導致部分畫面語言不同步。
- **忘記 `values/` 預設資料夾**：compose resources 以 `values/` 為 fallback，缺字串的語系會回退到它；預設語系選使用者主要語言（本架構為 zh-TW）。
- **簡體中文資料夾命名**：區域限定要用 `values-zh-rCN`（`r` 前綴），寫成 `values-zh-CN` 不會生效。
- **ViewModel 直接呼叫 `stringResource`**：非 Composable 環境要用 suspend 的 `org.jetbrains.compose.resources.getString`，在 `viewModelScope.launch` 內呼叫。
- **只改 StateFlow 未持久化（或反之）**：切語言要同時 `userSettingStorage.setLanguage()` 與 `languageStateHolder.setLanguage()`，漏一邊會出現「重啟後語言跳回」或「當下不切換」。
- **iOS 端照抄 Android 的 Configuration 手法**：iOS 沒有 `LocalConfiguration`/`LocalContext`，必須用自建 `staticCompositionLocalOf` + `AppleLanguages` 的寫法。

## 命名與位置範例（相對結構）

基準目錄：`composeApp/src/`

- 多語系核心：
  - `commonMain: base/Language.kt`
  - `commonMain: base/LanguageStateHolder.kt`
  - `commonMain: base/LocalAppLocale.kt`（expect）＋ `androidMain: base/LocalAppLocale.kt`、`iosMain: base/LocalAppLocale.kt`
  - `commonMain: base/DefaultLocaleProvider.kt`（expect）＋ android/ios 同名 actual
  - 字串表：`commonMain/composeResources/values{,-en,-ja,-ko,-zh-rCN}/strings.xml`
  - 根部串接：`commonMain: App.kt`（`AppTheme { CompositionLocalProvider(LocalAppLocale provides languageCode) { ... } }`）
  - 切換入口：`commonMain: screen/main/language/LanguageScreenViewModel.kt`
  - ViewModel 取字串範例：`commonMain: screen/main/score/ScoreScreenViewModel.kt`（`getString(Res.string.hint_change_car_c002, cart.plate)`）
- Theme：
  - `commonMain: ui/theme/{Color,Typography,Shape,AppTheme}.kt`
  - `androidMain: ui/theme/AppTheme.android.kt`、`iosMain: ui/theme/AppTheme.ios.kt`
- expect/actual 代表範例：
  - `commonMain: Platform.kt` → `Platform.android.kt` / `Platform.ios.kt`
  - `commonMain: api/core/HttpClientFactory.kt`（android OkHttp / ios Darwin，同名 actual）
  - `commonMain: di/AppModule.kt` 的 `expect fun platformModule()` → `androidMain: di/AndroidModule.kt`、`iosMain: di/IosModule.kt`
