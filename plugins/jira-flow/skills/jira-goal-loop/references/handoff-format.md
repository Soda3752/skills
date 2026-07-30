# HANDOFF 的格式

`goalLoop.handoffPath`，**每輪覆寫**。目的只有一個：使用者這一刻推門進來，一頁看懂現在在哪、該做什麼。

節次借 `handoff:create` 的結構，但內容**從 log 與 Jira 實查產生，不從對話歷史產生**——動態 loop 的對話歷史會被壓縮，越跑到後面越空，而最先被壓掉的正是失敗細節。

## 不要在輪內呼叫 handoff skill

- `handoff:create` 靠對話歷史，在跨輪壓縮下產出的內容會失真。
- `handoff:resume` 有數處會停下來問使用者（state drift 確認、ready to continue、規格不清時問人）。每輪都有新 commit，drift 偵測必然觸發，等於每輪開頭卡一次問答，而使用者不在。

使用者回來時由**他自己**跑 `handoff:resume`——那時他在場，問答成立。

## 節次

```markdown
# HANDOFF

**更新於** 輪 N（YYYY-MM-DD HH:MM）｜**分支** <branch>｜**commit** `<hash>`

## Goal
一句話：目標與終止條件。

## Current State
**誠實**。這一節是使用者唯一會信的東西。必寫：
- 工作區乾淨嗎？有沒有 stash？
- 最後一次 verifyCommands 的結果
- 有沒有票程式做完但狀態推送失敗
- 有沒有 patch 檔躺著沒人管
- 連續空轉幾輪了

## Completed
本次 loop 推進終態的票，每張一行：票號 → 狀態 → commit → 一句話。
標明哪些掛了 unverified label。

## Not Yet Done
仍非終態的票，附「為什麼還沒動」與「誰能讓它前進」。

## Failed Approaches
從 log 的「失敗過的做法」彙整，錯誤訊息保留原文。這一節不要為了短而砍。

## Key Decisions
規格缺口自己拍板的選擇，以及為什麼。使用者最可能推翻的就是這些。

## Resume Instructions
使用者接手的第一步。要按急迫度排序，具體到可執行：
1. PENDING 票各要他做什麼
2. `labels = <unverifiedLabel>` 的補驗清單
3. 狀態推送失敗的票要手動改成什麼

## Warnings
會咬人的東西：未 commit 的 stash、部分實作的暫時方案、動過但沒完全驗過的區域。
```

`Current State` 寫得含糊，整份 HANDOFF 就沒有價值——使用者會改成自己重查一遍，那不如不寫。
