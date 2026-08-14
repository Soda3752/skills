# log 與 index 的格式

兩個檔案，寫入規則相反，別搞混：

- `goalLoop.logPath` — **append-only。永不刪改既有段落。**
- `goalLoop.indexPath` — **每輪覆寫。** 它是 log 的壓縮視圖，內容全部從 log 產生。

---

## log

表頭只在 Step 0 寫一次：

```markdown
# Goal Loop 紀錄：<目標一句話>

**起始 commit** `<hash>`
**分支** <goalLoop.branch>
**規則** jira-goal-loop skill
**設定** .claude/jira-workflow.json → goalLoop
**開跑** YYYY-MM-DD

> append-only。永不刪改既有段落。

## Step 0
- [x] / [ ] 各項與結果
```

之後每輪 append 一段：

```markdown
## 輪 N — PROJ-XX <票標題>

**時間** <開始> → <結束>
**結果** 完成 / 完成+unverified / PENDING / Block / API Require / 三振 / 佔用超限 / 推送失敗
**commit** `<hash>`（或「無」）

**做了什麼**
- 具體改動，一到三條

**失敗過的做法**（沒有就寫「無」，有就一定要寫）
- 試了什麼 → 為什麼不行（錯誤訊息原文）→ 改用什麼

**留給使用者的**
- 需要他做什麼，具體到可執行；沒有就寫「無」

**順帶發現**
- 越出本票範圍的問題：建了哪張票，或為什麼只記錄不建票
```

**「失敗過的做法」是這份檔案存在的唯一理由。** 它是唯一能阻止第 8 輪的你重犯第 3 輪錯誤的東西——省略它，log 就退化成一份沒人看的進度表。

錯誤訊息要**原文**，不要摘要。「link 失敗」對下一輪的你毫無用處；`Undefined symbols for architecture arm64: _OBJC_CLASS_$_LottieAnimationView` 才能讓你三秒認出是同一個坑。

---

## index

每輪覆寫。**只放下一輪決策真正需要的東西**——它的價值來自短。

```markdown
# Goal Loop 索引（每輪覆寫）

**上輪已正常收尾：輪 N**
<!-- 或在輪內時：**進行中：輪 N / PROJ-XX** -->

**已跑輪數** N ｜ **連續空轉** 0 ｜ **最新 commit** `<hash>`

**本 session** `7d303e39` ｜ **本 session 已跑** 3 / 6
<!-- session id 取自 scratchpad 路徑前 8 碼；取不到就寫 `session-id 不可得` -->
<!-- 跑滿時改寫成：**本 session** `7d303e39` ｜ **已達上限，待 /clear** -->


## 別再挑的票
| 票 | 原因 | 輪次 | 現況 |
| --- | --- | --- | --- |
| PROJ-13 | 需真後端＋實機 | 3 | PENDING |
| PROJ-30 | 三振（iOS link 紅） | 5 | PENDING，patch 在 report/…/PROJ-30-failed.patch |

## 別再試的做法
- 改 `libs.versions.toml` 升 Camposer → iOS link 紅（`klib ABI version`）→ 已回滾，別再升

## 需要使用者注意
- PROJ-42 程式已 commit `abc1234` 但狀態推送失敗，票仍停在「進行中」

## 已推進終態
PROJ-49 完成+unverified ｜ PROJ-50 完成+unverified ｜ PROJ-51 完成 ｜ PROJ-24 完成
```

「別再挑的票」與「別再試的做法」兩節是第 3 步過濾與第 6 步實作的直接輸入，缺了它們 loop 就會原地繞圈。其餘幾節可以精簡，這兩節不行。

`**本 session**` 那一行是 SKILL 第 1 步的 session 判定與第 13 步的輪次上限唯一的依據，**不要為了精簡砍掉**。它與 `已跑輪數` 是兩個不同的計數：前者 `/clear` 後歸零，後者跨 session 累計。
