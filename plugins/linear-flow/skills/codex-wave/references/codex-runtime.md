# Codex 執行契約

以下指令與旗標是**實查驗證**的（openai-codex plugin 1.0.6、codex-cli 0.147.0），不是從文件推測的。若某天對不上，以 `--help` 的實際輸出為準並回報使用者。

## 找到 plugin 路徑

```bash
PLUGIN_ROOT=$(find ~/.claude/plugins/cache/openai-codex -maxdepth 2 -type d -name "codex" | head -1)
# 或指定版本目錄：~/.claude/plugins/cache/openai-codex/codex/<version>
```

指令一律用 `node "$PLUGIN_ROOT/scripts/codex-companion.mjs" <subcommand>`。

## 指令表

```
setup              [--enable-review-gate|--disable-review-gate] [--json]
review             [--wait|--background] [--base <ref>] [--scope <auto|working-tree|branch>]
adversarial-review [--wait|--background] [--base <ref>] [--scope <auto|working-tree|branch>] [focus text]
task               [--background] [--write] [--resume-last|--resume|--fresh]
                   [--model <model|spark>] [--effort <none|minimal|low|medium|high|xhigh>] [prompt]
transfer           [--source <claude-jsonl>] [--json]
status             [job-id] [--all] [--json]
result             [job-id] [--json]
cancel             [job-id] [--json]
```

## 本 skill 用到的組合

| 目的 | 指令 |
| --- | --- |
| 派一張票（背景、可寫檔） | `cd <worktree> && node "$PLUGIN_ROOT/scripts/codex-companion.mjs" task --background --write "<prompt>"` |
| 看全部 job | `... status --all` |
| 等某個 job | `... status <job-id> --wait --timeout-ms <ms>` |
| 取結果 | `... result <job-id>` |
| 送後續指令（同 thread） | `cd <worktree> && ... task --resume-last --write "<只有差異的指令>"` |
| 中止 | `... cancel <job-id>` |
| 對 diff 做對抗式審查 | `cd <worktree> && ... adversarial-review --background --base <base分支>` |

`--json` 在需要程式化解析時加，人看的時候不加。

## 旗標的預設立場

- **`--write` 要明確加**。不加就是唯讀，Codex 改不了檔案，卻可能看起來「完成了」。
- **`--model` 與 `--effort` 預設不給**。plugin 的指引是先把 prompt 契約寫緊，再談推理強度。使用者明確要求才給。`spark` 要正規化成 `gpt-5.3-codex-spark`。
- **`--resume-last` 只用在同一張票的後續指令**。跨票用會接到別人的 thread——這正是並發關卡要驗的事。
- **`--fresh`** 用在明確要重開一條 thread 的時候。

## 工作目錄

Codex 以**呼叫時的 cwd** 為工作目錄（實測：在 repo 根呼叫，它回報的 working directory 就是 repo 根）。所以 worktree 隔離**完全依賴呼叫前 `cd` 到正確的 worktree**。

```bash
cd "<worktreeRoot>/<ticket-dir>" && node "$PLUGIN_ROOT/scripts/codex-companion.mjs" task --background --write "..."
```

漏掉 `cd` 的後果是 Codex 直接改到主 repo，而且你不會馬上發現。**每次派工前確認 cwd**。

## ⚠️ 已知未知：背景 job 的並發安全性

`status` 的說明是「show active recent Codex jobs **in repository**」——job 以 repository 為單位追蹤。多個 worktree 共用同一個 `.git`，因此**尚未確認**：

1. 同一 repo 底下多個 worktree 各起一個背景 job，job id 是否確實互不衝突
2. `--resume-last` 在多 job 並存時，接到的是哪一條 thread
3. `status --all` / `result <id>` 能否正確區分不同 worktree 的 job

**這不是理論疑慮**：若 `--resume-last` 接錯 thread，Codex 會把 A 票的修正指令套到 B 票的脈絡上，而產出看起來完全正常。

### 首次使用的驗證程序

在某個 repo 第一次用本 skill 時，先派兩張**改動範圍明顯不同**的票（例如一張改 UI、一張改資料層），然後：

```bash
node "$PLUGIN_ROOT/scripts/codex-companion.mjs" status --all
# 確認：兩個不同 job id 同時出現

git -C "<worktreeA>" status --short
git -C "<worktreeB>" status --short
# 確認：各自只有自己該有的檔案，沒有互相污染

node "$PLUGIN_ROOT/scripts/codex-companion.mjs" result <jobA>
# 確認：拿回的是 A 票的內容
```

三項全過才放大到 N 張。任一項不過，退回一次一張串行。

**把結果寫進記憶**（哪個 repo、幾張並發實測沒問題、有沒有踩到 `--resume-last` 的坑），下次直接用，不必重驗。

## 認證

`codex --version` 跑不起來或提示要登入時**停下來請使用者自己處理**。建議他們在對話框輸入 `! codex login`——輸出會直接回到對話裡。**不要代為輸入任何憑證。**

## review gate

`setup --enable-review-gate` 會裝一個 stop-time 的 review 關卡（hook）。本 skill **不主動開關它**——那會改動使用者的全域行為。使用者若問起，說明它的作用讓他自己決定。
