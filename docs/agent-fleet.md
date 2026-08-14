[← 回目錄](README.md)

# agent-fleet

用 Telegram 管理一群 Claude Code agent 的設計參考。

## 先讀這一段

**這個 plugin 與其他五個性質不同。**

其他 plugin 裝了就能用。這一個**不能**。

它是**設計與維運參考文件**，不是可執行的工具。它描述一套可運作的模式，以及那套模式裡的陷阱。它提到的 `~/agents/scripts/*` 腳本（`new-agent.sh`、`launch-agent.sh`、`seed-telegram-plugin.sh` 等）**沒有一起發佈**。你要自己寫，或從既有的 fleet 搬過來。

把它當作藍圖來讀。不要當作安裝包。

## 它描述什麼

一群 Claude Code agent 住在同一個終端多工器 session（`claude-agents`）裡。

每一個 agent 是：

- 一個 window 或 pane。
- 一個自己的 `CLAUDE_CONFIG_DIR`。
- 一個自己的 Telegram bot（服務型 agent 除外）。

agent 之間用 `agent-send.sh` 溝通。agent 與你之間用 Telegram 溝通。

## 安裝

```
/plugin marketplace add Soda3752/skills
/plugin install agent-fleet@soda-skills
```

安裝後你得到的是文件。不是可執行的 fleet。

## 收錄它的價值

它的價值在那些**踩過才知道的坑**。

最好的例子：手工安裝 plugin 時漏了 `known_marketplaces.json` 的 `installLocation`，Claude 會**完全不載入該 plugin，而且不留任何錯誤訊息**。

這種問題你自己查會花很久。

---

## 核心概念一：CONFIG 目錄與 STATE 目錄要分開

這是整份文件最重要的一點。搞錯就什麼都不會動。

兩棵樹，刻意分開：

```
~/agents/                       ← CONFIG。要進版控。
├── _template/                  ← new-agent.sh 的複製來源
├── <name>/
│   ├── CLAUDE.md               ← 角色定義 + import 共用規則
│   └── .claude/                ← 這個 agent 的 CLAUDE_CONFIG_DIR
│       ├── settings.json
│       ├── skills/
│       ├── plugins/            ← ★ claude 從這裡讀 plugin
│       └── .credentials.json
├── shared/rules/*.md
├── shared/telegram-fork/
├── scripts/
└── .trash/YYYYMMDD/            ← 軟刪除。禁止用 rm。

~/.claude-agents/               ← STATE。執行期產生。絕不進版控。
├── pane-registry               ← name<TAB>pane_id 對照表
└── <name>/
    ├── channels/telegram/
    ├── plugins/                ← ⚠ claude 不從這裡讀
    ├── claude.running
    └── restart-requested
```

**最經典的失敗**是把 plugin 快取放進 STATE 目錄。放錯位置時 Claude 讀不到，而且不會報錯。

---

## 核心概念二：用 registry 判斷身分，不要用畫面

agent 與 pane 的對應關係存在 `~/.claude-agents/pane-registry`。格式是 `name<TAB>pane_id`。

**不要**用這三種方式推導身分：

| 不要用 | 原因 |
| --- | --- |
| `pane_title` | Claude Code 會改寫它。 |
| `pane_current_command` | Claude Code 會改寫它。 |
| 多工器的 `@user-options` | psmux 3.3.4 把它存成全域。最後寫入的覆蓋前面的。 |

手動重建 window 時，記得呼叫 `registry_set` 登記新的 pane。忘記的症狀是 `agent-send` 回報 "no pane found"。

---

## 核心概念三：用標記檔判斷存活，不要看畫面

`launch-agent.sh` 在啟動 claude 前建立 `$STATE_DIR/claude.running`。它用 `EXIT` trap 清除。

`pane_is_alive()` 讀這個標記。**這是唯一正確的存活測試。**

**不要用畫面判斷。** 一個實際踩過的案例：

Windows 上的 fleet 用「最後一行是不是單獨一個 `$`」來偵測 idle 的 bash。這個判斷在 macOS 上**永遠不會成立**，因為 macOS 的預設提示字元是 `<host>:<dir> <user>$`。

症狀是：重啟一直失敗，訊息說「TUI 還在」，但 pane 其實早就閒置了。

已知缺口：`SIGKILL` 或 `kill-pane` 會跳過 trap，留下過時的標記。重啟前要手動清除。

---

## 核心概念四：Telegram 頻道的設定

每個 agent 的 Telegram 檔案放在 `~/.claude-agents/<name>/channels/telegram/`：

| 檔案 | 內容 |
| --- | --- |
| `.env` | `TELEGRAM_BOT_TOKEN`。權限設 600。 |
| `access.json` | 存取政策、允許的使用者、群組設定。 |
| `bot.pid` | poller 的 PID。**這是唯一的存活訊號。** |
| `inbox/` | 附件下載位置。 |

**沒有 `bot.pid` 就代表 poller 已停止，agent 收不到 Telegram 訊息。**

### 兩個一定要知道的陷阱

**1. 直接編輯 `access.json`。不要用 `/telegram:access` skill。**
那個 skill 把路徑寫死成 `~/.claude/channels/telegram/access.json`。它忽略每個 agent 各自的 `TELEGRAM_STATE_DIR`。

**2. 基本群組收不到 @mention。**
新的 bot 預設開啟 Group Privacy。

- 超級群組（`-100…`）可以正常收到 @mention。
- 基本群組（`-5xxxxxxxxx`）**收不到**。

解法：在 BotFather 執行 `/setprivacy` 並選 Disable，然後把 bot 移出群組再重新加入。

送訊息**到**群組不受影響。

---

## 主機專屬資訊要留在本機

文件本身只寫「在每一台機器上都成立的事」。

以下這些是**機器專屬**的，要寫在 `hosts/` 底下的個別檔案：

- agent 名冊
- 工具的絕對路徑
- 版本 pin
- 多工器選擇
- 平台差異

每台機器複製一份 `hosts/EXAMPLE-host.md`。

### 為什麼真實主機檔不進版控

一份填好的主機檔，是一台**用 `--dangerously-skip-permissions` 執行 agent 的機器**的完整配置圖。

它寫出：確切的工具路徑、每個 agent 接了什麼、有哪些 bot 存在。

那是攻擊面清單，不是文件。它屬於那台機器，不屬於公開 repo。

所以本 repo 只發佈 `hosts/EXAMPLE-host.md` 骨架。

## 深入說明

skill 目錄下有兩份參考文件：

| 檔案 | 內容 |
| --- | --- |
| `references/telegram-plugin.md` | 分支版 Telegram plugin：手動安裝、修復、為什麼版本標籤不可信 |
| `references/porting.md` | 把 fleet 移植到新作業系統的完整差異清單 |
