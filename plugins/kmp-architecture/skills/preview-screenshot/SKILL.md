---
name: preview-screenshot
description: 把專案裡的 Compose @Preview 用 Roborazzi 在純 JVM 渲染成 PNG，讓 Claude 能直接「看見」UI 長什麼樣，或匯出成報告／文件用圖。當使用者說「看一下畫面」、「這頁現在長怎樣」、「截圖給我看」、「出一張圖」、「Preview 截圖」、「渲染看看」、「改完的 UI 對不對」、「把畫面存成圖」、「產出設計稿用圖」時觸發。改完任何 Composable 想確認視覺結果時也應主動使用，不要叫使用者自己開 Android Studio 看 Preview。專案還沒裝這套工具鏈時，本 skill 也負責裝起來（見 references/setup.md）。
---

# Compose Preview 截圖

把 `@Preview` 用 Robolectric 在純 JVM 裡渲染成 PNG。
不需要模擬器、不需要實機、不需要手寫測試檔。

## 第 0 步：專案裝了沒

```bash
grep -rn "roborazzi" --include="*.gradle" --include="*.gradle.kts" . | head
```

沒有任何結果 → 這個專案還沒接上這套工具鏈，先讀 `references/setup.md` 裝起來（約 10 分鐘），再回來走下面的流程。

有結果 → 從那份 gradle 檔讀出**模組名**（`:app:` 還是 `:composeApp:`）與掃描的 **package**，下面所有指令的 `:app:` 都換成實際模組名。

## 先決定要出哪些圖

**預設只出使用者問的那個情境，不要每次都全出。** 全出可能只多幾秒，
但把一堆不相干的圖洗進對話對誰都沒好處。

從使用者的話對到過濾字串，只跑那幾張：

```bash
# 單一情境（最常見）
./gradlew :app:recordRoborazziDebug --tests "*RoborazziPreviewParameterizedTests.test[*SettingScreenContentLoadingPreview*]"

# 一整頁的所有狀態
./gradlew :app:recordRoborazziDebug --tests "*RoborazziPreviewParameterizedTests.test[*SettingScreenContent*]"

# 全部（只有在使用者明確要全部、或要做整體視覺盤點時才用）
./gradlew :app:recordRoborazziDebug
```

過濾字串比對的是 **Preview 函式名**（不是 `@Preview(name=)` 的中文名），
前後包 `*`，大小寫敏感。想確認會命中哪幾張，先查一次再跑：

```bash
grep -rn "fun .*Preview()" --include="*.kt" . | grep -i <關鍵字>
```

**KMP 專案注意**：`@Preview` 通常散在 `commonMain`（`org.jetbrains.compose.ui.tooling.preview.Preview`）
與 `androidMain`（`androidx.compose.ui.tooling.preview.Preview`）。掃描器只吃得到 **androidx 那一個**——
commonMain 的 JetBrains `@Preview` 掃不到。詳見 `references/setup.md` 的 KMP 段落。

## 想看的情境「還沒有 Preview」怎麼辦

使用者可能問「列表有 500 筆時長怎樣」這種目前沒有對應 Preview 的狀態。
做法是臨時補一個 Preview，出完圖再決定去留：

1. 把臨時 Preview 寫進**測試 source set**（如 `app/src/test/java/.../ScratchPreviews.kt`），
   **不要寫進 main** —— main 會進版控，臨時探索用的 Preview 留在那裡就是垃圾。
   （scanner 掃的是 debug unit test 的 classpath，所以 test source set 一樣吃得到。）
2. 用 `--tests` 只跑它，出圖給使用者看。
3. 看完問使用者要不要留。要留就搬進 main 並補上 `@Preview(name=)`；不留就直接刪掉檔案。

臨時 Preview 一律用寫死的假資料，不要碰 Koin、Repository 或真的 Context。

## 輸出

`<模組>/build/outputs/roborazzi/`，一個 `@Preview` 一張 PNG，檔名格式為

```
<完整類別名>.<Preview 函式名>.<@Preview 的 name 參數>_WITH_BACKGROUND.png
```

例：`com.example.app.screen.main.MainScreenContentKt.MainScreenContentRunningPreview.狀態_·_運作正常_WITH_BACKGROUND.png`

沒有指定 `name` 的 Preview 檔名結尾就只有函式名。

## 看圖

出圖後**直接用 Read 工具讀 PNG**——你看得到完整渲染結果（中文字型、Material 3 配色、深色模式都正確）。
這是這個 skill 的主要價值：改完 UI 自己確認視覺結果，而不是叫使用者去開 Android Studio。

一次只讀需要的那幾張。全部讀進 context 是浪費。

## 典型流程：定位 → 只截它 → 看

**先定位再截圖，不要先全截再挑。** 三步，全程約 10 秒：

```bash
# 1. 定位：使用者要的情境對到哪個 Preview 函式？
grep -n "@Preview\|fun .*Preview()" <目標 ScreenContent 檔>

# 2. 只截它（先 rm 舊圖，避免上一輪殘留的圖混進來被誤讀）
rm -rf app/build/outputs/roborazzi
./gradlew :app:recordRoborazziDebug --tests "*RoborazziPreviewParameterizedTests.test[*SettingScreenContentDarkPreview*]"

# 3. 看
ls app/build/outputs/roborazzi/   # 確認命中的就是要的那張
# 然後 Read 那個 PNG
```

改完 Composable 要複驗時，重跑第 2 步即可（過濾字串不用重找）。

`grep` 那步找不到對應 Preview，就代表這個情境還沒有 Preview——走上面「還沒有 Preview 怎麼辦」。

## 匯出給人看

要放進報告、PR 說明或交給 PM 時，把圖複製到報告資料夾（`build/` 會被清掉，不要直接給 build 底下的路徑）：

```bash
mkdir -p .claude/report/$(date +%Y_%m_%d)/screenshots
cp app/build/outputs/roborazzi/*<關鍵字>*.png .claude/report/$(date +%Y_%m_%d)/screenshots/
```

檔名很長且含 `·` 等符號，複製後建議重新命名成人看得懂的短名。

## 新增 Preview

零設定。只要寫在掃描的 package 底下、掛 `@Preview`，下次 record 就自動納入——**private 也吃得到**（前提是 `includePrivatePreviews` 有開），不用為了截圖把可見性放寬。

## 改壞時看這裡

設定全部在模組的 `build.gradle(.kts)` 的 `roborazzi.generateComposePreviewRobolectricTests.*`。
Gradle plugin 掃描 `@Preview` 後**自動生成**一個 Robolectric 參數化測試類別，
產物在 `<模組>/build/generated/roborazzi/preview-screenshot/debug/`——出問題時讀那個生成檔最快看出原因。

常見症狀對照，完整設定與踩坑說明在 `references/setup.md`：

| 症狀 | 原因 |
| --- | --- |
| 掃到 0 個 preview 且不報錯 | `includePrivatePreviews` 沒開，而 preview 全是 private |
| 第二個測試起全掛 `KoinApplicationAlreadyStartedException` | `application` 沒覆寫成 `android.app.Application::class` |
| 圖缺字缺色 | `includeAndroidResources = true` 沒開 |
| `unknown property 'enable'` | Groovy DSL 用了 Kotlin 文件的巢狀 closure 寫法 |
| configure 階段要你補版本號 | 缺 `ComposablePreviewScanner` 依賴 |
| KMP 專案掃到 0 個 | Preview 用的是 JetBrains 版註解，不是 androidx 版 |

某個 Preview 依賴 Koin 注入或真實 Context 時它會單獨失敗——把該 Preview 的資料改成寫死的假資料，
這本來就是 Preview 該有的樣子。

## 不要做的事

- 不要為了截圖去改 `@Preview` 函式的可見性。
- 不要建議改用官方 `com.android.compose.screenshot`——它仍是 alpha，且要求 preview 另寫在
  `screenshotTest` source set，等於維護兩份會腐化的 preview。已評估過，刻意不選。
- 這套是「出圖工具」，預設沒接視覺回歸測試（`verifyRoborazziDebug`）。
  使用者沒明講要做回歸比對前，不要自作主張把基準圖 commit 進版控。
