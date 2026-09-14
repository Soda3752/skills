# 模組結構與 Gradle 設定（AGP 9+）

本架構是**雙 Gradle 模組**：`:shared`（所有 KMP 程式碼與共享 UI）＋ `:androidApp`（純 Android 進入點），
iOS 端則由 `iosApp/` 的 Xcode 專案消費 `:shared` 產出的 framework。

## 為什麼不是單模組

AGP 9.0 起，`com.android.application` 與 `com.android.library` **都不能**和 `org.jetbrains.kotlin.multiplatform` 共存。
硬套會在 configuration 階段直接失敗：

```
The com.android.library (or com.android.application) plugin is not compatible with
the org.jetbrains.kotlin.multiplatform plugin since AGP 9.0.
```

取代方案是 `com.android.kotlin.multiplatform.library`，但它**只有 library 版本，沒有 application 版本**。
Google 官方說法：要遷移就把 Android application 抽成獨立 Gradle 模組。
JetBrains 的建議一致：新開一個 `com.android.application` 模組當進入點，原模組改用 Android KMP library plugin，app 模組依賴它。

> **過渡逃生門（不要當正解）**
> 既有單模組專案若一時無法拆，可在 `gradle.properties` 暫時設
> `android.builtInKotlin=false` 與 `android.newDsl=false` 繞過相容性檢查。
> AGP 官方明講這是 *temporarily bypass*，**AGP 10.0 會移除**。
> 新專案一律直接用雙模組；既有專案設了這兩個旗標就要同時排期拆模組。

參考來源：
- <https://developer.android.com/kotlin/multiplatform/plugin>
- <https://developer.android.com/build/releases/agp-9-0-0-release-notes>
- <https://blog.jetbrains.com/kotlin/2026/01/update-your-projects-for-agp9/>

---

## 目錄佈局

```
<root>/
├── settings.gradle.kts          # include(":shared") / include(":androidApp")
├── build.gradle.kts             # 只宣告 plugin 版本，全部 apply false
├── gradle/libs.versions.toml    # 唯一版本來源
├── shared/                      # ← 所有 KMP 程式碼（含共享 UI）都在這
│   ├── build.gradle.kts
│   └── src/
│       ├── commonMain/kotlin/<package>/…   # api/ base/ di/ model/ screen/ ui/ util/
│       ├── commonMain/composeResources/    # 多語系字串表、drawable
│       ├── androidMain/kotlin/…            # actual 實作、Android Service
│       ├── androidMain/AndroidManifest.xml # 權限宣告 + <service>（見下方「Manifest 分工」）
│       └── iosMain/kotlin/…                # actual 實作、MainViewController
├── androidApp/                  # ← 純 Android 模組，非 KMP
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml  # launcher Activity、android:label、Application 名稱
│       ├── kotlin/<package>/AppApplication.kt   # initKoin { androidContext(...) }
│       ├── kotlin/<package>/MainActivity.kt     # setContent { App() }
│       └── res/                 # launcher icon、app_name
└── iosApp/                      # Xcode 專案，連結 :shared 的 framework
```

`:androidApp` 只放三種東西：**Application、MainActivity、Android 專屬啟動資源**。
任何業務邏輯、ViewModel、Composable 都不准出現在 `:androidApp`。

---

## `shared/build.gradle.kts`

```kotlin
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    // AGP 9 起 KMP 模組一律用這個外掛；Android App 進入點另開 :androidApp
    alias(libs.plugins.androidKotlinMultiplatformLibrary)
    alias(libs.plugins.composeMultiplatform)
    alias(libs.plugins.composeCompiler)
    alias(libs.plugins.kotlinxSerialization)
}

kotlin {
    compilerOptions {
        freeCompilerArgs.add("-Xexpect-actual-classes")
    }

    // 注意：是 kotlin { android { } }，不是頂層的 android { } block
    android {
        // 與 :androidApp 的 applicationId 區隔，避免兩個模組的 R 類別撞名
        namespace = "com.example.app.shared"
        compileSdk = libs.versions.android.compileSdk.get().toInt()
        minSdk = libs.versions.android.minSdk.get().toInt()

        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_11)
        }
    }

    listOf(iosArm64(), iosSimulatorArm64()).forEach { iosTarget ->
        iosTarget.binaries.framework {
            baseName = "ComposeApp"
            isStatic = true
            binaryOption("bundleId", "com.example.app")
        }
    }

    sourceSets {
        commonMain.dependencies {
            // compose、lifecycle、koin、ktor、kotlinx、settings、napier、navigation3…
            // Koin：App() 與 initKoin 由 :androidApp 直接呼叫，故用 api 對外曝光
            api(libs.koin.core)
        }
        androidMain.dependencies {
            // :androidApp 的 MainActivity 需要 androidContext() 與 by inject()
            api(libs.koin.android)
            implementation(libs.ktor.client.okhttp)
        }
        iosMain.dependencies {
            implementation(libs.ktor.client.darwin)
        }
    }
}
```

`api` vs `implementation` 是這裡唯一容易漏的地方：`:androidApp` 要呼叫 `initKoin`、`androidContext()`、
`by inject()`，這些型別必須從 `:shared` **傳遞出去**，所以 `koin-core` 與 `koin-android` 用 `api`。
寫成 `implementation` 會在 `:androidApp` 編譯時找不到符號。

### `com.android.kotlin.multiplatform.library` 不支援的東西

| 不支援 | 對策 |
|---|---|
| `buildTypes` / product flavors（單一 variant） | 需要 variant 就另開一個 `com.android.library` 模組，由 `androidMain` 依賴它 |
| `BuildConfig` | 改用 BuildKonfig 之類的 KMP 方案，或把值放 `:androidApp` 再注入 |
| Data binding / View binding | 本架構全 Compose，不會用到 |
| `externalNativeBuild` | 改用 KMP native target + cinterop |

---

## `androidApp/build.gradle.kts`

```kotlin
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.androidApplication)
    // AGP 9 內建 Kotlin 編譯，不需要再套 org.jetbrains.kotlin.android
    alias(libs.plugins.composeCompiler)
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_11) }
}

android {
    namespace = "com.example.app"
    compileSdk = libs.versions.android.compileSdk.get().toInt()

    defaultConfig {
        applicationId = "com.example.app"
        minSdk = libs.versions.android.minSdk.get().toInt()
        targetSdk = libs.versions.android.targetSdk.get().toInt()
        versionCode = libs.versions.app.versionCode.get().toInt()
        versionName = libs.versions.app.versionName.get()
    }
    packaging { resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" } }
    buildTypes {
        getByName("debug") { isMinifyEnabled = false; isDebuggable = true }
        getByName("release") {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

dependencies {
    implementation(project(":shared"))
    implementation(libs.androidx.activity.compose)
    implementation(libs.compose.uiToolingPreview)
    debugImplementation(libs.compose.uiTooling)
}
```

**buildTypes、簽章、applicationId、版本號一律在這個模組**，`:shared` 一個都不管。

---

## 根 `build.gradle.kts` 與 `settings.gradle.kts`

```kotlin
// build.gradle.kts —— 只做版本宣告，避免每個子專案的 classloader 重複載入外掛
plugins {
    alias(libs.plugins.androidApplication) apply false
    alias(libs.plugins.androidKotlinMultiplatformLibrary) apply false
    alias(libs.plugins.composeMultiplatform) apply false
    alias(libs.plugins.composeCompiler) apply false
    alias(libs.plugins.kotlinMultiplatform) apply false
    alias(libs.plugins.kotlinxSerialization) apply false
}
```

```kotlin
// settings.gradle.kts
include(":shared")
include(":androidApp")
```

`gradle/libs.versions.toml` 的 `[plugins]`：

```toml
androidApplication = { id = "com.android.application", version.ref = "agp" }
# AGP 9 起 KMP 模組必須用這個外掛，com.android.library／com.android.application 都不能與 KMP 外掛共存
androidKotlinMultiplatformLibrary = { id = "com.android.kotlin.multiplatform.library", version.ref = "agp" }
composeMultiplatform = { id = "org.jetbrains.compose", version.ref = "composeMultiplatform" }
composeCompiler = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
kotlinMultiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "kotlin" }
kotlinxSerialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
```

---

## Manifest 分工

兩邊各有一份 `AndroidManifest.xml`，AGP 會做 manifest merge。切法：

| 內容 | 放哪 |
|---|---|
| `<uses-permission>`（含前景服務權限） | `shared/src/androidMain/AndroidManifest.xml` |
| `<service>` / `<receiver>`（業務層元件，實作在 `:shared`） | `shared/src/androidMain/AndroidManifest.xml` |
| launcher `<activity>`、`android:name` 的 Application、`android:label`、`android:theme` | `androidApp/src/main/AndroidManifest.xml` |
| launcher icon、`app_name` 字串 | `androidApp/src/main/res/` |

`shared` 的 manifest 只寫 `<application>` 裡的元件，**不寫 `<application>` 的屬性**（label/icon/theme 交給 `:androidApp`）。

範例（shared）：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
    <application>
        <!-- 服務屬於共享層：業務邏輯都在 :shared，:androidApp 只是進入點 -->
        <service
            android:name="com.example.app.service.LocationForegroundService"
            android:exported="false"
            android:foregroundServiceType="location" />
    </application>
</manifest>
```

---

## `:androidApp` 的兩支檔案

```kotlin
// androidApp/…/AppApplication.kt
class AppApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Napier.base(DebugAntilog())
        initKoin { androidContext(this@AppApplication) }   // initKoin 定義在 :shared
    }
}
```

```kotlin
// androidApp/…/MainActivity.kt
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { App() }          // App() 定義在 :shared 的 commonMain
    }
}
```

需要 Activity 才能做的事（權限對話框、`registerForActivityResult`），一律照鐵律 8：
在 `:shared` 定義介面 + `androidMain` 的 Controller 實作（`single` 註冊），
MainActivity 用 `by inject()` 取得後把 launcher 掛進去，ViewModel 只認介面。

---

## `:shared` 看不到 `:androidApp`

依賴是單向的：`:androidApp → :shared`。所以 `shared/androidMain` 的程式碼
**參照不到 `:androidApp` 的 `MainActivity` 與 `R`**。實務上最常撞到的兩個點：

| 原本（單模組可以） | 拆模組後要改成 |
|---|---|
| `Intent(context, MainActivity::class.java)` 建 PendingIntent | `context.packageManager.getLaunchIntentForPackage(context.packageName)` |
| `R.string.app_name` 取通知標題 | 字串放 `:shared` 自己的資源（Compose Resources 的 `Res.string`，或 `shared` 的 `androidMain/res`） |

這兩個都是編譯期就會炸，但錯誤訊息（unresolved reference: MainActivity / R）容易被誤判成 import 漏了。

---

## 驗證指令

```bash
JAVA_HOME="<Android Studio JBR 路徑>" ./gradlew :androidApp:assembleDebug
./gradlew :shared:linkDebugFrameworkIosSimulatorArm64    # 目標含 iOS 時
```

`:shared` 沒有 `assembleDebug`（它是單 variant 的 KMP library）；Android APK 只由 `:androidApp` 產出。

---

## 版本相容性地雷

| 項目 | 基準 | 說明 |
|---|---|---|
| AGP | 9.1.0 | 9.0 起強制雙模組；`com.android.kotlin.multiplatform.library` 最低需 AGP 8.10 / KGP 2.0 |
| `compileSdk` / `targetSdk` | 36 | AGP 9.1.0 建議上限就是 36 |
| `androidx.core` | **1.16.0** | 1.19.0 要求 `compileSdk 37`，會在 `checkDebugAarMetadata` 直接失敗。在 AGP 升到支援 37 之前不要升 |

---

## 從單模組 composeApp 遷移

1. `settings.gradle.kts` 改成 `include(":shared")` + `include(":androidApp")`，`composeApp/` 目錄改名為 `shared/`。
2. `shared/build.gradle.kts`：把 `com.android.application` 換成 `com.android.kotlin.multiplatform.library`，
   頂層 `android { }` 搬進 `kotlin { android { } }`，刪掉 `applicationId` / `buildTypes` / `versionCode` / 簽章設定。
3. 新建 `androidApp/`，照上面的 `build.gradle.kts` 與 manifest 範本。
4. 把 `MainActivity.kt`、`Application` 子類、launcher manifest 條目、launcher icon 與 `app_name`
   從 `shared/androidMain` 搬到 `androidApp/src/main`。
5. `shared` 的 manifest 留下權限與 `<service>`，拿掉 `<application>` 屬性與 launcher activity。
6. 修掉 `shared/androidMain` 裡對 `MainActivity` 與 `R` 的參照（見上方對照表）。
7. `koin-core` / `koin-android` 在 `shared` 改成 `api`。
8. 跑 `./gradlew :androidApp:assembleDebug` 與 `:shared:linkDebugFrameworkIosSimulatorArm64` 驗收。
