[← 回目錄](README.md)

# herdr

在 Herdr 裡開新 pane，把工作派給另一個 agent。

## 先讀這一段

**這個 plugin 需要 Herdr。**

Herdr 是一個終端多工器。它把終端機組織成 workspace、tab、pane，並且辨識 pane 裡執行的編碼 agent。

skill 執行前會檢查環境變數：

```
HERDR_ENV=1
```

這個變數不是 1 時，skill 會停止並說明原因。它**不會**改用 tmux、screen 或背景程序代替。原因見下面「為什麼不用 tmux 代替」。

## 安裝

```
/plugin marketplace add Soda3752/skills
/plugin install herdr@soda-skills
```

它與票券系統無關。你不需要裝 `linear-flow` 或 `jira-flow` 就能用。

## 它解決什麼問題

你在跟一個 Claude 對話。你想同時跑一件長工作，例如一輪平行開發、一個 goal loop、或把測試修綠。

你有三個選擇：

| 做法 | 問題 |
| --- | --- |
| 叫當前的 Claude 直接做 | 它被佔住。你不能同時跟它講別的事。 |
| 自己開終端機貼指令 | 你要自己組脈絡。新 agent 對專案現況一無所知。 |
| 用這個 plugin | Claude 開 pane、起 agent、把脈絡整理好交過去，然後交手。 |

## 收錄它的價值

價值不在「開一個終端機」。那件事你自己按快捷鍵就會了。

價值在**交接品質**與**兩個會誤判的訊號**。

### 交接品質

只丟一行 skill 名字給新 agent，它得自己重新摸索專案現況。摸出來的結論還未必和你一致。

skill 規定派工內容要有四段：

```
執行 /<skill 全名>

脈絡：<專案是什麼、剛發生了什麼、現在的狀態>

<關鍵事實：票號、檔案路徑、依賴關係、已知限制>

請<明確交代它負責什麼、以及什麼不歸它管>
```

三條規則寫在 skill 裡：

- skill 要寫**全名**，含 plugin 前綴。只寫後半段可能對不到，或對到同名的另一支。
- 脈絡寫**事實**，不寫推測。判斷可以給，但要標明是建議，讓對方有機會用查到的資料推翻。
- 一定要交代**邊界**。沒講邊界的 agent 會擴張範圍。

### 誤判訊號一：timeout 不是失敗

派工指令長這樣：

```
herdr agent prompt <name> '<內容>' --wait --timeout 60000
```

`--wait` 等的是第一個 settled 狀態（`idle`、`done` 或 `blocked`）。

派出去的如果是 wave 或 loop 這種長工作，agent 會**一直待在 `working`**。所以 `--wait` 必然 timeout：

```json
{"error":{"code":"timeout","message":"timed out waiting for agent status"}}
```

**這不是失敗。** prompt 早就送達了。CLI 此時 exit 1，所以有兩個後果：

- 沒有 `|| true` 的話，在 `set -e` 環境下整個步驟會中斷。
- 看到 error JSON 就回報「派工失敗」是錯的。

反過來說，`--wait` 如果**很快**回 `blocked`，那才要處理。那代表 agent 一進去就撞到權限確認或在問問題。

### 誤判訊號二：`idle` 要當可疑

派工後查狀態：

```
herdr agent get <name>
```

四種狀態的處理方式不同：

| 狀態 | 意思 | 該做什麼 |
| --- | --- | --- |
| `working` | 正常，收到工作開始做 | 交手 |
| `blocked` | 撞到權限確認或在問問題 | 讀畫面看它問什麼 |
| `idle` | **可疑** | 一定要讀畫面確認 |
| `unknown` | Herdr 認不出來 | 讀畫面判斷，不要當成完成 |

`idle` 可疑的原因：prompt 可能沒送到，或 skill 名字打錯被當成普通文字回了一段話。兩種情況狀態都是 `idle`。

所以查證要讀畫面，確認看得到 skill 真的載入：

```
⏺ Skill(linear-flow:herdr-claude-wave)
  ⎿  Successfully loaded skill
```

沒看到這一段就是派工沒生效。

## 使用方式

你不需要記指令。說出你要做的事就會觸發。

| 你說 | 發生什麼 |
| --- | --- |
| 開新 pane 叫 Claude 跑 herdr-claude-wave | 開 pane、起 Claude、派 wave |
| 用 herdr 派 parallel-loop 給 claude | 同上，換一支 skill |
| 叫 codex 在 pane 裡把 e2e 跑綠 | 開 pane、起 Codex、派純文字任務 |
| 開一隻 agent 執行 linear-goal-loop | 開 pane、起 Claude、派 loop |

派的對象可以是任何 skill，也可以是一段純文字任務。agent 種類可選 `claude` 或 `codex`，你沒指定時用 `claude`。

## 六個步驟

skill 走這個流程。每一步都寫了為什麼，不只是指令。

| 步驟 | 做什麼 | 關鍵 |
| --- | --- | --- |
| 0 | 確認 `HERDR_ENV=1` | 失敗就停，不找替代方案 |
| 1 | 讀 `pane layout` 決定分割方向 | 依自己這格的實際寬高決定，不是依上次分哪邊 |
| 2 | `pane split` 開 pane | 三個參數都不能省，見下 |
| 3 | `agent start` 起 agent | 名稱要有意義且獨一 |
| 4 | `agent prompt` 派工 | 這支 skill 的重點 |
| 5 | `agent get` + `agent read` 查證 | 開完就宣稱成功是錯的 |
| 6 | 回報並交手 | 附可複製的盯工指令，然後停 |

### 分割方向怎麼選

判準是「分完之後那格還能用嗎」，不是「上一次往哪分」。

| 自己這格 | 方向 | 理由 |
| --- | --- | --- |
| 寬（≥ 160 欄） | `right` | 分完兩邊都還有 80 欄 |
| 中等或已被左右分過（100～160 欄） | `down` | 再往右分會掉到 60～80 欄，agent 的 TUI 會擠爛 |
| 矮（< 40 列） | `right` | 再往下分只剩 20 列，看不到 agent 在做什麼 |

連續同方向分兩三次就會做出一條沒人讀得了的細長條。

你明講方向時，skill 照你的做，不用這張表覆蓋你。

### 三個不能省的參數

```
herdr pane split --current --direction <right|down> --cwd "$PWD" --no-focus
```

| 參數 | 少了會怎樣 |
| --- | --- |
| `--current` | 打到 UI 焦點所在的 pane。那可能是你正在用的，或別的 client 的。 |
| `--cwd "$PWD"` | 新 pane 不繼承工作目錄。agent 會在家目錄啟動，然後對著錯的 repo 開工。 |
| `--no-focus` | 你的視線被搶走。你叫它開 pane 是要它在背景跑。 |

## 交手之後怎麼盯

skill 回報時會附這三行，可直接複製：

```
herdr agent focus <name>                      # 切過去看
herdr agent read <name> --lines 60            # 讓主 Claude 讀它的輸出
herdr agent wait <name> --until blocked done  # 等它卡住或做完
```

skill **不會**留下來自動盯。主 agent 被佔住的話，你就不能同時跟它講別的事，而那正是你開第二個 pane 的原因。

你要它盯的話，直接說。

### 讀不到完整輸出時

`--lines` 加大還是看不到完整回應，代表 agent 跑在終端機的 alternate screen。那些行不會進 Herdr 的 scrollback，加再多也撈不回來。

這時才改用檔案：叫那個 agent 把完整回應寫成 Markdown 放 temp 目錄、只回檔案路徑，然後直接讀檔。

這是 fallback。skill 規定不要在一開始就這樣要求。

## 為什麼不用 tmux 代替

`HERDR_ENV` 不是 1 時，skill 停止而不改用 tmux、screen 或背景程序。

理由：那些方式開出來的東西 Herdr 看不到，你也 attach 不進去。結果是一個你管不到的黑箱。

Herdr 提供的東西是替代不了的：

- 它辨識 pane 裡的 agent，並解讀 `idle`、`working`、`blocked`、`done` 生命週期。
- 它讓你隨時切過去看、中斷、接手。
- 它用穩定的 pane id 定位，不靠畫面內容猜。

## 與 linear-flow 的關係

`linear-flow` 裡有幾支 skill 自己也會開 Herdr pane：

- `herdr-claude-wave`
- `herdr-codex-wave`
- `parallel-loop`

差別在**誰是主體**。

| | 做什麼 |
| --- | --- |
| `herdr` 的 `create-herdr-wave-agent` | 開一個 pane，派一份工作，交手。不管票、不管整合。 |
| `linear-flow` 的 wave 系列 | 盤點看板、分派多張票、審碼、rebase、fast-forward 整合、維護 Linear 狀態。 |

常見用法是兩個一起用：用 `create-herdr-wave-agent` 開一個 pane，派給它 `herdr-claude-wave`，然後那個 agent 自己再開更多 pane 做票。

你只要前者的話，不需要裝 `linear-flow`。
