# 接入片段寫法

推薦一個套件時，附上的程式碼片段照這裡的格式寫。
目標是**最小可跑**：使用者貼上去、改版本號、就能編譯，不多不少。

DI 的完整慣例（模組切分、`single` vs `factory`、platformModule 的判斷準則）
以 `kmp-mvvm-architecture` skill 的 `references/koin-di.md` 為準，這裡只寫「新套件怎麼接進去」。

---

## 1. gradle/libs.versions.toml

座標從 kmp-awesome 條目的 Maven Central 徽章網址取：
`https://img.shields.io/maven-central/v/GROUP/ARTIFACT` → `GROUP:ARTIFACT`。

```toml
[versions]
coil = "3.x.y"          # ← 查過 Maven Central 才填實際版本，查不到就留 <查最新版> 並說明

[libraries]
coil-compose = { module = "io.coil-kt.coil3:coil-compose", version.ref = "coil" }
coil-network-ktor = { module = "io.coil-kt.coil3:coil-network-ktor3", version.ref = "coil" }
```

多模組套件（core / compose / network 分開發佈）要**講清楚哪幾個是必要的**，
不要整包列出讓使用者自己猜。

## 2. build.gradle.kts

一定要說清楚放哪個 source set。這是 KMP 最容易錯的一步：

```kotlin
kotlin {
    sourceSets {
        commonMain.dependencies {
            implementation(libs.coil.compose)
            implementation(libs.coil.network.ktor)
        }
        // 只有平台專屬實作才放這裡
        androidMain.dependencies { /* … */ }
        iosMain.dependencies    { /* … */ }
    }
}
```

需要 KSP／compiler plugin 的套件（Ktorfit、Room、Mockative⋯），
把 plugin 宣告與 KSP 設定一併附上，否則會編譯過但 runtime 找不到產生的類別。

## 3. Koin 註冊

新增的相依一律走 Koin，**不要在 Composable 或 Repository 裡自己 `new` 一個 client／loader**。

```kotlin
// commonMain/di/AppModule.kt — sharedModule 內，插進對應的分區註解底下
single {
    ImageLoader.Builder(get())
        .components { add(KtorNetworkFetcherFactory(httpClient = get())) }  // 共用既有 HttpClient
        .build()
}
```

需要平台 API（`Context`、`NSUserDefaults`、CoreLocation⋯）才能建構的，
改寫進 **androidMain / iosMain 的 `platformModule`**，並在 commonMain 用 `expect` 宣告介面。

```kotlin
// commonMain
interface BiometryAuthenticator { suspend fun authenticate(reason: String): Boolean }

// androidMain platformModule
single<BiometryAuthenticator> { AndroidBiometryAuthenticator(get<Context>()) }
// iosMain platformModule
single<BiometryAuthenticator> { IosBiometryAuthenticator() }
```

## 4. 呼叫端（放對層）

| 套件性質 | 放哪一層 | 誰持有 |
|---|---|---|
| API client、DB、快取、本地儲存 | `data` | Repository |
| 純運算、格式化、驗證 | `domain` | UseCase |
| Composable 元件、圖片載入、動畫 | `ui` | ScreenContent |
| 裝置能力（權限、相機、定位、生物辨識） | `data`（包成介面）+ `platformModule` | Repository / Manager |

裝置能力**絕對不要直接在 Composable 呼叫平台 API**——包成 commonMain 的介面、
由 ViewModel 透過 UseCase 觸發、結果走 `UiState` 回到畫面，才不會破壞雙向資料流。

```kotlin
// ui 層範例：Composable 直接用，ImageLoader 由 Koin 提供
AsyncImage(
    model = state.avatarUrl,
    contentDescription = null,
    imageLoader = koinInject(),
)
```

## 5. 平台設定（裝置能力類必附）

推薦權限／相機／定位／通知類套件時，這段不能省：

```
iOS  — Info.plist：NSCameraUsageDescription、NSPhotoLibraryUsageDescription…
Android — AndroidManifest.xml：<uses-permission android:name="android.permission.CAMERA" />
         + 執行期權限請求（targetSdk 23+）
```

漏掉的話使用者會在真機第一次呼叫時直接 crash，而且錯誤訊息通常看不出原因。

---

## 收尾檢查

給出片段後，提醒使用者跑一次編譯確認：

```bash
./gradlew :composeApp:compileKotlinIosArm64 :composeApp:assembleDebug
```

模組名依專案實際情況（`:app:` 或 `:composeApp:`）。
只編 Android 過不算數——KMP 的相依問題大半在 iOS 端才爆。
