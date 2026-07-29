# Koin DI 慣例

本文件定義 本架構的 Koin 依賴注入慣例：模組如何切分、註冊語法怎麼寫、
Android / iOS 各自如何初始化，以及新增功能時 DI 需要動哪幾行。
所有慣例均取自專案實際程式碼，移植或新增功能時**照此格式寫，不要發明新寫法**。

---

## 目的與原則

1. **單一 sharedModule + 各平台一個 platformModule**：
   commonMain 只有一個 `sharedModule`（所有共享註冊集中在一個檔案），
   平台差異透過 `expect fun platformModule(): Module` 由 androidMain / iosMain 各自提供 `actual`。
2. **介面在 shared 註冊點宣告、實作由 platform 提供** 的判斷準則：
   - 建構時**不需要平台 API**（`Context`、`NSUserDefaults`、CoreLocation…）→ 放 `sharedModule`。
   - 需要平台 API、或介面定義在 commonMain 但實作分平台（`ITokenManager`、`IGpsStatusProvider`、
     `LocationRepository`…）→ 介面綁定寫在**兩邊的 platformModule**，各綁各的實作。
3. **幾乎全部用 `single`**：Repository、UseCase、StateHolder、Manager 一律 `single`；
   本架構 **UseCase 也用 `single` 註冊（不用 `factory`）**，因為 UseCase 皆為無狀態或持有共享狀態。
   ViewModel 一律用 `viewModel { }` DSL（生命週期由 lifecycle-viewmodel 管理）。
4. **依賴一律用 `get()` 佔位**：建構子有幾個參數就寫幾個 `get()`，
   需要指定型別時才寫 `get<Type>()`（例如 Android 端取 `get<Context>()`）。
5. **分區註解**：sharedModule 內用 `// Repositories`、`// Use Cases`、`// ViewModels`、
   `// Dialog ViewModels — Login` 等區塊註解分組，新註冊項插入對應區塊，不要亂序追加。

---

## 模組佈局

```
composeApp/src/
├── commonMain/…/di/AppModule.kt      # val sharedModule = module { … }
│                                     # expect fun platformModule(): Module（同檔案末行）
├── commonMain/…/KoinInit.kt          # fun initKoin(config) = startKoin { … } 共用進入點
├── androidMain/…/di/AndroidModule.kt # actual fun platformModule(): Module
├── androidMain/…/SampleApplication   # Application.onCreate() 呼叫 initKoin { androidContext(...) }
├── iosMain/…/di/IosModule.kt         # actual fun platformModule(): Module
└── iosMain/…/MainViewController.kt   # ensureIosKoinStarted() → initKoin()
```

### 什麼放 shared、什麼放 platform

| 類別 | 放哪裡 | 範例（本架構） |
|------|--------|---------------|
| `Json`、`HttpClient`、`ApiService` | sharedModule | `single { createHttpClient(get()) }` |
| Repository 介面+實作皆在 commonMain | sharedModule | `single<LoginRepository> { LoginRepositoryImpl(get()) }` |
| Repository 介面在 common、實作分平台 | 兩邊 platformModule | `LocationRepository` |
| UseCase（純業務邏輯） | sharedModule | `single { LoadScoreCardUseCase(get(), get()) }` |
| StateHolder（跨畫面共享狀態） | sharedModule | `single { LanguageStateHolder() }` |
| ViewModel | sharedModule | `viewModel { LoginViewModel(get(), …) }` |
| `Settings.Factory`（本地存儲底層） | platformModule | SharedPreferences / NSUserDefaults |
| 本地存儲實作（Token、CoreData…） | platformModule（兩邊都要綁同一組介面） | `single<ITokenManager> { TokenStorage(get(), get()) }` |
| GPS / TTS / 音效 / 網路狀態 / 電池 | platformModule | `IGpsStatusProvider`、`IDistanceAnnouncer` |

> 注意：`ITokenManager`、`ICoreDataStorage` 等存儲介面雖然**兩個平台綁定的是同一個 commonMain 實作類別**，
> 綁定仍寫在 platformModule（因為它們依賴 platform 提供的 `Settings.Factory`）。移植時照抄此配置。

---

## 範本程式碼

### sharedModule（commonMain — `di/AppModule.kt`）

```kotlin
package com.example.app.di

import kotlinx.serialization.json.Json
import org.koin.core.module.Module
import org.koin.core.module.dsl.viewModel
import org.koin.dsl.module

val sharedModule = module {
    // JSON
    single {
        Json {
            ignoreUnknownKeys = true
            isLenient = true
            encodeDefaults = true
            prettyPrint = false
            coerceInputValues = true
        }
    }

    // HTTP Client (expect/actual per platform)
    single { createHttpClient(get()) }

    // ApiService (IApiConfig & ITokenManager 由 platformModule 提供)
    single { ApiService(get(), get(), get(), get()) }

    // Repositories — 一律「介面 → 實作」成對註冊
    single<SampleRepository> { SampleRepositoryImpl(get()) }

    // State Holder（跨畫面共享狀態，無介面、直接註冊具體類別）
    single { SampleStateHolder() }

    // Use Cases — 本架構慣例：用 single（不是 factory）
    single { SampleSyncUseCase(get(), get()) }
    single { SampleLoadUseCase(get()) }

    // ViewModels — 用 viewModel DSL（org.koin.core.module.dsl.viewModel）
    viewModel { SampleViewModel(get(), get()) }

    // Dialog ViewModels — Sample
    viewModel { SampleDialogViewModel(get()) }

    // 複雜建構子可用具名參數 + 巢狀參數物件（實例：DataSyncManager）
    single {
        SampleSyncManager(
            simpleInfo = get(),
            scoreUseCases = SampleSyncManager.ScoreUseCases(
                uploadScore = get(),
                syncScoreCard = get(),
            ),
        )
    }
}

// 與 sharedModule 同檔案末行宣告 expect
expect fun platformModule(): Module
```

### androidMain platformModule（`di/AndroidModule.kt`）

```kotlin
package com.example.app.di

import android.content.Context
import com.russhwolf.settings.Settings
import com.russhwolf.settings.SharedPreferencesSettings
import org.koin.core.module.Module
import org.koin.dsl.module

actual fun platformModule(): Module = module {
    // Settings.Factory：使用 Android SharedPreferences
    single<Settings.Factory> { SharedPreferencesSettings.Factory(get<Context>()) }

    // Local Storage（介面在 commonMain，綁定寫在 platformModule）
    single<ISampleStorage> { SampleStorage(get(), get()) }

    // Platform utilities — 需要 Context 時明確寫 get<Context>()
    single<ISampleStatusProvider> { AndroidSampleStatusProvider(get<Context>()) }

    // 平台專屬實作綁 commonMain 介面
    single<SampleRepositoryPlatform> { AndroidSampleRepositoryImpl(get<Context>(), get()) }

    // 已註冊的具體類別轉綁另一個介面（實例：SimulateController）
    single<SampleController> { get<SampleSourceImpl>() }
}
```

### iosMain platformModule（`di/IosModule.kt`）

```kotlin
package com.example.app.di

import com.russhwolf.settings.NSUserDefaultsSettings
import com.russhwolf.settings.Settings
import org.koin.core.module.Module
import org.koin.dsl.module

actual fun platformModule(): Module = module {
    // Settings.Factory：使用 iOS NSUserDefaults
    single<Settings.Factory> { NSUserDefaultsSettings.Factory() }

    // 與 Android 端「同一組介面」逐一提供 iOS 實作
    single<ISampleStorage> { SampleStorage(get(), get()) }
    single<ISampleStatusProvider> { IosSampleStatusProvider(get()) }
    single<SampleRepositoryPlatform> { IosSampleRepositoryImpl(get(), get()) }

    // 平台不支援的功能用 NoOp 實作補齊（實例：NoOpIotHubConnectionController）
    single<SampleConnectionController> { NoOpSampleConnectionController() }
}
```

---

## 初始化（Android / iOS）

### 共用進入點 KoinInit.kt（commonMain）

```kotlin
package com.example.app

import com.example.app.di.platformModule
import com.example.app.di.sharedModule
import org.koin.core.KoinApplication
import org.koin.core.context.startKoin

typealias KoinAppDeclaration = KoinApplication.() -> Unit

fun initKoin(config: KoinAppDeclaration? = null) {
    startKoin {
        config?.invoke(this)
        modules(sharedModule, platformModule())
        // 本架構實際還載入外部函式庫模組：grantModule, grantPlatformModule
    }
}
```

### Android — Application.onCreate()

```kotlin
class SampleApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Napier.base(DebugAntilog())
        initKoin {
            androidContext(this@SampleApplication)  // 供 get<Context>() 使用
            androidLogger()
        }
    }
}
```

### iOS — MainViewController.kt（iosMain）

iOS 沒有 Application 生命週期掛點，改在建立 UIViewController 前做「冪等啟動」：

```kotlin
fun MainViewController(): UIViewController {
    ensureIosKoinStarted()
    return ComposeUIViewController { App() }
}

fun ensureIosKoinStarted() {
    try {
        KoinPlatform.getKoin()
        return // Koin 已啟動，跳過
    } catch (_: IllegalStateException) {
        // Koin 尚未啟動，繼續初始化
    }
    Napier.base(DebugAntilog())
    initKoin()   // iOS 不需傳 config（無 Context）
}
```

### Composable 取得 ViewModel — koinViewModel()

畫面 Composable 一律以**預設參數**注入 ViewModel：

```kotlin
import org.koin.compose.viewmodel.koinViewModel

@Composable
fun SampleScreen(
    viewModel: SampleViewModel = koinViewModel(),
    onNavigate: () -> Unit,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    // ...
}
```

---

## 新增功能時的 DI checklist

新增「一頁畫面」通常涉及以下每項各**加一行**（全部改 `AppModule.kt`，除非牽涉平台 API）：

1. **新 Repository**（介面 + 實作都在 commonMain 時）
   - `AppModule.kt` 的 `// Repositories` 區塊：`single<FooRepository> { FooRepositoryImpl(get()) }`
   - 若實作需平台 API：改在 `AndroidModule.kt` 與 `IosModule.kt` **兩邊**各加一行綁同一介面。
2. **新 UseCase**
   - `AppModule.kt` 對應畫面的 `// Xxx UseCases` 區塊：`single { FooUseCase(get(), get()) }`（本架構用 single，不用 factory）。
3. **新 ViewModel**
   - `AppModule.kt` 的 `// ViewModels`（或 `// Dialog ViewModels — Xxx`）區塊：`viewModel { FooViewModel(get(), …) }`。
4. **新跨畫面 StateHolder**
   - `AppModule.kt`：`single { FooStateHolder() }`。
5. **畫面端**
   - Composable 參數：`viewModel: FooViewModel = koinViewModel()`。
6. **驗證**：Android + iOS 都跑一次啟動（Koin 為 runtime 解析，缺註冊在編譯期不會報錯，
   會在第一次 `get()` 時丟 `NoDefinitionFoundException`）。

---

## 常見錯誤

| 錯誤 | 症狀 | 修法 |
|------|------|------|
| ViewModel 建構子加了參數但 `viewModel { }` 沒補 `get()` | 編譯錯誤（參數數量不符） | 建構子有幾個依賴就寫幾個 `get()` |
| Repository 只註冊實作、忘了 `single<Interface>` 泛型 | ViewModel 注入介面時 runtime `NoDefinitionFoundException` | 一律寫 `single<FooRepository> { FooRepositoryImpl(get()) }` |
| 平台介面只在 AndroidModule 綁、IosModule 漏綁 | Android 正常、iOS 啟動即 crash | 兩個 platformModule 必須提供**同一組**介面綁定；iOS 無對應能力時用 NoOp 實作 |
| 在 commonMain 註冊需要 `Context` 的類別 | commonMain 編譯失敗 | 移到 `AndroidModule.kt`，iOS 提供替代實作 |
| Android 端忘了 `androidContext(...)` | `get<Context>()` runtime 失敗 | `initKoin { androidContext(this@Application) }` |
| iOS 重複 startKoin | `KoinApplication has already been started` | 走 `ensureIosKoinStarted()` 的 try/catch 冪等模式 |
| 用 `kotlinx.datetime.Clock` 當依賴 | 專案規範禁止 | 改用 `kotlin.time.Clock`，時間函數集中在 `TimeUtil` |

---

## 命名與位置範例（相對結構）

| 角色 | 路徑 |
|------|------|
| sharedModule + `expect platformModule()` | `commonMain: di/AppModule.kt` |
| initKoin 進入點 | `commonMain: KoinInit.kt` |
| Android platformModule | `androidMain: di/AndroidModule.kt` |
| Android 初始化（Application） | `androidMain: AppApplication.kt` |
| iOS platformModule | `iosMain: di/IosModule.kt` |
| iOS 初始化（ensureIosKoinStarted） | `iosMain: MainViewController.kt` |
| koinViewModel 用法範例 | `commonMain: screen/splash/SplashScreen.kt` |

補充實況：

- `initKoin` 除了 `sharedModule` 與 `platformModule()`，還載入外部函式庫的
  `grantModule`、`grantPlatformModule`（`dev.brewkits.grant.di`）。
- `sharedModule` 目前約 27 個 ViewModel（含 Dialog VM）、30+ 個 UseCase，全部集中單檔管理；
  區塊順序大致為：Json → HttpClient → ApiService → Repositories → StateHolders →
  UseCases（依畫面分組）→ ViewModels → Dialog ViewModels → DataSyncManager。
- `DataSyncManager` 是唯一使用具名參數 + 巢狀參數物件（`ScoreUseCases` / `LocationUseCases`）
  的複雜註冊，依賴多於 5 個時可仿照此寫法。
