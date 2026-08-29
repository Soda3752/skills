# 在新專案裝上 Preview 截圖工具鏈

版本以實測過的組合為基準（Roborazzi 1.72.0 / Robolectric 4.16 / ComposablePreviewScanner 0.9.2）。
升版前先確認 Roborazzi 與 scanner 的相容表——這兩個是綁在一起的。

## 1. root build.gradle：宣告 plugin

Groovy DSL：

```groovy
plugins {
    id "io.github.takahirom.roborazzi" version "1.72.0" apply false
}
```

Kotlin DSL 用 `id("io.github.takahirom.roborazzi") version "1.72.0" apply false`。

## 2. 模組 build.gradle：套用 plugin

```groovy
plugins {
    id "io.github.takahirom.roborazzi"
}
```

## 3. 開 android resources

```groovy
android {
    testOptions {
        unitTests {
            returnDefaultValues = true
            // Robolectric 要讀得到 res/ 才能渲染出真正的主題、字串與 drawable，
            // 否則 Preview 出來的圖會缺色缺字。Roborazzi 走 Robolectric，所以必開。
            includeAndroidResources = true
        }
    }
}
```

## 4. 掃描設定（最容易踩坑的一段）

Groovy DSL——**必須走屬性路徑 + `.set()`**：

```groovy
roborazzi.generateComposePreviewRobolectricTests.enable.set(true)
roborazzi.generateComposePreviewRobolectricTests.packages.set(["com.example.app"])
// preview 通常宣告為 private（正確做法，preview 本就不該外露）。
// 沒有這行會掃到 0 個且不報錯，是這套設定最容易踩空的一格。
roborazzi.generateComposePreviewRobolectricTests.includePrivatePreviews.set(true)
// 固定裝置與 SDK，讓同一份 Preview 在任何人的機器上都渲染出同樣尺寸的圖。
// 這個 map 的 value 會被「原樣」插進生成測試的 @Config(...)，
// 所以寫的是 Kotlin 程式碼片段而非字串值。
roborazzi.generateComposePreviewRobolectricTests.robolectricConfig.set([
        "sdk"        : "[34]",
        "qualifiers" : "RobolectricDeviceQualifiers.Pixel5",
        // 刻意換成空的 Application：預設會啟動 manifest 裡的正式 Application，
        // 它會 startKoin()，而所有測試共用同一個 JVM，第二個測試就爆
        // KoinApplicationAlreadyStartedException。ScreenContent 全是無狀態元件、
        // 不從 Koin 取東西，所以不需要真的 Application。
        "application": "android.app.Application::class",
])
```

**Groovy DSL 不能用官方文件那種巢狀 closure**：

```groovy
// ✗ 會噴 unknown property 'enable' for extension 'roborazzi'
roborazzi {
    generateComposePreviewRobolectricTests { enable = true }
}
```

closure 的 delegate 不會切進子 extension。Kotlin DSL 才能用巢狀寫法。

## 5. 依賴

```groovy
dependencies {
    // Preview 截圖工具鏈（只進 test / debug，不會被打包進正式 APK）。
    testImplementation("io.github.takahirom.roborazzi:roborazzi:1.72.0")
    testImplementation("io.github.takahirom.roborazzi:roborazzi-compose:1.72.0")
    testImplementation("io.github.takahirom.roborazzi:roborazzi-compose-preview-scanner-support:1.72.0")
    // 實際做 @Preview 掃描的是這個函式庫；Roborazzi 只是包一層，不會自動帶進來，
    // 缺它時 configure 階段就會失敗並要你自己補版本號。
    testImplementation("io.github.sergio-sastre.ComposablePreviewScanner:android:0.9.2")
    testImplementation("org.robolectric:robolectric:4.16")
    testImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
```

## 6. 驗收

```bash
./gradlew :app:recordRoborazziDebug
ls app/build/outputs/roborazzi/
```

出圖張數對得上 `grep -rc "@Preview" ` 的量就成了。
出 0 張且不報錯 → 回頭檢查 `packages` 與 `includePrivatePreviews`。

生成的測試類別在 `app/build/generated/roborazzi/preview-screenshot/debug/`，
任何「為什麼掃不到／為什麼渲染成這樣」的問題，讀那個檔最快。

## KMP 專案的額外眉角

這套走的是 **Android unit test（Robolectric）**，所以：

- plugin 與依賴掛在 `composeApp`（或你的 KMP 模組）的 **androidUnitTest** source set，
  不是 commonTest。
- 掃描器認的是 **`androidx.compose.ui.tooling.preview.Preview`**。
  `commonMain` 裡用 `org.jetbrains.compose.ui.tooling.preview.Preview` 寫的 preview **掃不到**。
  兩個解法：
  1. 在 `androidMain` 補一層薄的 `@Preview` wrapper，呼叫 commonMain 的 ScreenContent（推薦——
     commonMain 保持乾淨，且 wrapper 本來就要處理 Android 主題）；
  2. 把 preview 直接寫在 `androidMain`。
- `robolectricConfig` 的 `application` 覆寫在 KMP 一樣必要，理由相同（Koin 重複啟動）。
- 只截圖不做視覺回歸的話，**不要**把 `build/outputs/roborazzi/` 進版控。

## 為什麼不用官方 com.android.compose.screenshot

它仍是 alpha，且要求 preview 另寫在 `screenshotTest` source set，
等於同一個畫面維護兩份會各自腐化的 preview。已評估過，刻意不選。
