---
name: kmp-library-scout
description: 當 KMP／Compose Multiplatform 專案缺少某個能力（圖片載入、本地資料庫、日期時間、權限、生物辨識、圖表、地圖、分析、加密、檔案存取⋯）時，即時查 terrakok/kmp-awesome 這份 KMP 套件精選清單，挑出可用的候選套件，給出比較表、首選推薦與 libs.versions.toml／Koin 接線片段。也能反過來掃專案的 build.gradle.kts 與 libs.versions.toml，盤點還沒被覆蓋的能力缺口。當使用者說「KMP 要用什麼套件做 XXX」、「有沒有支援 iOS 的 XXX 函式庫」、「這個功能跨平台怎麼做」、「幫我找套件」、「盤點這專案缺什麼套件」、「kmp-awesome 有什麼」、「這套件有更好的替代嗎」時觸發。要新增任何第三方相依到 KMP 專案前也應主動使用，不要憑記憶推薦套件。
---

# KMP 套件偵察

專案缺一個能力，去 [terrakok/kmp-awesome](https://github.com/terrakok/kmp-awesome) 找誰能補。
**永遠即時抓 README，不要憑記憶推薦**——KMP 生態換得很快，記憶裡的版本號和維護狀態多半已經過期。

## 兩種模式

| 使用者說的話 | 模式 | 走哪幾步 |
|---|---|---|
| 「KMP 要用什麼做本地資料庫」「有沒有跨平台的圖表套件」 | **A：需求查詢** | 1 → 2 → 3 → 4 → 5 |
| 「盤點這專案缺什麼」「還有哪些能力沒接」 | **B：專案盤點** | 0 → 1 → 2 → 3 → 4 → 5 |

模式 B 掃完後，一次列出所有缺口，讓使用者挑要補哪幾個，再對挑中的走 2～5。
不要一口氣把十個缺口的完整比較表全倒出來。

---

## 第 0 步：掃專案（只有模式 B 需要）

```bash
# 已宣告的相依
cat gradle/libs.versions.toml 2>/dev/null
grep -rn "implementation\|api(\|ksp(" --include="*.gradle.kts" . | grep -v "/build/" | head -60
```

把抓到的 group id 對照 `references/capability-matrix.md` 的能力矩陣，
標出**已覆蓋**與**未覆蓋**的能力。未覆蓋的才是缺口。

判缺口時要誠實：有些能力這個專案根本用不到（例如純內部工具 App 不需要地圖）。
輸出時把缺口分成「**建議補**」與「**視需求**」兩組，不要把整張矩陣當成待辦清單塞給使用者。

---

## 第 1 步：抓 kmp-awesome README

檔名是 **`README.MD`（大寫）**，分支是 **`master`**。小寫或 `main` 都會 404。

```bash
gh api repos/terrakok/kmp-awesome/contents/README.MD --jq '.content' \
  | base64 -d > /tmp/kmp-awesome.md
wc -l /tmp/kmp-awesome.md    # 正常約 1300+ 行，明顯更短代表抓壞了
```

`gh` 不可用時退回 WebFetch：
`https://raw.githubusercontent.com/terrakok/kmp-awesome/master/README.MD`

抓不到（無網路／GitHub 掛了）就**直說抓不到**，並改為只給方向性建議且明確標注「未經清單驗證」。
不要假裝查過。

---

## 第 2 步：定位分類

`## Contents` 後面那張表是分類目錄。實際區段是 `### ` 開頭：

```
🛠 Tooling / 📋 Log / 🌎 Network / 📦 Storage / 📱 Device
💉 Dependency Injection / 🏗 Architecture / 🔍 Analytics / 🩺 Test
🔑 Crypto / 📁 File / 🚀 Language extensions / 🗃 Serializer
⏰ Date-Time / ➿ Asynchronous / 🎨 UI Frameworks / 🍎 Compose UI
🎨 Graphics / 🧩 Service SDK / 🧮 Arithmetic / 🛢 Resources / 🔧 Utils
```

先看目錄確認分類名沒變，再抽該段：

```bash
grep -n "^### " /tmp/kmp-awesome.md                        # 確認分類與行號
sed -n '212,283p' /tmp/kmp-awesome.md                      # 抽出該分類全文
```

需求對不到單一分類時，**跨分類搜關鍵字**（分類邊界很鬆，圖片載入在 Compose UI、
權限在 Device、DataStore 在 Storage）：

```bash
grep -n -i "image\|coil\|permission" /tmp/kmp-awesome.md
```

「這個需求該去哪個分類找」的對照表在 `references/capability-matrix.md`。

---

## 第 3 步：篩候選

清單裡每個條目長這樣：

```
[Coil](https://github.com/coil-kt/coil) - image loading
[![GitHub Repo stars](https://img.shields.io/github/stars/coil-kt/coil?style=flat)](...)
[![Maven Central](https://img.shields.io/maven-central/v/io.coil-kt.coil3/coil)](https://central.sonatype.com/artifact/io.coil-kt.coil3/coil)
> 較長的說明
```

**Maven Central 徽章網址裡的 `v/GROUP/ARTIFACT` 就是座標**，直接拿來寫 `libs.versions.toml`。
沒有 Maven Central 徽章的條目 = 可能沒發佈到 Central，優先序往後放，並在輸出中註明。

星數與最後更新日在 README 裡只是**圖片徽章，文字抓不到**。要排序或判斷是否停更，
對縮到 2–4 個的候選逐一查（不要對整個分類查，會打爆 rate limit）：

```bash
for r in coil-kt/coil Kamel-Media/Kamel; do
  gh api repos/$r --jq '"\(.full_name)\t★\(.stargazers_count)\t最後推送 \(.pushed_at[0:10])\t\(.archived)"'
done
```

淘汰規則：
1. `archived: true` → 直接淘汰
2. 最後推送超過 18 個月 → 除非沒有替代品，否則淘汰並在輸出註明「已久未更新」
3. 不支援專案實際要出的平台 → 淘汰（平台支援看條目說明與 repo README，**不要猜**）
4. 剩下的照星數 + 與現有架構的契合度排序

---

## 第 4 步：架構相容性（本 plugin 的專案優先看這關）

本 plugin 的標準架構是 **Compose Multiplatform + MVVM + Koin + Ktor + Navigation3**
（細節見 `kmp-mvvm-architecture` skill）。推薦時先過這一關，**架構契合度優先於星數**：

- 導航類套件（Voyager、Decompose、Appyx）→ **和 Navigation3 衝突**，除非使用者明說要換掉導航層，否則不推
- 自帶 DI 的套件 → 檢查能不能用 Koin 接管；不能的話在比較表註明
- 自帶 MVI/狀態容器的套件 → 檢查會不會和 `UiState`／`UiEvent` 雙向資料流打架
- 網路類 → 優先選能掛在既有 Ktor `HttpClient` 上的（例如 Ktorfit），而不是自帶另一套 client
- 只有 Android／JVM 的套件 → 只有在「用 `expect/actual` 包一層、其他平台另尋實作」講得清楚時才推

同時要講**這個套件放在哪一層**：`data`（API／DB／快取）、`domain`（純邏輯）、`ui`（Composable）。
放錯層是後面最難拆的技術債。

---

## 第 5 步：輸出

固定三段。比較表最多 4 列，超過就是沒篩乾淨。

```markdown
## 能力：圖片載入（Compose Multiplatform）

| 套件 | Maven 座標 | 平台 | 最後更新 | 備註 |
|---|---|---|---|---|
| **Coil 3** | io.coil-kt.coil3:coil | A/i/D/W | 2026-08 | ★13k，官方 CMP 支援 |
| Kamel | media.kamel:kamel-image | A/i/D/W | 2026-03 | ★1k |

**首選：Coil 3** — 理由（挑最關鍵的 2–3 點，含架構契合度）：
- 原生支援 Compose Multiplatform，`AsyncImage` 直接可用
- 可注入既有的 Ktor `HttpClient`，共用 timeout／攔截器／憑證設定
- 放在 ui 層；`ImageLoader` 由 Koin `single` 提供

### 接入
gradle/libs.versions.toml、build.gradle.kts、Koin module、實際呼叫，各一段最小可跑片段。
片段寫法與範例見 references/integration.md。
```

版本號**不要憑記憶寫死**。查一次再填：

```bash
curl -s "https://search.maven.org/solrsearch/select?q=g:io.coil-kt.coil3+AND+a:coil&core=gav&rows=5&wt=json" \
  | grep -o '"v":"[^"]*"' | head -5
```

查不到就在片段裡寫 `"<查 Maven Central 最新版>"` 並說明，**不要編一個看起來很像的版本號**。

---

## 三個常見翻車點

1. **推了導航／DI 套件卻沒說會撞既有架構** — 使用者裝下去才發現要重寫半個 app。第 4 步不能跳。
2. **只看星數** — 星多但兩年沒動的套件在 KMP 生態等於死掉。一定要看 `pushed_at`。
3. **對整個分類逐一 `gh api`** — 一個分類三十個 repo，打爆 rate limit 又慢。先靠說明文字篩到 2–4 個再查。

## References

- `references/capability-matrix.md` — 能力 → kmp-awesome 分類 → 專案偵測關鍵字的對照表（模式 B 的骨架）
- `references/integration.md` — libs.versions.toml／Koin／分層接入的標準片段寫法
