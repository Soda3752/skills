# Herdr CLI 契約（已實查）

實查環境：herdr（`~/.local/bin/herdr`）、codex-cli 0.147.0、macOS。所有指令都回 JSON 到 stdout。

## 目錄

- [前置：integration](#前置integration)
- [開一個 pane](#開一個-pane)
- [起 Codex 並派工](#起-codex-並派工)
- [等待完工](#等待完工)
- [觀察與介入](#觀察與介入)
- [收場](#收場)
- [Codex 的 MCP 從哪來](#codex-的-mcp-從哪來)
- [已知未知](#已知未知)

---

## 前置：integration

```bash
herdr integration status                  # 全部 integration 的安裝狀態
herdr integration install codex           # 寫入 ~/.codex/herdr-agent-state.sh
```

安裝時的實際輸出：

```
installed codex integration hook to /Users/…/.codex/herdr-agent-state.sh
ensured codex hooks at /Users/…/.codex/hooks.json
ensured codex config at /Users/…/.codex/config.toml
```

**它會動 `~/.codex/hooks.json` 與 `~/.codex/config.toml`**，屬於改使用者設定，先徵得同意。

沒裝的後果：`agent_status` 永遠是 `unknown`，`herdr agent wait` 等不到狀態轉換，只能 `herdr agent read` 讀畫面尾端猜——Codex 思考久一點就會被誤判成 idle。

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

## 起 Codex 並派工

```bash
herdr agent start <name> --kind codex --pane <pane_id> -- --dangerously-bypass-approvals-and-sandbox
```

- `<name>` 是你自己取的 handle，後續所有 `herdr agent *` 都用它（用票號小寫最好認）
- `--kind` 可選值：`pi claude codex gemini cursor devin agy cline omp mastracode opencode copilot kimi kiro droid amp grok hermes kilo qodercli maki`
- `--` 之後的參數原樣傳給 codex 執行檔
- pane 必須在互動 shell 提示符下（剛 create 的就是）
- 成功回傳含 `"agent_status": "idle"`、`"interactive_ready": true`、以及 `"argv": ["codex", "--dangerously-bypass-approvals-and-sandbox"]`
- `--timeout <MS>` 等互動就緒，預設 30000、上限 300000

派工：

```bash
herdr agent prompt <name> "$(cat prompt.txt)"
```

長的多行指令用 `"$(cat 檔案)"` 傳沒問題，實測 6000 字元的中文指令正常。派工後 `agent_status` 會從 `idle` 轉 `working`（約數秒內）。

`herdr agent prompt` 也吃 `--wait`，但**分波派工時不要用**——那會變成串行。用第 4 步的 Monitor 模式。

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
      && echo "[$a] 已回到 idle — 可回收" \
      || echo "[$a] wait 逾時或出錯" ) &
done
wait
```

每個 pane 完工時各自送一則通知，先回報的可以先整合。

---

## 觀察與介入

```bash
herdr agent list                    # 所有 agent 與 agent_status
herdr agent get <name>
herdr agent read <name>             # 讀 pane 終端輸出
herdr agent explain <name>          # 解釋偵測狀態（integration 有問題時用這個查）
herdr agent prompt <name> "<補正指令>"   # 同一個 pane 續談，保留完整脈絡
herdr agent focus <name>            # 把使用者的畫面切過去
herdr agent attach <name>           # 直接接進終端
```

`herdr agent list` 的回傳含 `agent_session.value`（Codex 的 session id），要對回 Codex 自己的紀錄時用得上。

摘要 agent 狀態：

```bash
herdr agent list | python3 -c "import sys,json;d=json.load(sys.stdin);[print(a.get('name',a['agent']),'->',a['agent_status']) for a in d['result']['agents']]"
```

**pane 卡住時優先用 `herdr agent prompt` 補一句更緊的指令**，而不是殺掉重來——同一個 pane 保留了它已經讀過的票與已經跑過的建置。

告訴使用者他們可以自己 `herdr agent attach proj-111` 進去看，這是本工作流相對於背景 job 最大的好處。

---

## 收場

```bash
herdr workspace close <workspace_id>
```

回 `{"result": {"type": "ok"}}`。**先 `git worktree remove` 再 close workspace**，順序反了的話 worktree 的 cwd 會消失但 pane 還活著。

---

## Codex 的 MCP 從哪來

Codex 讀 `~/.codex/config.toml`，**不讀專案的 `.mcp.json`**。實查過的形狀：

```toml
[mcp_servers]

[mcp_servers.gitnexus]
command = "/opt/homebrew/bin/gitnexus"
args = ["mcp"]

[mcp_servers.linear]
url = "https://mcp.linear.app/mcp"

[mcp_servers.linear.tools.save_comment]
approval_mode = "approve"

[projects."/path/to/repo"]
trust_level = "trusted"
```

兩件事要注意：

1. **有 linear 就讓 pane 自己讀票**（`get_issue`、`list_comments`）。這是本 skill 與 `codex-wave` 最大的差異——那份的前提是「Codex 沒有 Linear MCP、寫不了票」，在這個設定下不成立。
2. **`[projects.…]` 的 `trust_level` 不涵蓋 worktree 路徑**（worktree 在 repo 外的目錄）。Yolo Mode 下這不影響執行，但若哪天不用 Yolo Mode，要記得 worktree 路徑是未信任的。

即使 pane 讀得到 Linear，**指令裡仍要明令它不准改票券狀態、不准留言**——那是主控 Agent 的職責，讓 pane 碰會讓看板的因果關係變得無法追溯。`config.toml` 裡 `save_comment` 設 `approval_mode = "approve"` 是額外一層保險，但 Yolo Mode 會繞過它，所以指令裡的明令才是真正的防線。

---

## 已知未知

- **同時開超過 4 個 pane 沒有實測過。** 實測過 2 個一波、共兩波，狀態偵測與隔離都正常。pane 各自是獨立的 codex 程序、獨立 cwd，理論上不像 `codex-wave` 的背景 job 有 repo 層級的 job 狀態共用問題，但沒驗證過就不要一口氣開 8 個。
- **pane 在 `blocked` 狀態下的行為沒實測過。** `herdr agent wait` 會因 `blocked` 而返回，但 Codex 在 Yolo Mode 下理論上不會停下來要求確認。若真的遇到，`herdr agent read` 看畫面。
- **使用者手動關掉 pane 時的處理沒實測過。** 遇到 pane 不存在的錯誤就 `herdr workspace list` / `herdr agent list` 重新取得現況。
