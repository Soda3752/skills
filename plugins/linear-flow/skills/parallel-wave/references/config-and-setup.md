# parallelWave 設定

放在專案的 `.claude/linear-workflow.json`，與 `linear-goal-loop` 讀的 `goalLoop` 區塊平行共存。**不要新增獨立設定檔**——票券工作流的 team、狀態 id、註解語言等值已經在那個檔裡，分家會造成兩份會不同步的真相。

```json
{
  "team": "…",
  "states": { "…": "…" },

  "parallelWave": {
    "worktreeRoot": "/absolute/path/to/<repo>-worktrees",
    "baseBranch": "main",
    "warmupCommand": "JAVA_HOME=\"…\" ./gradlew :app:compileDebugKotlin",
    "verifyCommands": [
      "JAVA_HOME=\"…\" ./gradlew :app:compileDebugKotlin",
      "JAVA_HOME=\"…\" ./gradlew :app:testDebugUnitTest"
    ],
    "testResultsGlob": "app/build/test-results/testDebugUnitTest/*.xml",
    "untrackedSetupFiles": ["keystore.properties", "app/google-services.json"],
    "specDocsRoot": "vault/games",
    "commitConvention": "中文 conventional commits",
    "sharedFileHotspots": [
      "app/src/main/kotlin/**/di/AppModule.kt",
      "gradle/libs.versions.toml"
    ],
    "activeProjectId": "…"
  }
}
```

## 欄位

| 欄位 | 用途 | 缺漏時 |
| --- | --- | --- |
| `worktreeRoot` | worktree 放哪 | 沿用 repo 既有慣例（找找有沒有 `*-worktrees` 目錄或既有 workflow 腳本寫死的路徑）；否則預設 `<repo>-worktrees` 放在 repo 同層 |
| `baseBranch` | 合併目標 | `git symbolic-ref refs/remotes/origin/HEAD` 或當前分支 |
| `warmupCommand` | 派工前暖快取 | 用 `verifyCommands` 第一項 |
| `verifyCommands` | 每個 agent 與整合後都要跑 | 從 repo 推斷（`gradlew` / `package.json` scripts / `Makefile`），**推斷完跟使用者確認一次** |
| `testResultsGlob` | 確認測試真的執行 | 沒有就在 agent 指令改用該測試框架的計數輸出；仍要求 agent 貼出數量 |
| `untrackedSetupFiles` | worktree 需補的 gitignored 檔 | 掃 `.gitignore` 找 `*.properties` / `*.json` / `.env*` 之類，**跟使用者確認**——猜錯會複製到不該複製的東西 |
| `specDocsRoot` | 規格文件位置 | 問使用者；沒有就略過 |
| `commitConvention` | commit 訊息風格 | 讀 `git log --oneline -20` 推斷 |
| `sharedFileHotspots` | 已知衝突熱點 | 每波實地掃描（見 SKILL.md 第 1 步）；掃到的可回寫這裡 |
| `activeProjectId` | 同一 team 有多專案時的過濾 | `linear-workflow.json` 的 `conventions.activeProject` 常已記錄 |

## 缺漏時的處理

**不要因為沒設定就停工。** 順序是：

1. 能從 repo 推斷的就推斷（base 分支、建置指令、commit 風格）
2. 猜錯代價高的（`untrackedSetupFiles`、`verifyCommands`）用一次 AskUserQuestion 把不確定的一次問完，附上你的推斷當推薦選項
3. 收工時提議把 `parallelWave` 區塊寫進設定檔，下次免問

## 環境變數

建置需要特定環境變數（`JAVA_HOME`、`NODE_OPTIONS`、`PATH` 前綴）時，**直接寫進 `warmupCommand` / `verifyCommands` 字串裡**，不要另外開 `env` 欄位。理由：agent 是複製整條指令去跑，變數寫在指令裡就不會漏；分開放兩處，agent 很容易只複製指令本身。

## 與其他 skill 的分工

| skill | 何時用 | 需要 |
| --- | --- | --- |
| `parallel-wave`（本 skill） | 一批獨立票同時做，有人在旁邊看每一步 | 無外部依賴 |
| `parallel-loop` | 無人監督連續清空看板，要可見可中斷的 pane | `HERDR_ENV=1` |
| `linear-goal-loop` | 無人監督但串行，一次一張做到底 | 無 |
| `check-linear-status` | 只想知道現況該做哪張，不動手 | 無（唯讀） |

盤點階段若使用者只是想知道「接下來做哪張」而非真的要動手，改用 `check-linear-status`，別直接開 worktree。
