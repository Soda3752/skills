---
name: handoff-to-new-pane
description: 把手上這份還沒做完的工作交接給一個 context 全新的 Claude——在 Herdr 開一個新 tab、起一隻 Claude、把完整脈絡當開場 prompt 丟過去、確認它真的接手了，然後關掉自己這個 pane。取代「/handoff:create → /clear → /handoff:resume」那套要手動觸發三次的流程，一句話跑完。順手留一份給人看的交接紀錄（pm_report 風格）。Use this whenever the user wants to hand the current work over to a fresh session, is running low on context, wants a clean slate without losing where they are, or asks to swap in a new agent and shut this one down. Triggers： "交接給新的 pane", "換一隻接手", "開新 pane 接手然後關掉自己", "context 快滿了幫我交接", "轉交這份工作", "重開一個乾淨的 session 繼續", "handoff 到新 tab", "接力", "hand this off to a fresh pane", "hand over and close yourself", "restart with clean context", "spin up a successor". 需要 HERDR_ENV=1。只要開新 pane 派別的工作、不是交接自己手上的活，用 create-herdr-wave-agent。
---

# handoff-to-new-pane

把**自己手上這份工作**交給一隻 context 全新的 Claude，然後把自己關掉。

和 `create-herdr-wave-agent` 的差別：那支是把**別的**工作派出去，自己還在；這支是**接力棒交出去就下場**。所以多了兩件它沒有的事——脈絡要從當前對話收斂出來（沒有票券、沒有規格書可以指）、以及最後要自我了結。

**交接載體是 prompt，不是檔案。** 新 agent 一開場就該拿到完整脈絡直接開工，不必先去讀一份文件。同時寫的那份紀錄是**給人看的**，不是給 agent 看的——使用者過幾天回來要知道當時交接了什麼。

## 什麼時候不要用這支

- 使用者只是要開個 pane 做別的事 → `create-herdr-wave-agent`
- 手上有**背景任務還在跑**（`/loop`、背景 Bash、watch 中的 artifact）→ 關掉 pane 會一併殺掉，先問使用者
- 手上工作**已經做完了** → 不需要交接，直接回報
- 使用者只說「幫我寫交接紀錄」 → 走第 1～2 步就停，不要自作主張開 pane 關自己

## 步驟 0：確認環境與自己的座標

```bash
test "${HERDR_ENV:-}" = 1 || echo "NOT_IN_HERDR"
printf '%s\n' "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID"
```

不在 Herdr 裡就說「我不在 Herdr 管理的 pane 裡，開不了新 pane 也關不掉自己」，
然後**改為只做第 1～2 步**（寫交接紀錄），讓使用者自己開新 session 讀。
不要用 `tmux`、背景 `&` 硬湊——那些 Herdr 管不到，使用者 attach 不進去。

順手看一眼有沒有背景任務會被一起殺掉：

```bash
git status --short
```

有未 commit 的變更**不要自己 commit**（除非使用者交代過），但一定要寫進紀錄與 prompt，
不然新 agent 會以為工作區是乾淨的。

## 步驟 1：收斂脈絡

從**當前對話**擷取下面這些。這一步是整支 skill 的價值所在——
新 agent 對這段對話一無所知，你腦子裡的東西沒寫出來就等於不存在。

| 要抓什麼 | 為什麼 |
| --- | --- |
| 原始目標 | 使用者到底要什麼，用他自己的話 |
| 已完成 | 哪些真的做完且驗證過了 |
| 進行到哪一步 | 現在正在做什麼、做到一半的是哪個檔案 |
| **試過但不行的做法** | **最值錢的一段**。少了它，新 agent 會把你踩過的坑再踩一遍 |
| 關鍵決策與理由 | 不寫理由，新 agent 會覺得選錯而改掉 |
| 使用者在對話中表達的偏好 | 「不要用 X」「一律中文」這種，講過一次就算數 |
| 未 commit 的變更 | `git status` 的實況 |
| 下一步具體動作 | 不是「繼續測試」，而是「跑 X 指令，預期看到 Y」 |

**分清事實與判斷。** 「測試在 auth.spec.ts:42 失敗」是事實；「應該是 middleware 順序問題」是你的推測——
推測可以給，但要標明是推測，讓新 agent 有機會用自己查到的資料推翻。

## 步驟 2：寫交接紀錄（給人看的）

**精簡，給人看的，不是給 agent 看的。** 照 `report-tools:pm_report` 的規範走：
繁體中文、Markdown、有流程就用 Mermaid（換行用 `<br/>` 不用 `\n`）、存到當前工作目錄的
`.claude/report/YYYY_MM_DD/`。

```bash
mkdir -p ".claude/report/$(date +%Y_%m_%d)"
```

檔名：`交接紀錄-<主題>.md`（同一天同主題再交接一次就加 `-HHMM`）。

模板——**六段，每段最多幾行，不要展開成技術調查報告**：

```markdown
# <主題> 交接紀錄

**日期：** YYYY-MM-DD HH:MM
**分支：** <git branch>
**狀態：** 進行中 / 卡住 / 待驗收
**接手者：** Herdr <workspace>:<新 tab> 的 Claude（agent 名稱 <name>）

## 一、這份工作要做什麼

<2-3 句，用使用者自己的話講目標>

## 二、目前進度

- [x] <已完成且驗證過的事>
- [ ] <還沒做的事>

## 三、試過不行的做法

<沒有就寫「無」。有的話寫：試了什麼 → 為什麼不行 → 改用什麼>

## 四、關鍵決策

| 決定 | 理由 |
|------|------|
| <選了什麼> | <為什麼> |

## 五、現場狀態

**可運作：** <現在什麼是好的>
**未完成／壞的：** <什麼還不行，錯誤訊息照抄>
**未 commit：** <git status 摘要>

## 六、交接後的第一步

<一個具體動作，含預期結果>
```

寫完把路徑記下來，第 4 步的 prompt 要提到它。

## 步驟 3：開新 tab

使用者要的是新 tab（不是分割目前這格）——因為舊 pane 等下會關掉，新 agent 值得一整格全寬。

```bash
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label "<工作名>" --no-focus
```

- `--cwd "$PWD"`：**不能省**，新 tab 不繼承工作目錄，少了它新 agent 會在家目錄對著錯的 repo 開工
- `--label`：用工作內容命名（`kmp-scout`、`auth-fix`），使用者切 tab 時認得出來
- `--no-focus`：先不搶焦點，等驗證過再切過去（第 6 步）

從回傳 JSON 取兩個 id，**從 JSON 讀，不要猜編號**（關掉的 id 不回收，數字不連續）：

```
.result.root_pane.pane_id   →  新 pane id（agent start 要用）
.result.tab.tab_id          →  新 tab id（最後 focus 要用）
```

## 步驟 4：起 agent 並派工

```bash
herdr agent start <name> --kind claude --pane <新 pane id> --timeout 60000
```

- `<name>` 格式 `[a-z][a-z0-9_-]{0,31}`，用工作內容命名（`auth-fix`、`kmp-scout`），不要 `agent-1`
- kind 一律 `claude`
- `--timeout 60000`：冷啟動偶爾超過預設 30 秒

**這一步失敗是真失敗**（pane 不是乾淨的 shell、claude 沒裝），停下來回報，不要往下走。

需要免確認才能連續跑的工作，才在後面接 `-- --permission-mode auto`；
預設不加，讓新 agent 該問就問——反正使用者的視線等下就在那個 tab 上。

### 派工內容 = 交接本體

prompt 會有換行、引號、路徑，**用單引號硬塞會爆**。寫成檔案再讀進去：

```bash
cat > "$TMPDIR/handoff-prompt.txt" <<'PROMPT'
你正在接手一份進行中的工作，前一個 session 的 pane（<舊 pane id>）交接完就會關掉。
以下是完整脈絡，你不需要再去讀任何交接文件就能開工。

## 目標
<使用者要什麼，用他自己的話>

## 已完成（驗證過）
<條列>

## 進行到哪
<現在卡在哪個檔案／哪一步>

## 試過不行的做法（不要重犯）
<試了什麼 → 為什麼不行>

## 關鍵決策與理由
<條列，附理由>

## 使用者的偏好
<對話中講過的規則>

## 現場狀態
分支：<branch>
未 commit：<git status 摘要>
可運作：<...>  壞的：<錯誤訊息照抄>

## 你的第一步
<一個具體動作，含預期結果>

給人看的交接紀錄在 .claude/report/<日期>/交接紀錄-<主題>.md，
內容和上面一致，你不必再讀；若之後發現上面哪裡寫錯了，順手更新那份檔案。

請先用三到五行跟使用者說你接到了什麼、下一步要做什麼（他的畫面剛從舊 pane 切過來，
需要看到接得上），然後直接開始做第一步，不要等他再確認一次。

舊 pane 的關閉不用你管——我讀到你這段開場回應之後才會關自己，所以你開場時它一定還在。
PROMPT

herdr agent prompt <name> "$(cat "$TMPDIR/handoff-prompt.txt")" --wait --timeout 60000 2>&1 | tail -5 || true
```

`|| true` 不能省：`--wait` 等的是第一個 settled 狀態，新 agent 一接到就開始做事會停在 `working`，
於是必然 timeout 並 exit 1。**那個 timeout 不是失敗**，prompt 早就送到了，進第 5 步查證。

反過來，如果很快回 `blocked`，那是真的要處理——它一進去就撞到權限確認或在問問題。

**最後那段「先講你接到什麼」不要省。** 舊 pane 一關，剛才的對話就從畫面上消失了；
使用者切到新 tab 如果看到的是一片空白或一堆工具輸出，他不知道交接成不成功。

**不要在 prompt 裡叫接手方「確認舊 pane 已關閉」。** 這條在時序上必然不成立：
第 5 步規定要讀到接手方的開場回應才准關自己，所以接手方開場的那一刻，舊 pane 一定還開著。
它照著查只會查到「舊 pane 還在」，然後把這個當成 bug 回報給使用者。

舊 pane 的關閉是**發起方**第 6 步的責任，不外包。真要讓接手方複查，
就得像上面模板那樣明講「我讀到你的回應之後才會關」，並請它稍後再查。

## 步驟 5：查證它真的接手了

**這一步過不了就不准關自己。** 兩邊都要看：

```bash
herdr agent get <name>
herdr agent read <name> --source recent-unwrapped --lines 40
```

`agent get` 的 `agent_status`：

| 狀態 | 判定 | 該做什麼 |
| --- | --- | --- |
| `working` | 接手成功 | 可以進第 6 步 |
| `blocked` | 它在問問題或等權限 | **不要關自己**，讀畫面看它問什麼，回報使用者 |
| `idle` | **可疑**——prompt 可能沒送到 | 讀畫面確認；只是秒答完開場說明也可能是 idle，看畫面判斷 |
| `unknown` | Herdr 認不出來 | **不要關自己**，讀畫面判斷 |

`agent read` 要看到它**真的在講這份工作**——提到了目標、檔名、下一步。
如果畫面上是一句無關的客套話或空的，代表 prompt 沒生效，重派一次；重派還是不行就回報並保留舊 pane。

讀不到完整輸出（`--lines` 加大也撈不到）代表它跑在 alternate screen，
這時**才**改叫它把回應寫成檔案、你去讀檔。這是 fallback，不要一開始就這樣要求。

這一步你自己讀一遍是為了**判斷內容對不對**；第 6 步的腳本會再機械化檢查一次狀態與畫面長度，
兩者不重複——腳本擋的是「明顯還沒接手」，你擋的是「接手了但在講別的事」。

## 步驟 6：把焦點交過去，然後關掉自己（用腳本，不要自己下指令）

這一步**不由你逐行下指令**，交給 skill 附的腳本跑：

```bash
"$CLAUDE_PLUGIN_ROOT/skills/handoff-to-new-pane/scripts/close-self.sh" \
  --agent <name> --tab <新 tab id>
```

`--pane` 省略時取 `$HERDR_PANE_ID`（就是自己這格）。想先看它會做什麼就加 `--dry-run`。

**為什麼是腳本。** 「驗證沒過就不准關自己」這條規則交給 LLM 判斷，就有機會被跳過，
而這一步的失敗是不可逆的——舊 pane 一關，脈絡兩邊都沒了，沒有第二次機會。
所以把 gate 寫成程式：狀態不對就 exit 非 0，且完全不會走到 `pane close`。
腳本本身也保證了順序（先 `tab focus` 再 `pane close`），不會反過來讓使用者盯著一個正在消失的 pane。

腳本做的事，依序：

| # | 動作 | 不通過會怎樣 |
| --- | --- | --- |
| 1 | 讀 `herdr agent get <name>` 的 `agent_status` | 非 `working` 就停，exit 3，什麼都沒關 |
| 2 | 讀 `herdr agent read` 的畫面，要求 ≥ 40 個非空白字元 | 太空就停，exit 4，什麼都沒關 |
| 3 | `herdr tab focus <新 tab id>` | focus 失敗就停，exit 5，不關自己 |
| 4 | `herdr pane close <自己>` | 成功則 exit 0，本行之後這個 pane 就不存在了 |

exit code 對應：`2` 參數不對、`3` 接手方狀態不合格、`4` 畫面是空的、`5` focus 失敗。
**非 0 一律等於交接沒完成、舊 pane 還活著**，照下面那段回報，不要手動補一行 `pane close` 繞過去。

`idle` 是唯一需要你介入的情況：腳本預設拒絕（第 5 步說過 `idle` 可疑）。
你讀畫面確認它真的在講這份工作之後，才加 `--accept-idle` 重跑一次。

因為 `pane close` 是整支 skill 的最後一個動作，後面不會再有機會做任何事、也不會再有機會回報：

- 該寫的檔案（交接紀錄）在第 2 步就要寫完並存好
- 該講的話在第 4 步就要交代給新 agent 去講

### 驗證沒過怎麼回報

腳本 exit 非 0 就是這個情況。不要手動關自己，照這個講：

```
交接沒完成，舊 pane（這裡）保留著。

新 tab：<tab id>，agent <name>，狀態 <blocked/idle/unknown>
close-self.sh exit <code>，訊息：<照抄>
它畫面上顯示：<照抄關鍵幾行>

交接紀錄已存：.claude/report/<日期>/交接紀錄-<主題>.md

要我重派一次、還是你自己切過去看？
  herdr agent focus <name>
  herdr agent read <name> --lines 60
```

## 不要做的事

- **不要**在第 5 步沒過的時候關掉自己。脈絡兩邊都丟是這支 skill 唯一的災難級失敗。
- **不要**自己手打 `herdr pane close` 收尾，一律走 `close-self.sh`；它 exit 非 0 就是不准關，不要繞過去。
- **不要**在派工 prompt 裡要求接手方驗證「舊 pane 已關閉」。第 5 步要先讀到它的開場回應才會關自己，
  所以它開場時舊 pane 必然還在——它只會查到「還在」，然後當成 bug 回報。關閉是發起方的責任。
- **不要**在有背景任務（`/loop`、背景 Bash）還在跑的時候直接關，先問使用者。
- **不要**只把交接紀錄的路徑丟給新 agent 當交接。載體是 prompt，檔案是給人看的。
- **不要**省略 `--cwd "$PWD"`，新 agent 會在家目錄開工。
- **不要**用單引號直接包多行 prompt，寫成檔案再 `"$(cat ...)"`。
- **不要**把第 4 步的 `--wait` timeout 當成派工失敗。
- **不要**在交接前自己 `git commit` 未 commit 的變更，除非使用者交代過。寫進紀錄就好。
- **不要**把交接紀錄寫成技術調查報告。六段、給人看、幾分鐘讀完。
- **不要**先關自己再切焦點。

## 附帶腳本

| 檔案 | 用途 |
| --- | --- |
| `scripts/close-self.sh` | 第 6 步的收尾：查證接手方 → `tab focus` → `pane close` 自己。gate 寫在腳本裡，狀態不對就 exit 非 0 且不關任何 pane。用 `$CLAUDE_PLUGIN_ROOT` 定位，`--dry-run` 可先試跑。 |
