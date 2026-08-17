---
name: create-herdr-wave-agent
description: 在 Herdr 裡開一個新 pane、啟動一隻編碼 agent（Claude 或 Codex），並派給它一份帶脈絡的工作——通常是要它執行某支 skill（herdr-claude-wave、parallel-loop、goal-loop⋯），也可以是一段純文字任務。確認它真的跑起來就交手，不佔用主 agent。Use this whenever the user wants to spin up another agent in a Herdr pane and hand it work, delegate a skill to a separate pane, or start a wave/loop in its own terminal. Triggers： "開新 pane 叫 claude 跑 X", "用 herdr 派 X 給 claude", "開一隻 agent 執行 X", "叫 codex 在 pane 裡做 X", "派 herdr-claude-wave", "開個 pane 跑 parallel-loop", "spin up an agent to run X", "open a herdr pane and have claude do X", "delegate this skill to another pane"。需要 HERDR_ENV=1。
---

# create-herdr-wave-agent

把一份工作交給**另一個 pane 裡的 agent**，而不是自己做。

價值不在「開一個終端機」，而在**交接品質**。同樣一句「跑 herdr-claude-wave」，只丟 skill 名字給對方，它得自己重新摸索專案現況；帶著脈絡丟過去，它第一步就能做對事。這支 skill 的重點在派工那一段的組法。

派完確認它真的動起來就交手。**不要留下來盯**——主 agent 被佔住的話，使用者就不能同時跟你講別的事，而那正是他開第二個 pane 的原因。

## 步驟 0：確認在 Herdr 裡

```bash
test "${HERDR_ENV:-}" = 1
```

失敗就說「我不在 Herdr 管理的 pane 裡，開不了新 pane」然後停。**不要**改用 `tmux`、`screen` 或背景 `&` 硬湊一個替代品——那些開出來的東西 Herdr 看不到，使用者也 attach 不進去，等於給了他一個管不到的黑箱。

順手記下自己的位置，後面每一步都要用：

```bash
printf '%s\n' "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID"
```

## 步驟 1：決定分割方向

**先看現況再決定，不要固定往某個方向分。**

```bash
herdr pane layout --pane "$HERDR_PANE_ID"
```

從回應裡找自己那格的 `rect`，依它的**實際寬高**選方向：

| 自己這格 | 分割方向 | 理由 |
| --- | --- | --- |
| 寬（≥ 160 欄） | `right` | 分完兩邊都還有 80 欄，讀得下程式碼 |
| 中等或已經被左右分過（100～160 欄） | `down` | 再往右分會掉到 60～80 欄，agent 的 TUI 會擠爛 |
| 矮（< 40 列） | `right` | 再往下分只剩 20 列，看不到 agent 在做什麼 |

使用者明講方向就照他的，不要用這張表覆蓋他。

**判準是「分完之後那格還能用嗎」**，不是「上一次往哪分」。連續同方向分兩三次就會做出一條沒人讀得了的細長條。

## 步驟 2：開 pane

```bash
herdr pane split --current --direction <right|down> --cwd "$PWD" --no-focus
```

三個參數都不能省：

- `--current`：目標是**我這格**。省略會打到 UI 焦點所在的 pane，那可能是使用者正在用的、或別的 client 的。
- `--cwd "$PWD"`：新 pane 預設不繼承工作目錄。少了它，agent 會在家目錄啟動，然後對著錯的 repo 開工。
- `--no-focus`：不要把使用者的視線搶走。他叫你開 pane 是要它在背景跑，不是要你打斷他。

從 `.result.pane.pane_id` 取新 pane id。**從 JSON 讀，不要從側欄順序或前例猜**——closed 的 id 不會回收，數字不連續。

## 步驟 3：起 agent

```bash
herdr agent start <name> --kind <claude|codex|...> --pane <上一步的 pane id> --timeout 60000
```

**名稱要取得有意義且獨一。** 它是之後所有指令的地址，`agent-1` 這種名字在有三隻 agent 的時候完全沒用。用工作內容命名：`wave-lead`、`e2e-fix`、`proj-11`。

格式限制 `[a-z][a-z0-9_-]{0,31}`——小寫開頭，不能有中文、空格、大寫。

kind 用使用者指定的；沒指定就用 `claude`。完整清單跑 `herdr agent` 看。

`agent start` 會等到 Herdr 確認 agent 起來且可接收輸入才回，預設 30 秒。冷啟動偶爾會超過，所以明確給 `--timeout 60000`。

**這一步失敗才是真的失敗**（pane 不是乾淨的 shell prompt、agent 沒裝、kind 打錯）。與步驟 4 的 timeout 不是同一回事。

## 步驟 4：派工——這支 skill 的重點

```bash
herdr agent prompt <name> '<派工內容>' --wait --timeout 60000 2>&1 | tail -5 || true
```

### 派工內容怎麼組

**不要只丟一行 skill 名字。** 對方是全新的 context，它對這個專案一無所知——你現在腦子裡那些「剛建好 7 張票」「規格書在哪」「哪張能動」，它全都沒有。少了這些它會自己去摸，摸出來的結論還未必和你一致。

一份派得動的工作有四段：

```
執行 /<skill 全名>

脈絡：<專案是什麼、剛發生了什麼、現在的狀態>

<關鍵事實：票號、檔案路徑、依賴關係、已知限制>

請<明確交代它負責什麼、以及什麼不歸它管>
```

實例：

```
執行 /linear-flow:herdr-claude-wave

脈絡：這個專案（<repo 名>，Linear team <team>，prefix PROJ）剛建好
Project「<專案名>」，共 7 張票 PROJ-11 ~ PROJ-17。

目前只有 PROJ-11 是 Todo 且無 blocker，其餘 6 張都是 Blocked
（PROJ-12~16 blocked by PROJ-11；PROJ-17 blocked by PROJ-13/14/15/16）。

規格書在 .claude/report/<日期>/<專案名>-規格書.md，
每張票的描述已寫好完成條件。

請照 skill 流程盤點看板、決定這一波能派哪幾張票、開 worktree 與 Claude
pane 實作，並負責 rebase、fast-forward 整合與全部 Linear 狀態與註解。
```

幾條規則：

- **skill 要寫全名**（含 plugin 前綴，如 `linear-flow:herdr-claude-wave`）。只寫後半段對方可能對不到，或對到同名的另一支。
- **脈絡寫事實，不要寫推測。** 「PROJ-11 是 Todo」是事實；「應該先做 PROJ-11」是你的判斷——判斷可以給，但要標明是建議，讓它有機會用自己查到的資料推翻。
- **交代邊界。** 「你負責整合與 Linear 狀態」跟「不要動 main 以外的分支」一樣重要。沒講邊界的 agent 會擴張範圍。
- **不要在派工裡要求它把結果寫檔**。除非之後真的讀不到畫面（見「讀不到完整輸出」），否則多此一舉。

### 為什麼 `|| true` 不能省

`--wait` 等的是「第一個 settled 狀態」（`idle` / `done` / `blocked`）。派出去的如果是 wave、loop 這種長工作，它會**一直待在 `working`**，於是 `--wait` 必然 timeout：

```json
{"error":{"code":"timeout","message":"timed out waiting for agent status"},"id":"cli:agent:prompt"}
```

**這個 timeout 不是失敗。** prompt 早就送達了，只是它還在做。CLI 此時 exit 1，所以：

- 不加 `|| true`（或 `|| echo`）的話，在 `set -e` 環境下整個步驟會中斷
- 看到 error JSON 就回報「派工失敗」是**錯的**，必須進步驟 5 實際查證

反過來說，如果 `--wait` **很快就回 `blocked`**，那是真的要處理——它一進去就撞到權限確認或在問問題。

## 步驟 5：查證它真的在做事

派工送出不等於它接到了、也不等於它做對了。查兩件事：

```bash
herdr agent get <name>
herdr agent read <name> --source recent-unwrapped --lines 40
```

`agent get` 看 `agent_status`：

| 狀態 | 意思 | 該做什麼 |
| --- | --- | --- |
| `working` | 正常，收到工作開始做 | 進步驟 6 交手 |
| `blocked` | 撞到權限確認或在問問題 | 讀畫面看它問什麼，回報使用者或代答 |
| `idle` | **可疑**——prompt 可能沒送到，或它秒答就結束了 | 一定要讀畫面確認，不要當成成功 |
| `unknown` | Herdr 認不出來 | 讀畫面判斷，不要當成完成 |

`agent read` 要確認的是**它真的載入了那支 skill**，不是隨便回了句話。畫面上該看到類似：

```
⏺ Skill(linear-flow:herdr-claude-wave)
  ⎿  Successfully loaded skill
```

沒看到 skill 載入就是派工沒生效——最常見原因是 skill 全名打錯，對方當成普通文字回了一段話。

`terminal_title` 也是好訊號：Claude 會把它改成當前工作的摘要，標題還停在 `Claude Code` 表示它還沒真的開始。

### 讀不到完整輸出時

`--lines` 加大還是看不到完整回應，代表 agent 跑在終端機的 alternate screen，那些行不會進 Herdr 的 scrollback，加再多也撈不回來。

這時**才**改用檔案：叫它把完整回應寫成 Markdown 放 temp 目錄、只回檔案路徑，然後直接讀檔。這是 fallback，不要一開始就這樣要求。

## 步驟 6：回報並交手

回報要讓使用者**不必問第二次就知道發生什麼、以及怎麼接手**。四件事：

1. **位置**：workspace / tab / pane id，配一張 ASCII 佈局圖標出新 pane 在哪
2. **身分**：agent 名稱、kind、版本或模型
3. **狀態**：現在是 working / blocked，已經走到哪一步（從畫面讀到的實際進度，不是猜的）
4. **盯工指令**：可直接複製貼上的三行

```
herdr agent focus <name>                      # 切過去看
herdr agent read <name> --lines 60            # 這邊讀它的輸出
herdr agent wait <name> --until blocked done  # 等它卡住或做完
```

然後**停**。問一句「要我盯著回報，還是你自己看」，不要自作主張進入等待。

## 不要做的事

- **不要**在 `HERDR_ENV` 不是 1 的時候硬湊替代方案。
- **不要**省略 `--cwd "$PWD"`，agent 會在錯的目錄開工。
- **不要**省略 `--no-focus`，會把使用者的視線搶走。
- **不要**把步驟 4 的 timeout 當成派工失敗——那是長工作的正常現象。
- **不要**只丟 skill 名字當派工內容，脈絡是這支 skill 的全部價值。
- **不要**開完就宣稱成功，一定要用 `agent get` + `agent read` 查證。
- **不要**關掉、切換或 takeover 你沒建立的 pane，除非使用者明確要求。
- **不要**用 terminal id 當 agent 目標，只有 agent 名稱與 pane id 認得。
- **不要**派完之後留下來 `agent wait` 空轉，除非使用者要你盯。
