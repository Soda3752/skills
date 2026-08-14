# Codex task prompt 寫法

Codex 吃的 prompt 風格與 Claude subagent **完全不同**。plugin 自己的指引（`gpt-5-4-prompting`）說得很直接：

> 把 Codex 當**操作員**而不是協作者。prompt 要精簡、用 XML 標籤做區塊結構。講清楚任務、輸出契約、預設的自行推進政策，以及少數真正要緊的約束。

不要把 `parallel-wave` 那份給 Claude 的長篇指令直接搬過來——那份靠的是 Claude 的規範意識與 theory of mind，Codex 要的是契約。

## 核心原則

- **一個 job 一件事。** 不相關的要求拆成不同 job。
- **講明白「完成長什麼樣」。** Codex 不會自己推斷你要的終態。這是最常見的失敗原因。
- **先緊契約，別先加推理強度。** 效果不好時改 prompt，不是加 `--effort`。
- **標籤名沿用 plugin 的既有命名**，不要自創一套。

## 實作型任務要有的區塊

| 標籤 | 放什麼 | 為什麼不能省 |
| --- | --- | --- |
| `<task>` | 具體任務 + repo 脈絡 | 唯一必要區塊 |
| `<completeness_contract>` | 完成的定義，逐條列 | Codex 會在「差不多」的地方停手 |
| `<verification_loop>` | 怎麼自我驗證、失敗了怎麼辦 | 沒有這段它不會自己跑到綠 |
| `<action_safety>` | 不准碰什麼、範圍邊界 | 沒有這段它會順手重構無關的東西 |
| `<missing_context_gating>` | 什麼情況該停下來問、什麼情況自己決定 | 否則不是亂猜就是卡住等指示 |
| `<compact_output_contract>` | 回報的形狀與長度 | 你要從回傳結果重建 Linear 註解，形狀不對很難用 |

## 必須寫進 prompt 的專案脈絡

Codex 沒讀過 `CLAUDE.md`，不知道任何慣例。**下列每一項講漏了，它就會自己發明一套**：

- 建置與測試的**完整指令**（含環境變數，例如 `JAVA_HOME=...`），以及輸出要重導到 log
- **測試要確認真的執行**——只看「BUILD SUCCESSFUL」會放過空測試
- commit 訊息慣例（風格、語言、結尾要不要加 co-author）
- **只 commit 預期路徑**：`git commit --only <paths>`，commit 後用 `git show --stat` 自我確認沒夾帶未追蹤檔
- 禁止 push、禁止合併回 base 分支、禁止動 base 分支
- 本機**驗不到**的驗收條件（實機、視覺、跨平台），要它誠實標記而不是宣稱通過
- 已經存在、可直接取用的元件與型別（附路徑），以及**不准重寫**它們

## 範例：實作型任務

```xml
<task>
在目前工作目錄（git worktree）完成這張票：

<ticket_id>PROJ-99</ticket_id>
<title>遊戲計分板表格（五遊戲共用 UI）</title>
<spec>
<!-- 票券描述全文貼在這裡。Codex 讀不到 Linear，這是它唯一的規格來源。 -->
</spec>

規格文件（唯讀，不要修改）：
- /abs/path/vault/games/G7-遊戲計分主頁.md
</task>

<existing_building_blocks>
以下已存在且可直接用，不要重寫或修改：
- ui/component/SegmentedControl.kt — 泛型分段控制項
- ui/component/NumberStepper.kt — 加減按鈕數字選擇（不含鍵盤觸發）
- model/matchgame/ — 領域模型，enum ordinal 已對齊外部系統
</existing_building_blocks>

<completeness_contract>
完成的定義（全部滿足才算完成）：
1. 編譯通過
2. 表格的純邏輯部分（欄位計算、合計、五款遊戲的欄位差異）抽成純函式並有單元測試
3. 單元測試實際執行且全部通過
4. 未實作任何票券範圍外的功能
</completeness_contract>

<verification_loop>
自我驗證，失敗就修，修完重跑，直到全綠或確認無法解決：

  JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
    ./gradlew :composeApp:compileDebugKotlinAndroid :composeApp:testDebugUnitTest \
    > /tmp/PROJ-99-verify.log 2>&1; echo "EXIT=$?"; tail -40 /tmp/PROJ-99-verify.log

建置輸出很大，一律重導到 log 再看尾段。

「BUILD SUCCESSFUL」不等於測試有跑。必須確認測試實際執行數：
  find composeApp/build/test-results/testDebugUnitTest -name "*.xml" | xargs grep -o 'tests="[0-9]*"'
tests="0" 代表測試沒被執行，要修好而不是當成通過。
</verification_loop>

<action_safety>
- 只改本票需要的檔案。不要順手重構、格式化、或修正你認為有問題的無關程式碼。
- 不要修改 model/matchgame/ 與 ui/component/ 底下的既有檔案。
- 不要動 di/AppModule.kt（有其他工作同時在改它）。
- 不要 push、不要合併回 main、不要切換或修改 main 分支。
</action_safety>

<commit_policy>
完成後 commit 在目前分支：
- 訊息用中文 conventional commits，例如 feat(matchgame): 新增計分板表格元件
- 結尾加一行：Co-Authored-By: Codex <noreply@openai.com>
- 用 git commit --only <明確路徑> 限定範圍，不要用 git add -A
- commit 後跑 git show --stat HEAD 自我確認，沒有夾帶未追蹤或被 gitignore 的檔案
</commit_policy>

<missing_context_gating>
- 規格有歧義但存在合理預設時：自己選一個合理作法，繼續做完，並在回報中說明你的選擇與理由。
- 缺少會導致做錯方向的關鍵資訊（例如找不到規格文件、建置指令跑不起來）：停下來，在回報中說明卡在哪，不要猜。
</missing_context_gating>

<compact_output_contract>
最後回報用這個結構，簡潔：
- commit hash
- 改動檔案清單（每個檔一行，附一句說明）
- 驗證結果：編譯 pass/fail、測試實際執行數與通過數
- 規格歧義處的決策與理由
- 本機無法驗證的項目（明確列出，不要宣稱通過）
- 已知限制
</compact_output_contract>
```

## 後續指令（`--resume-last`）

只送**差異**，不要重述整個 prompt：

```xml
<task>
測試 GameScoreboardTest 有 2 項失敗，log 在 /tmp/PROJ-99-verify.log。
修正後重跑同一組驗證指令，直到全綠。
</task>
<action_safety>
只修測試失敗的成因。不要順手改其他東西。
</action_safety>
```

方向有實質改變時才重述完整脈絡。

## 常見失敗與對策

| 症狀 | 多半是缺了什麼 |
| --- | --- |
| 做到一半就宣稱完成 | `<completeness_contract>` 沒寫或太模糊 |
| 沒跑測試就說通過 | `<verification_loop>` 沒給具體指令與確認方式 |
| 改了一堆無關的檔 | `<action_safety>` 沒寫範圍邊界 |
| commit 夾帶奇怪的檔案 | `<commit_policy>` 沒指定 `--only` 與事後 `git show --stat` |
| 回報難以轉成 Linear 註解 | `<compact_output_contract>` 沒定形狀 |
| 卡住等指示不動 | `<missing_context_gating>` 沒說什麼時候該自己決定 |
