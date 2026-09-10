# 能力矩陣

模式 B（專案盤點）的骨架，也是模式 A「這個需求該去 kmp-awesome 哪個分類找」的對照表。

**grep 關鍵字**只是用來判斷「專案有沒有接這個能力」的線索，命中不代表座標就長那樣。
真正要寫進 `libs.versions.toml` 的座標，一律以 README 條目的 Maven Central 徽章網址
（`.../maven-central/v/GROUP/ARTIFACT`）為準。

盤點指令：

```bash
cat gradle/libs.versions.toml 2>/dev/null
grep -rn "implementation\|api(\|ksp(" --include="*.gradle.kts" . | grep -v "/build/"
```

---

## 基礎層（幾乎每個 App 都要，缺了就是缺口）

| 能力 | kmp-awesome 分類 | grep 關鍵字 | 本架構預設 |
|---|---|---|---|
| HTTP client | 🌎 Network | `ktor` | **Ktor**（架構已定，不另推） |
| JSON 序列化 | 🗃 Serializer | `kotlinx-serialization` | **kotlinx.serialization** |
| DI | 💉 Dependency Injection | `koin`, `kodein`, `kotlin-inject` | **Koin**（架構已定） |
| 導航 | 🏗 Architecture / 🍎 Compose UI | `navigation3`, `voyager`, `decompose`, `precompose` | **Navigation3**（架構已定，其他一律不推） |
| ViewModel | 🏗 Architecture | `lifecycle-viewmodel`, `kmp-viewmodel` | **androidx.lifecycle ViewModel（CMP）** |
| 協程 | ➿ Asynchronous | `kotlinx-coroutines` | **kotlinx.coroutines** |
| 日期時間 | ⏰ Date-Time | `kotlinx-datetime`, `island-time`, `kronos` | kotlinx-datetime |
| Log | 📋 Log | `napier`, `kermit`, `kmlogging` | 依專案選 |

上面標「架構已定」的四項，**不要推替代品**，除非使用者明說要換掉那一層。

---

## 資料層

| 能力 | 分類 | grep 關鍵字 | 候選（去 README 查最新狀態） |
|---|---|---|---|
| Key-Value 設定 | 📦 Storage | `multiplatform-settings`, `datastore` | Multiplatform-Settings、DataStore、KStore、KSafe |
| 加密的 Key-Value | 📦 Storage / 🔑 Crypto | `kvault` | KVault |
| SQL 資料庫 | 📦 Storage | `sqldelight`, `room`, `sqllin` | SQLDelight、Room KMP、SQLlin |
| 文件型／同步資料庫 | 📦 Storage | `realm`, `kotbase` | Realm、Kotbase |
| 記憶體／磁碟快取 | 📦 Storage | `store`, `cache4k` | Store 5、cache4k、Universal-Cache |
| 檔案 I/O | 📁 File | `kotlinx-io`, `okio`, `filekit` | kotlinx-io、Okio、FileKit |
| 分頁 | 🏗 Architecture | `paging` | multiplatform-paging、lazy-pagination-compose |
| GraphQL | 🌎 Network | `apollo` | Apollo GraphQL |
| WebSocket / RPC | 🌎 Network | `krossbow`, `rsocket`, `socketio` | Krossbow、rsocket、SocketIo |
| 加解密／雜湊 | 🔑 Crypto | `cryptography`, `kotlincrypto`, `libsodium` | Cryptography-Kotlin、KotlinCrypto、Libsodium |

---

## 裝置能力（`📱 Device` 分類，多半需要 `expect/actual` 或平台權限設定）

| 能力 | grep 關鍵字 | 候選 |
|---|---|---|
| 執行期權限 | `moko-permissions`, `grant` | MOKO Permissions、Grant |
| 生物辨識 | `moko-biometry` | MOKO Biometry |
| 定位 | `moko-geo`, `compass` | MOKO Geo、Compass |
| 相機 | `kamera`, `camposer`, `peekaboo` | Kamera、Camposer、peekaboo（也含相簿選取） |
| 相簿／媒體選取 | `moko-media`, `filekit`, `peekaboo` | MOKO Media、FileKit、peekaboo |
| 推播通知 | `kmpnotifier` | KMPNotifier |
| 本地排程通知 | `alarmee` | Alarmee |
| 網路連線狀態 | `connectivity` | Connectivity |
| 藍牙 | `kable`, `blue-falcon` | Kable、Blue-Falcon |
| 掃碼 | `kscan`, `qrose` | kScan、QRose（QRose 亦可產碼） |
| 系統對話框／Alert | `alert-kmp` | Alert-KMP |
| 分享 | `kmp-sharing` | KMP Sharing |

**這一類推薦時一定要附上平台端的設定成本**（Info.plist 權限描述、AndroidManifest 權限、
Podfile 或 SPM 設定），不然使用者裝完會卡在 runtime crash。

---

## UI 層（`🍎 Compose UI`／`🎨 Graphics`）

| 能力 | grep 關鍵字 | 候選 |
|---|---|---|
| 圖片載入 | `coil`, `kamel`, `sketch`, `imageloader`, `landscapist` | Coil 3、Kamel、Sketch、Compose-Imageloader、Landscapist |
| 圖表 | `koalaplot`, `vico`, `charts` | Koala Plot、Vico、charts |
| 地圖 | `kmp-maps` | KMP Maps |
| 動畫（Lottie） | `kottie` | Kottie |
| Markdown 渲染 | `markdown-renderer` | Multiplatform Markdown Renderer |
| 富文字編輯 | `richeditor` | Compose Rich Editor |
| PDF 檢視 | `composepdfreader` | ComposePdfReader |
| WebView | `compose-webview` | Compose WebView Multiplatform |
| 影音播放 | `mediaplayer`, `compose-media-player` | MediaPlayer-KMP、Compose Media Player |
| 縮放圖片 | `zoomimage` | ZoomImage |
| 日曆 | `calendar` | Calendar |
| iOS 風格元件 | `cupertino`, `calf` | Compose Cupertino、Calf |
| 動態主題色 | `materialkolor`, `kmpalette` | MaterialKolor、kmPalette |
| 毛玻璃／模糊 | `haze` | Haze、KMPLiquidGlass |
| 設定頁 | `compose-settings` | Compose Settings |
| 響應式版面 | `window-size-class` | Window Size Class |
| 無樣式元件 | `compose-unstyled` | Compose Unstyled |

---

## 品質與維運

| 能力 | 分類 | grep 關鍵字 | 候選 |
|---|---|---|---|
| 單元測試 | 🩺 Test | `kotest`, `kotlin-test`, `testballoon` | Kotest、TestBalloon |
| Flow 測試 | 🩺 Test | `turbine` | Turbine |
| Mock | 🩺 Test | `mockative`, `mokkery`, `mockmp` | Mockative、Mokkery、MocKMP |
| Crash 回報 | 🔍 Analytics | `crashkios`, `sentry` | CrashKiOS、Sentry SDK |
| 分析事件 | 🔍 Analytics / 🧩 Service SDK | `firebase`, `trckr` | Firebase Kotlin SDK、trckr |
| Feature flag | 🧩 Service SDK | `growthbook`, `configcat` | Growth Book SDK、ConfigCat |
| BaaS | 🧩 Service SDK | `supabase`, `firebase` | supabase-kt、Firebase Kotlin SDK |
| 多語系資源 | 🛢 Resources | `compose.resources`, `moko-resources`, `libres` | Compose Resources（本架構預設）、MOKO Resources、Libres |
| BuildConfig | 🛠 Tooling | `buildkonfig`, `buildconfig` | BuildKonfig、gradle-buildconfig-plugin |
| 開源授權頁 | 🛠 Tooling | `aboutlibraries` | AboutLibraries |
| iOS API 友善化 | 🛠 Tooling | `skie`, `kswift` | SKIE、KSwift |
| 錯誤型別 | 📁 File / 🚀 Language extensions | `arrow`, `sandwich`, `apiresult` | Arrow、Sandwich、ApiResult |

---

## 盤點輸出建議

分兩組，不要把整張矩陣當待辦：

- **建議補**：專案類型明顯需要、卻完全沒有相依的能力（例如有登入卻沒有安全儲存、有列表卻沒有圖片載入、完全沒有 crash 回報）
- **視需求**：可有可無，列名稱即可，等使用者點名再展開比較表

判不出專案類型時就問一句，不要硬猜。
