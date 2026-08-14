---
name: parallel-ticket
description: "並行 Linear loop 的單票實作 skill：在自己的 git worktree 裡把一張票做完 —— dev → codex adversarial review 與修正 → 驗證與 E2E → rebase base 分支 → squash → 寫結果檔，然後停下來等主 Agent 做 ff merge。由 parallel-loop 主 Agent 透過 herdr agent prompt 呼叫，一般不由使用者直接觸發。Use this when a Herdr implementation pane is told to work a single Linear ticket end-to-end inside its own worktree, or when asked to re-rebase after the main agent's fast-forward failed. Triggers: \"/parallel-ticket PROJ-xx\", \"做這張票到可以合併為止\", \"重新 rebase 後更新結果檔\"."
---

# Parallel Ticket —— 單票實作 pane

你在一個**專屬的 git worktree** 裡，把一張 Linear 票做到「可以被 fast-forward 進 base 分支」的狀態，然後停下來。

**你不做合併，不推終態，不寫紀錄檔。** 那是主 Agent 的事。

用法：`/parallel-ticket <TICKET> --slot <N> --port <PORT>`

---

## 0. 你的邊界

```
主 Agent（另一個 pane）          你（這個 pane）
─────────────────────────────────────────────────────
建 worktree、複製種子檔    →     dev / review / test / rebase / squash
推 In Progress             →     推 In Review + 進度註解
                           ←     寫結果檔
ff merge 進 base           ←
推終態 + 實作紀錄註解
寫 index / HANDOFF / landmines
```

**票號從參數拿，其餘一切從外部世界推導** —— 你也適用零記憶紀律：`attempt` 次數、上一輪為什麼失敗、票的驗收條件，全部去查，不要靠別人在 prompt 裡告訴你。

---

## 1. 絕對規則（違反即視為本階段失敗）

**先解析出主 repo 的絕對路徑，本檔以下所有 `<主repo>` 都指它。** 你的 worktree 裡**沒有** `.claude/` —— 那個目錄是 gitignore，`git worktree` 只帶 tracked 檔案。所以設定檔、結果檔、階段鎖一律走主 repo：

```bash
MAIN_REPO="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
```

`--show-toplevel` 在 worktree 裡回的是你自己，不是主 repo，別拿它當 `<主repo>`。

設定值一律讀 `<主repo>/.claude/parallel-loop.json`（**唯讀，不要改它**）。

1. **你的工作目錄是自己的 worktree。** 所有 git 與檔案操作都在這個路徑底下。**絕對不要 `cd` 回主 repo，也不要對 base 分支做任何寫入。** 每次下 git 指令前先確認：

   ```bash
   git rev-parse --abbrev-ref HEAD    # 必須是你的票號分支
   git rev-parse --show-toplevel      # 必須是你的 worktree
   ```

2. **`protectedPaths` 列的路徑一律禁止修改（讀可以）。** 包含 `CLAUDE.md`、`.claude/skills/**`、`.claude/workflows/**`、所有設定檔、`HANDOFF.md`、`spec.md`、`docs/adr/**`、`**/settings.json`。紀錄檔由主 Agent 統一寫 —— **`$MAIN_REPO` 底下的那些檔一律不准動**（`HANDOFF.md` 是 tracked，你的 worktree 裡就有一份，那份也不准動），動了會讓每條分支在檔尾互相衝突。

3. **終態與實作紀錄註解由主 Agent 推。** 你只推 `In Review` 與進度註解（第 5 步）。**不要推 Done / Blocked / API Require、不要動 labels。** 你要傳達的一切都寫進結果檔。

4. **`conflictRules.appendOnlyPaths`（barrel 檔）只准在檔尾追加 export**，不准重排、不准修改既有行。

5. **`conflictRules.exclusivePaths`（`package.json`、`package-lock.json`、`wrangler.toml`、`migrations/**`）未經主 Agent 允許不得修改** —— 同時在飛的其他票可能也要動它們。非改不可就中止，在結果檔的 `blockedReason` 說明，主 Agent 會改排成獨占票。

6. **一律用參數給的 `--port`**，不要用預設 8787 —— 其他票正在用。所有起 dev server 的指令都要帶 `E2E_PORT=<port>`。

7. **codex review 與 test 兩個階段要先搶名額**（第 6、7 步）。這台機器 12 核，5 個 pane 同時跑 build + wrangler + chromium 會互搶到單票反而變慢。

---

## 2. 步驟 0：確認現場，判斷是新做還是重入

主 Agent 已經幫你建好 worktree、切好分支、複製好種子檔（`.dev.vars`、`市區明細.xlsx`、`fixtures/`）。你先確認：

```bash
git rev-parse --abbrev-ref HEAD
git log --oneline -5
ls -la .dev.vars fixtures 2>/dev/null
```

**判斷 attempt**：數 `$MAIN_REPO/.claude/parallel-loop-state/<TICKET>.attempt-*.json`。有 N 個檔就代表這是第 N+1 次。

**重入（分支上已經有你的 commit）**：

```bash
git fetch . <baseBranch>:<baseBranch> 2>/dev/null || true
git rebase <baseBranch>
```

先讀**上一個 attempt 的結果檔**（`failures`、`blockedReason`、`review.blockingFindings`）與 Linear description 最下方的 `## Bug Fix（第 N 次）` —— 那是上一輪留給你的交接資訊，不要重走同一條死路。

rebase 衝突且無法明確判斷正確解時**不要硬解**：`git rebase --abort`，結果檔寫 `disposition: "blocked"` 並在 `blockedReason` 列清楚衝突檔案。

種子檔缺了就自己補：`cp -R "$MAIN_REPO/<檔>" .`；`fixtures/` 仍不存在就 `npm run fixtures:density`。這些都是 gitignore，不會進 commit。

`node_modules/` 也一樣不隨 worktree 過來，缺了就 `cp -R "$MAIN_REPO/node_modules" .`（實測 4.5 秒，比 `npm ci` 快一個數量級，且 lockfile 必然與主 repo 一致）。**沒有它整組 verify 會全紅在跟本次改動完全無關的地方** —— 那是最浪費一輪的失敗模式。

---

## 3. 讀票與驗收條件分類

```
get_issue({ id: "<TICKET>" })
```

**這是你唯一允許讀 Linear 的用途。**

把**每一條**驗收條件抄下來，各標一個類別：

| 類別 | 意思 |
| --- | --- |
| `automated` | 能寫 E2E / verify 腳本驗 |
| `manual` | 必須真人操作（實機掃 QR、看版面美感） |
| `static` | 讀程式碼就能確認 |

**這個分類直接決定測試階段做什麼，不要偷懶全填 automated。** 也不要把不確定的塞進 static 蒙混 —— 判錯的後果是假通過，而假通過的程式碼會直接被合併進 base。

---

## 4. Dev

實作。**跟著周圍程式碼的風格走**：註解密度、命名、慣用寫法都對齊既有檔案。這個 repo 的註解是繁體中文，且傾向解釋「為什麼」而非「做什麼」。

跑 `commands.verify` 的全部閘門（設定檔目前列了 15 條：typecheck / lint / build ＋ 12 支專案自製的 tsx 驗證腳本）。**全綠才算完成。**

commit，訊息照 repo 慣例：`feat(<TICKET>): 摘要` 或 `fix(<TICKET>): 摘要`。一次 commit 就好 —— review 修正會是第二個 commit，最後你會 squash 成一個。

### 什麼情況要中止

寫結果檔然後停下來，**不要賭**：

| 情況 | disposition | 額外欄位 |
| --- | --- | --- |
| 需要後端動作（API 沒提供、契約不完整、錯誤碼未定義） | `apiRequire` | `needsBackend: true` |
| 規格有歧義且不同解讀會做出不同東西 | `blocked` | `blockedReason` 寫清楚歧義點與你需要的裁示 |
| 非改 `exclusivePaths` 不可 | `blocked` | `blockedReason` 註明要改哪個檔 |

> 無人監督下賭錯的代價是後面每張票都疊在錯的東西上。

---

## 5. 推 In Review + 進度註解

**dev 一 commit 完就推，不要等 codex 過關。**

```
save_issue({ id: "<TICKET>", state: "<states.inReview.id>" })
```

`state` **一律送 id**，不要送名稱或 type —— `started` 型有 In Progress 與 In Review 兩欄，送 type 會撞。**不要動 labels**（`labels` 參數是整組取代，會把既有標籤清光）。

> 為什麼推在這裡：dev 是最長的階段（實測 20–39 分鐘），而 review + test + rebase 通常十分鐘內。等 codex 過了才推的話，In Progress 這一欄就同時代表「在寫程式」「在被審」「在跑驗證」，看板分不出來。推在這裡，In Progress 精確等於「dev agent 正在寫」。

`$MAIN_REPO/.claude/parallel-loop.json` 的 `progressComments` 為 true 時，在四個階段轉換各加一則**一兩行**的進度註解（進場已由主 Agent 寫過，你負責這三則）：

- **dev 交件** —— 碰了幾個檔、commit hash、一句摘要
- **codex 通過** —— verdict、修過幾個 commit、非阻塞意見原文
- **驗證通過** —— 幾條閘門全綠、幾支 E2E spec、有沒有人工項

進度註解是**即時交接**，不要套七大區塊 —— 那是主 Agent 收尾註解的格式。Markdown 用**真正的換行字元**，不要寫 `\n` 逸出序列。

**每一次 Linear 寫入的成敗都要記進結果檔的 `linearWrites[]`。** 誠實回報失敗 —— 主 Agent 會彙總進 HANDOFF。靜默失敗會讓看板說謊而沒有任何人知道。

---

## 6. codex review 與修正

### 6.1 先搶名額

```bash
bash "$HOME/.claude/skills/parallel-ticket/scripts/stage-lock.sh" acquire review <quotas.review> <TICKET>
```

搶不到會阻塞等待（腳本內建孤兒鎖回收）。**做完一定要釋放**，任何離開路徑都要：

```bash
bash "$HOME/.claude/skills/parallel-ticket/scripts/stage-lock.sh" release review <TICKET>
```

### 6.2 跑 codex

最多 `codex.maxPasses` 輪（設定檔目前是 2）：

```bash
cd "<你的 worktree>" && node "<codex.companionPath>" <codex.reviewArgs>
```

- **必須在 worktree 裡跑** —— codex 的狀態目錄以 cwd 雜湊分桶，跑錯目錄會審到別票的差異。
- 子指令**必須是 `adversarial-review`**（設定檔已經是了，不要自作主張改成 `review`）。`review` 走 native reviewer，只回自由文字、沒有 severity 欄位，阻塞判斷會整段失效。
- `--wait` 是前景模式，會阻塞到結果回來。**不要用背景執行。**

### 6.3 解析結果

真正的審查結果在 **`payload.result`**，形狀是 `{ verdict, summary, findings[], next_steps[] }`。每條 finding 含 `severity`（critical/high/medium/low）、`title`、`body`、`file`、`line_start`、`confidence`、`recommendation`。

先檢查 `payload.parseError`：不是 null 就代表 codex 沒吐出合法結構 → 結果檔寫 `disposition: "blocked"`，把 parseError 與 `payload.rawOutput` 摘要填進 `blockedReason`。`payload.result` 缺席或 `findings` 不是陣列時同樣視為失敗。

> **不要**改去讀 `payload.codex.stdout` 的自由文字自己歸類 severity —— 那等於自己編一份審查結果。

**severity 落在 `codex.blockingSeverities`（critical / high）的是阻塞級**，其餘連同 `next_steps` 壓成文字放進 `nonBlockingFindings`。

> ⚠️ **「codex 挑出一堆 critical」不是執行失敗。** codex 正常回傳、`parseError` 是 null，就代表這一步成功了，把 findings 照實記下來進入修正即可。把它當成失敗直接中止，等於讓 `maxPasses` 形同虛設 —— 2026-08-11 PROJ-81 就是這樣被判死的：codex 挑出 2 條 finding，第 2 條只需要改一行 npm script，票卻直接進了終態。

### 6.4 修正

**只准動 finding 指到的檔案與行段附近。** 不准趁機重構、不准順手改風格、不准動沒被指名的檔案 —— 下一輪 codex 複查看的是整條分支相對 base 的差異，修正範圍膨脹會讓複查失去意義。

認為某條 finding 是誤判就**不要照改**，在結果檔的 `review.nonBlockingFindings` 說明為什麼，保持原樣。

修完跑一次全部 verify 閘門確認沒改壞，commit（`fix(<TICKET>): 修 codex review findings`），回到 6.2 複查。

### 6.5 輪數用完仍有阻塞級 finding

寫結果檔 `disposition: "retry"`，把剩下的 findings 逐條填進 `review.blockingFindingsRemaining`（含 severity / file / title / recommendation）。

**這是 `retry` 不是 `blocked`** —— 退回 Todo 重派後 codex 輪數會重置，而下一輪的 dev 帶著這些 finding 進場。只有 `attempt` 已達 `maxAttemptsPerTicket` 時才是 `blocked`（主 Agent 會判，你照實填 attempt 就好）。

---

## 7. 測試

### 7.1 先搶名額

```bash
bash "$HOME/.claude/skills/parallel-ticket/scripts/stage-lock.sh" acquire test <quotas.test> <TICKET>
```

同樣，任何離開路徑都要 `release`。

### 7.2 `commands.e2e` 有值時

1. 準備本地資料庫（在 worktree 內，各 worktree 的 `.wrangler` 是獨立的）：`commands.dbSetup` 逐條跑。
2. 對 `automated` 類的條件寫 Playwright spec，放 `e2e/`，用 `e2e/helpers/auth.ts` 的登入 helper，**不要每支 spec 自己重刻登入**。
3. 跑 `E2E_PORT=<port> <commands.e2e>`。前端從 `dist` 出去（wrangler 的 `[assets]` 設定），webServer 會先 build 再起 wrangler dev，第一次會慢，這是正常的。
4. **再跑一次全部 verify 閘門**，確認測試檔沒把型別或 lint 弄壞。
5. `static` 類的條件讀程式碼逐條核對，寫清楚是看哪個檔案哪一段判定的。
6. `manual` 類的條件**不要假裝驗過** —— 原封不動列進 `test.manualItems`。
7. 新增的 spec 要 commit（`test(<TICKET>): 補 E2E`）並列進 `test.specsAdded`。

### 7.3 `commands.e2e` 為 null 時（E2E 關閉）

**不要試圖安裝 Playwright、不要新增 `e2e/`、不要動 `package.json`** —— 那是另一張票的工作。

1. 跑全部 verify 閘門，任一條失敗就進 `test.failures`。
2. `static` 類照 7.2 第 5 點。
3. `automated` 類**降級處理**，逐條二選一，不准第三種：
   - 純靠讀程式碼就能確定成立 → 當 static 核對，並在 `summary` 註明「因 E2E 關閉，此條以讀碼判定」。
   - 需要真的跑起來才知道（互動行為、版面、實際回應）→ **列進 `test.manualItems`**，寫清楚人工要怎麼驗（走哪條路徑、看什麼）。
4. `manual` 類同 7.2 第 6 點。`test.specsAdded` 一律留空陣列。

### 7.4 回傳紀律

- **測試通過的條件才算通過。** 沒跑到的、跑失敗的、環境起不來的，一律進 `test.failures`。
- `failures` 每條要寫得讓下一輪的自己能重現：現象、預期、實際、重現步驟。**這段會被原封不動貼進 Linear 當交接資訊，含糊等於白寫。**
- 有 `failures` → `disposition: "retry"`。**有 `manualItems` 但沒有 failures 仍然往下走 rebase** —— 主 Agent 會在 ff 之後把它推成 In Review + `needs-user`，而不是 Done。

> 為什麼有人工項還要往下合併：2026-08-11 那次七張票全部停在「有人工項」而不合併，main 一個 commit 都沒進，七條分支全停在同一個 base 上互相看不見 —— 兩張票改的是不同檔案、git 合得乾乾淨淨，語意上卻互相破壞。**分支擱越久，這種 merge 看不見的衝突越多。**

---

## 8. rebase 與 squash

這是你交件前的最後一步。目標是讓主 Agent 拿到「**單一 commit、已 rebase 到 base 最新**」的乾淨分支，它只需要一個 `git merge --ff-only`。

```bash
git fetch . <baseBranch>:<baseBranch> 2>/dev/null || true
git rebase <baseBranch>
```

- **乾淨通過** → 記 `hadConflict: false`。
- **有衝突** → barrel 檔（`conflictRules.appendOnlyPaths`）的衝突形式應該是兩邊各自 append，機械合併即可。其他檔案若無法明確判斷正確解 → `git rebase --abort`，`disposition: "blocked"`，`conflictFiles` 填清楚，**worktree 保留不刪**。

rebase 之後：

1. **重跑全部 verify 閘門**。任一條失敗 → `disposition: "retry"`，`verifyFailures` 填失敗輸出摘要。
2. **若步驟 1 發生過實際衝突**：
   - `commands.e2e` 有值 → 再跑一次 `E2E_PORT=<port> <commands.e2e>`，記 `e2eRerun: true`。衝突代表這張票跟已合併的票真的動到同一段程式碼，型別檢查攔不住行為層面的互相破壞。
   - `commands.e2e` 為 null → 在 `summary` **明寫**「本票與已合併的票動到同一段程式碼，且無 E2E 覆蓋，行為層面的互相破壞未被驗證」。這句會進 Linear 註解，是這個模式下唯一的風險留痕。
3. squash 成單一 commit：

   ```bash
   git reset --soft $(git merge-base HEAD <baseBranch>)
   git commit -m "feat(<TICKET>): <一句話摘要>"
   ```

4. 記下 `rebasedOnto`（rebase 當下 base 的 HEAD）與 `headCommit`（squash 後的 commit）。

**不要自己 merge 進 base，不要 push，不要刪 worktree 或分支。** 停在這裡。

---

## 9. 結果檔（你的最後一個動作）

寫到 `$MAIN_REPO/.claude/parallel-loop-state/<TICKET>.attempt-<N>.json`（**主 repo**，不是你的 worktree —— 主 Agent 只讀那裡）。

> **沒有這個檔 = 沒做完。** 主 Agent 會當 crash 處理，這一輪的工作就白費了。任何中止路徑都要先寫檔再停。

```json
{
  "ticket": "PROJ-93",
  "attempt": 1,
  "stage": "rebase",
  "disposition": "ready-to-merge",
  "branch": "feat/PROJ-93",
  "worktree": "/abs/path/to/route_planner-wt/PROJ-93",
  "port": 8803,
  "rebasedOnto": "<rebase 當下 base 的 HEAD>",
  "headCommit": "<squash 後的 commit>",
  "hadConflict": false,
  "conflictFiles": [],
  "e2eRerun": false,
  "summary": "2–4 句：做了什麼、為什麼這樣做、現在什麼狀態",
  "filesTouched": ["src/..."],
  "acceptanceCriteria": [
    { "criterion": "條件原文", "howVerifiable": "automated|manual|static",
      "result": "通過|部分通過|未驗", "evidence": "哪條閘門／哪支 spec／讀了哪個檔哪一段" }
  ],
  "decisions": ["與票券原始描述不同的決策及理由"],
  "review": {
    "verdict": "codex 的 verdict",
    "passes": 2,
    "blockingFindingsRemaining": [],
    "nonBlockingFindings": ["原文摘要，會被主 Agent 寫進 Linear 留存"]
  },
  "test": {
    "verifyAllGreen": true,
    "specsAdded": [],
    "failures": [{ "criterion": "", "detail": "", "repro": "" }],
    "manualItems": ["人工要怎麼驗：走哪條路徑、看什麼"]
  },
  "linearWrites": [
    { "op": "state:inReview", "ok": true, "detail": "" },
    { "op": "comment:dev交件", "ok": true, "detail": "" }
  ],
  "landmines": ["本次踩到、值得寫進地雷表的坑"],
  "blockedReason": "",
  "needsBackend": false
}
```

`disposition` 四選一：

| 值 | 什麼時候 |
| --- | --- |
| `ready-to-merge` | 全部通過，已 rebase + squash，等主 Agent ff |
| `retry` | 可以再試（test 失敗、codex 輪數用完、rebase 後 verify 紅） |
| `blocked` | 需要人（規格歧義、rebase 衝突解不了、codex 沒跑起來、要改 exclusivePaths） |
| `apiRequire` | 缺後端 |

**必填**：`ticket`、`attempt`、`stage`、`disposition`、`summary`、`linearWrites`。`ready-to-merge` 時另外必填 `branch`、`rebasedOnto`、`headCommit`。

**寫完之後就停下來，不要關自己的 pane。** 主 Agent 會看到你轉成 idle，讀這個檔，決定下一步。

---

## 10. 被主 Agent 送回來時

### 「main 已前進到 X，重新 rebase」

ff merge 失敗代表 base 在你 rebase 之後又動了。只做第 8 步：重新 rebase、重跑全部 verify、重新 squash、**更新結果檔**（`rebasedOnto`、`headCommit`、必要時 `hadConflict`）。

**不要重跑 dev / review / test。** 那些的結論沒有失效。

### 「結果檔缺欄位／無法解析」

只重寫結果檔，**不要重跑任何階段**。素材都還在你的 context 與 git 歷史裡。

---

## 11. 你不准做的事

1. **不 merge 進 base、不 push、不刪自己的 worktree 或分支。**
2. **不推終態**（Done / Blocked / API Require）、**不動 labels**。
3. **不寫紀錄檔**（`HANDOFF.md`、`parallel-loop-log.md`、`parallel-loop-index.md`、`goal-loop-landmines.md`）—— 連你 worktree 裡的副本也不行。踩到的坑寫進結果檔的 `landmines[]`，主 Agent 收工時彙總。
4. **不動 `protectedPaths`、不動別票的 worktree、不用預設 port。**
5. **不把「沒驗」寫成「通過」。** 結果檔會被原封不動翻成 Linear 上的實作紀錄註解 —— 寫錯比留白傷害大。
