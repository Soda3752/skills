---
name: gitnexus-init
description: "Initialize GitNexus on the current project from zero — register the MCP server, build the first index, verify it loads, and (optionally) wire up an Obsidian vault skeleton for codebase knowledge sync. Use this whenever the user wants to set up GitNexus for a brand-new project, onboard an existing repo to GitNexus, or stand up the full GitNexus + Obsidian knowledge stack. Triggers: \"初始化 gitnexus\", \"建立 gitnexus 索引\", \"幫這個專案接 gitnexus\", \"setup gitnexus\", \"set up gitnexus for this project\", \"index this repo with gitnexus\", \"onboard gitnexus\", \"為新專案建好 gitnexus\". Run the SOP as written — do not re-ask which package, which CLI flags, or where to put the vault folder. The decision points that DO get asked: (1) whether to enable embeddings; (2) whether to also set up Obsidian integration; (3) overwrite confirmations when state already exists. Everything else is mechanical."
---

# gitnexus-init

Stand up GitNexus on the current project: register MCP, build the first index, verify, and (if requested) bootstrap an Obsidian vault skeleton for codebase knowledge sync.

This is a **mechanical SOP**. Do not invent extra steps, do not negotiate defaults. The three decision points that DO get asked are listed in **§ Ask the user** below — everything else just runs.

## What this gives the user

After running this skill on a project, they have:

- ✅ `gitnexus` registered as an MCP server in Claude Code (idempotent — won't duplicate)
- ✅ `.gitnexus/` directory in the project root containing the knowledge graph index
- ✅ Project registered in `~/.gitnexus/registry.json` (verifiable via `npx gitnexus list`)
- ✅ Auto-generated GitNexus section in `CLAUDE.md` / `AGENTS.md` (analyze does this)
- ✅ Verified working: `mcp__gitnexus__list_repos` returns the repo without errors
- ✅ (Optional) `vault/10_Codebases/<repo>/` skeleton with `_Overview.md`, `Processes/`, `Symbols/`, `Impact-Reports/`

## Pre-flight checks

Run these before doing anything mutating. If any fail, stop and report — don't try to "fix" them implicitly.

| Check | How | If fails |
|-------|-----|----------|
| Inside a git repo | `git rev-parse --show-toplevel` | Stop — GitNexus refuses to index non-git directories |
| Node.js available | `node --version` | Stop — ask user to install Node |
| cwd is project root | Compare `pwd` to `git rev-parse --show-toplevel` | If not, switch to git root before continuing |
| GitNexus not already initialized | Check if `.gitnexus/` exists AND `npx gitnexus list` includes this path | If both true → tell user it's already set up, ask whether to skip or `--force` re-index |

Capture the **absolute path** of the project root — used in vault skeleton step.

## Ask the user (the only three questions)

Use `AskUserQuestion`. Do **not** ask anything else. Bake all other defaults.

### Q1: Enable semantic search (embeddings)?

```
question: 要啟用語意搜尋（embeddings）嗎？啟用後可以用中文 / 模糊概念查詢。
options:
  - 啟用（推薦，需 OPENAI_API_KEY）  → flag = --embeddings
  - 跳過（之後可隨時補）             → no flag
```

If user picks 啟用 but `OPENAI_API_KEY` is not set in env, surface this clearly before running analyze and let them either set it now or fall back to no embeddings. Do **not** run `analyze --embeddings` without the key — it will fail mid-index.

### Q2: 同時設定 Obsidian 整合骨架？

```
question: 要同時建立 Obsidian vault 骨架（同步 codebase 知識用）嗎？
options:
  - 是，含完整骨架               → 觸發 obsidian-init skill + 建立 codebases 子結構
  - 是，但 vault 已存在          → 跳過 obsidian-init，只建 codebases 子結構
  - 否                          → 略過所有 Obsidian 步驟
```

### Q3 (conditional): 已存在的 obsidian server 處理方式

Only ask if user picked Obsidian integration AND `.mcp.json` already has an `obsidian` server entry pointing somewhere different. Mirror the question from `obsidian-init` skill.

---

## Step 1 — Register the gitnexus MCP server (user-scope)

Check first, register only if missing. Never duplicate.

```bash
# Check current state
claude mcp list | grep -E "^gitnexus\s" || echo "NOT_REGISTERED"
```

If output shows `NOT_REGISTERED`:

```bash
claude mcp add gitnexus -- npx -y gitnexus@latest mcp
```

If already registered, **do not re-register and do not "upgrade"** — the user may have a pinned version on purpose. Just note it in the final report.

> ⚠️ This registers gitnexus at **user scope** (available to all projects), which is the right default — GitNexus's own MCP server reads `~/.gitnexus/registry.json` to multiplex across projects, so one user-scope server serves them all. Do not register at project scope.

## Step 2 — Build the first index

Run from the project root. Use the flag from Q1.

```bash
# With embeddings
npx gitnexus analyze --embeddings

# Without embeddings
npx gitnexus analyze
```

Stream the output so the user can see progress. Indexing time scales with file count — give them a rough heads-up before running:

| Files | Expected time (approx, no embeddings) |
|-------|----------------------------------------|
| <100 | <30s |
| 100-500 | 30s–2min |
| 500-2000 | 2–8min |
| >2000 | >8min, may want to grab coffee |

Embeddings roughly double these numbers and consume API credits.

If `analyze` exits non-zero, **stop**. Capture the error and report — common failures:

| Error pattern | Likely cause |
|---------------|--------------|
| `Not inside a git repository` | Pre-flight should have caught this; double-check cwd |
| `OPENAI_API_KEY` not set | User picked embeddings but no key; restart Q1 |
| Out of memory | Project too large for default heap; try `NODE_OPTIONS=--max-old-space-size=8192` |
| Tree-sitter parse failure on N files | Usually fine; analyze continues; just note in report |

## Step 3 — Verify the index loaded

Two checks, both must pass:

```bash
npx gitnexus list
```

Expect to see the project path with non-zero `nodes` and `edges`. If `nodes: 0`, the parser hit nothing — investigate (probably an unsupported language).

Then via MCP (this catches "MCP server hasn't reloaded the registry yet" issues):

```javascript
mcp__gitnexus__list_repos()
```

Expect the project to appear. **If it does not appear**, the MCP server has cached state from before the new repo was added. Tell the user to restart Claude Code (or run `/mcp` to reconnect) before continuing — do **not** silently retry.

## Step 4 — Obsidian skeleton (only if Q2 said yes)

### 4a. If Q2 = "完整骨架" and no `vault/` exists

Delegate to the `obsidian-init` skill — it handles vault creation, `.gitignore`, and `.mcp.json` registration. After it returns, continue to 4b.

### 4b. Build the codebases sub-structure

Inside the vault, create:

```
vault/
├── 10_Codebases/
│   └── <repo-name>/
│       ├── _Overview.md          ← seeded with frontmatter + gitnexus marker
│       ├── Processes/            ← future: one note per execution flow
│       ├── Symbols/              ← future: 360-degree symbol notes
│       └── Impact-Reports/       ← future: dated impact analysis snapshots
```

Use `<repo-name>` exactly as it appears in `npx gitnexus list` (typically the directory basename).

`_Overview.md` content (write via `mcp__obsidian__write_note` if obsidian MCP is reachable, else `Write` tool to direct path):

```markdown
---
type: codebase-overview
repo: <repo-name>
indexed_at: <ISO timestamp from list_repos>
last_synced:
tags: [code/overview]
---
# <repo-name>

> GitNexus index entry point. Run `/sync-codebase <repo-name>` to populate Processes/ and Symbols/.

## Stats
<!-- gitnexus:context -->

## Functional areas
<!-- gitnexus:clusters -->

## Execution flows
<!-- gitnexus:processes -->
```

Leave the markers as plain HTML comments — don't fill them in during init. They're hooks for a future `/sync-codebase` slash command (out of scope for this skill).

> Why empty markers and not full sync? **Init is mechanical and fast.** Pulling all 89 processes into individual notes is bulk content generation — that belongs in a separate `/sync-codebase` command the user can run on demand. Keeping init lean means re-running it is cheap.

## Step 5 — Final report

Output a concise summary, in this order:

1. **What was created**: list each artifact (MCP registration status, index node/edge counts, vault path if applicable).
2. **Verification result**: `list_repos` confirmed entry, `node count > 0`.
3. **Restart needed?**: If you registered a new MCP server in Step 1, the user **must restart Claude Code** for the gitnexus MCP tools to appear. Say this explicitly.
4. **Next steps**: 2-3 bullet points pointing to the existing skills:
   - Explore: see `gitnexus-exploring`
   - Impact analysis before edits: see `gitnexus-impact-analysis`
   - Refactor safely: see `gitnexus-refactoring`
5. **Skipped items** (if any): if user said no to embeddings or Obsidian, mention how to add them later (`npx gitnexus analyze --embeddings` / re-run this skill with Q2 = yes).

## Idempotency

Running this skill twice should be safe:

| State | Behavior |
|-------|----------|
| MCP already registered | Skip registration, note it |
| `.gitnexus/` already exists | Ask before re-indexing; offer `--force` or skip |
| `vault/10_Codebases/<repo>/` already exists | Skip creation, leave existing notes alone |
| `_Overview.md` already exists with content | Do not overwrite — append a comment if the gitnexus markers are missing, otherwise leave alone |

## Things to avoid

- **Do not** run `npx gitnexus clean` as part of init. Clean is a recovery action, not a setup action. If pre-flight detects a corrupt index, surface it and let the user choose — don't silently nuke their state.
- **Do not** try to "fix" a stale index with `--force`. Staleness is a content concern, not an init concern.
- **Do not** populate the Obsidian Processes/ and Symbols/ folders with actual content — that's `/sync-codebase`'s job. Init only creates the empty skeleton.
- **Do not** commit anything (`.gitnexus/`, `.mcp.json`, vault, etc.). The user owns commit decisions. `analyze` already adds a `.gitnexus/` line to `.gitignore` if needed; don't second-guess that.
- **Do not** ask the user to choose between mcpvault vs cyanheads vs MarkusPfundstein for Obsidian. `obsidian-init` already made that call (mcpvault). Honor it.
- **Do not** run this skill on a directory that's not a git repo or not the project root. Pre-flight should have stopped you.

## Cross-references

| Concern | Skill |
|---------|-------|
| Recovering from a corrupt index | (no skill — manual: `npx gitnexus clean --force && npx gitnexus analyze`) |
| Index commands beyond init (status, wiki, group) | `gitnexus-cli` |
| Tool / resource reference | `gitnexus-guide` |
| First exploration after init | `gitnexus-exploring` |
| Obsidian vault + MCP setup (delegated) | `obsidian-init` |
