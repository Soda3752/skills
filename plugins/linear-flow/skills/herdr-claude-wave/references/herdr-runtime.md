# Herdr CLI 契約（已實查，Claude pane 版）

實查環境：herdr（`~/.local/bin/herdr`）、Claude Code CLI、macOS。所有指令都回 JSON 到 stdout。

**與 `herdr-codex-wave/references/herdr-runtime.md` 共用同一套 CLI**，差別只在 integration 名稱、`--kind`、`--` 之後的旗標，以及 MCP / 專案指令的來源。本檔只寫這些差異與 Claude pane 特有的行為。

## 目錄

- [前置：integration](#前置integration)
- [開一個 pane](#開一個-pane)
- [起 Claude Code 並派工](#起-claude-code-並派工)
- [等待完工](#等待完工)
- [blocked 的處理](#blocked-的處理)
- [觀察與介入](#觀察與介入)
- [收場](#收場)
- [Claude pane 的專案指令與 MCP 從哪來](#claude-pane-的專案指令與-mcp-從哪來)
- [已知未知](#已知未知)

---

## 前置：integration

```bash
herdr integration status | grep claude    # 期望看到 claude: current (vN)
herdr integration install claude          # 寫入 ~/.claude/hooks/herdr-agent-state.sh
```

**它會動 `~/.claude/` 底下的 hook 設定**，屬於改使用者設定，先徵得同意。

沒裝的後果：`agent_status` 永遠是 `unknown`，`herdr agent wait` 等不到狀態轉換，只能 `herdr agent read` 讀畫面尾端猜——Claude 思考久一點就會被誤判成 idle。

`herdr integration list` 會列出支援的 agent 種類（pi / claude / codex / copilot / droid / cursor / grok / opencode …）。

---

## 開一個 pane

```bash
herdr workspace create --cwd "<絕對路徑>" --label "PROJ-111" --no-focus
```

回傳結構（節錄）：

```json
{"result": {
  "type": "workspace_created",
  "root_pane": {"pane_id": "w9:p1", "tab_id": "w9:t1", "cwd": "…", "agent_status": "unknown"},
  "workspace": {"workspace_id": "w9", "label": "PROJ-111", "number": 2}
}}
```

**要的是 `result.root_pane.pane_id`**：

```bash
herdr workspace create --cwd "$WT" --label "$T" --no-focus \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['root_pane']['pane_id'])"
```

`workspace_id` 是 `w8`、`w9`、`wA`、`wB`…（十六進位遞增），`pane_id` 形如 `w9:p1`。**不要跨 session 重用舊的 id。**

`--no-focus` 讓使用者的畫面不被搶走。其他可用選項：`--env KEY=VALUE`（例如每票給不同的 dev server port）。

---

## 起 Claude Code 並派工

```bash
herdr agent start <name> --kind claude --pane <pane_id> \
  -- --permission-mode auto --add-dir "<主 repo 絕對路徑>"
```

- `<name>` 是你自己取的 handle，後續所有 `herdr agent *` 都用它。**用票號小寫最好認**（`proj-111`）；名稱規則是 `[a-z][a-z0-9_-]{0,31}`，而且**存活的 agent 之間必須唯一**——上一輪的同名 agent 還活著會直接失敗。
- `--kind claude`
- `--` 之後的參數原樣傳給 `claude` 執行檔
- pane 必須在互動 shell 提示符下（剛 create 的就是）
- `--timeout <MS>` 等互動就緒，預設 30000、上限 300000

### `--` 之後值得傳的旗標

| 旗標 | 為什麼 |
| --- | --- |
| `--permission-mode auto` | 分類器自動放行低風險指令；沒接住的會停成 `blocked` 由你放行。**本 skill 的預設。** |
| `--add-dir <主 repo>` | Claude Code 的工具存取限於 cwd 及子目錄。規格文件常在主 repo 的 gitignore 目錄裡，不加這個就讀不到。**注意它同時給了寫入能力，唯讀紀律只能靠指令明令。** |
| `--model <model>` | 想讓某些票跑便宜一點的模型時用。地基票不要省。 |
| `--dangerously-skip-permissions` | 完全跳過確認。**需使用者明確要求**，理由見 SKILL.md 第 3 步。 |
| `--mcp-config <file>` | worktree 裡缺專案 `.mcp.json` 又不想整包複製 `.claude/` 時的替代做法。 |

派工：

```bash
herdr agent prompt <name> "$(cat prompt.txt)"
```

長的多行指令用 `"$(cat 檔案)"` 傳沒問題——雙引號包住的命令替換不會對內容做二次展開，反引號與 `$(...)` 都安全。**但不要把指令內容 inline 展開寫在指令行裡**，那才會被 shell 吃掉一段而 pane 照著殘缺指令做。

派工後 `agent_status` 會從 `idle` 轉 `working`（約數秒內）。

`herdr agent prompt` 也吃 `--wait`（只等第一次狀態轉換，不是等做完），但**分波派工時不要用**——那會變成串行。用下一節的 Monitor 模式。

---

## 等待完工

```bash
herdr agent wait <name> [--until idle|working|blocked|done|unknown] [--timeout <MS>]
```

不帶 `--until` 時等 `idle` / `done` / `blocked` 任一。不帶 `--timeout` 會無限等。

多個 pane 一起等，包在 `Monitor` 裡：

```bash
for a in proj-111 proj-112; do
  ( herdr agent wait $a --timeout 3000000 >/dev/null 2>&1 \
      && echo "[$a] 已離開 working — 去對帳" \
      || echo "[$a] wait 逾時或出錯" ) &
done
wait
```

**通知文字寫「去對帳」而不是「完工」是刻意的。** `--permission-mode auto` 下 `blocked` 也會讓 `wait` 返回，把返回當成完工會讓你去讀一個還不存在的 `RESULT.md`。醒來一律先 `herdr agent list` 看實際狀態。

摘要 agent 狀態：

```bash
herdr agent list | python3 -c "import sys,json;d=json.load(sys.stdin);[print(a.get('name',a['agent']),'->',a['agent_status']) for a in d['result']['agents']]"
```

---

## blocked 的處理

這是 Claude pane 版相對 Codex Yolo Mode 多出來的一段常態工作。

```bash
herdr agent read <name> --source detection --lines 40
```

`--source detection` 給的是 Herdr 判定狀態時看的那段畫面，比 `visible` 準。看清楚它在問什麼：

| 它在問 | 你要做的 |
| --- | --- |
| 權限確認（跑某個指令、寫某個檔） | 落在合理範圍（自己的 worktree、verify 指令、讀主 repo）就 `herdr agent send-keys <name> <鍵>` 放行，並**把該指令補進 worktree 的 `.claude/settings.local.json` 白名單**，讓它下次不再問 |
| 規格提問（這個欄位要顯示什麼？） | 你答不了，帶回來問使用者。不要自己編一個答案送回去 |
| 它自己卡住在打轉 | `herdr agent prompt` 補一句更緊的指令，同一個 pane 保留完整脈絡 |

`send-keys` 的鍵名照 `herdr agent read` 畫面上顯示的選項給。放行前**先看清楚它要跑什麼**——`auto` 沒放行的指令通常是有理由的。

同一批指令反覆撞牆就一次補齊整組白名單，不要一次放行一條——那會把整波的節奏拖垮。

---

## 觀察與介入

```bash
herdr agent list                    # 所有 agent 與 agent_status
herdr agent get <name>
herdr agent read <name> [--source visible|recent|detection] [--lines N]
herdr agent explain <name>          # 解釋偵測狀態（integration 有問題時用這個查）
herdr agent prompt <name> "<補正指令>"   # 同一個 pane 續談，保留完整脈絡
herdr agent focus <name>            # 把使用者的畫面切過去
herdr agent attach <name>           # 直接接進終端
```

**pane 卡住時優先用 `herdr agent prompt` 補一句更緊的指令**，而不是殺掉重來——同一個 pane 保留了它已經讀過的票與已經跑過的建置。

告訴使用者他們可以自己 `herdr agent attach proj-111` 進去看，這是本工作流相對於背景 job 最大的好處。

---

## 收場

```bash
herdr workspace close <workspace_id>
```

回 `{"result": {"type": "ok"}}`。**先 `git worktree remove` 再 close workspace**，順序反了的話 worktree 的 cwd 會消失但 pane 還活著。

失敗的票**留著不要清**——worktree 與 pane 的 context 都在，那是給使用者直接接手的失敗現場。

---

## Claude pane 的專案指令與 MCP 從哪來

**這是本檔與 Codex 版差最多的一節。** Codex 讀 `~/.codex/config.toml`（全域、與 cwd 無關）；Claude Code 是**分層**的，而 worktree 剛好缺了其中一層：

| 層 | 路徑 | worktree 裡有嗎 |
| --- | --- | --- |
| user 全域設定 / MCP | `~/.claude/settings.json`、`~/.claude.json` | **有**（跟 cwd 無關） |
| user 層 skill | `~/.claude/skills/` | **有** |
| 專案 MCP | `<repo>/.mcp.json` | 有進版控才有 |
| 專案指令 | `<repo>/CLAUDE.md`、`CLAUDE.local.md` | `CLAUDE.md` 通常有；`CLAUDE.local.md` 幾乎一定沒有 |
| 專案層 skill / 設定 | `<repo>/.claude/**` | **通常整包 gitignore，一律沒有** |

三個實際症狀，**都不會有錯誤訊息**：

1. pane 在完全沒有專案指令下工作——它不知道「UI 文字一律繁中」「改 symbol 前先跑影響分析」這類硬規則。
2. 專案層 skill 叫不動，pane 回 `Unknown command: /xxx`。若用了 `--wait`，你只會收到一個看不出原因的 `agent_prompt_stalled`。
3. 專案 `.mcp.json` 裡的 linear / gitnexus 不見了，於是「讓 pane 自己讀票」整段失效——而 pane 會改用你指令裡的摘要做事，你不會發現。

**對策：第 2 步把整個 `.claude/`、`CLAUDE.md`、`CLAUDE.local.md`、`.mcp.json` 一起複製進 worktree。** 複製比逐項挑穩，副作用只是 pane 看得到主 repo 的報告（唯讀性質，無害）。替代做法是 `--mcp-config` 明確指一份設定，但那只解決 MCP 一項。

**確認方式不要用猜的**——派工前在 worktree 裡確認關鍵檔在：

```bash
ls -d "$WT/.claude" "$WT/CLAUDE.md" "$WT/.mcp.json" 2>&1
```

---

## 已知未知

- **同時開超過 4 個 Claude pane 沒有實測過。** pane 各自是獨立的 claude 程序、獨立 cwd，隔離上沒有已知問題，但沒驗證過就不要一口氣開 8 個——而且可見 pane 的上限本來就是使用者看得過來幾個。
- **`--permission-mode auto` 在多 pane 同時 blocked 時的處理節奏沒有實測數據。** 理論上你會被 `wait` 依序叫醒逐一放行，但若整波都卡在同一類指令，先補白名單再一起放行會快得多。
- **使用者手動關掉 pane 時的處理沒實測過。** 遇到 pane 不存在的錯誤就 `herdr workspace list` / `herdr agent list` 重新取得現況。
- **worktree 裡那份 `.claude/` 被 pane 寫入時沒有任何保護。** 目前只靠指令明令，沒有機制擋。若哪天要硬擋，`--settings` 搭配 deny 規則是可能的方向，未實測。
