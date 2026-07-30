# The forked Telegram plugin

The fleet's Telegram channel is a **fork** of `claude-plugins-official/telegram` 0.0.6 — specifically its `server.ts`. That single file *is* the fork; everything else matches upstream.

Canonical source: **`~/agents/shared/telegram-fork/`**
- `server.ts` — the fork (~1618 lines)
- `server.ts.official-0.0.6` — upstream baseline for diffing (~1575 lines)
- `package.json` — upstream 0.0.6 dependency set, plus the mermaid-cli devDependency (see below)
- `fork-vs-official.diff` — unified diff, official → fork
- `README.md`

Before this directory existed (preserved 2026-07-22) the fork lived only inside running agents' plugin caches — untracked, unbacked-up, a single point of failure. **Keep it backed up.**

## What the fork changes

Only two things, ~51 lines:

1. **The `act:<cmd>` callback handler** — makes the Stop-hook context popup's inline buttons work (🧹 清空對話 → `/clear`, 🔄 重啟), by running `scripts/tg/<cmd>.sh`. Official 0.0.6 only handles `perm:*` callbacks, so those buttons are dead on it.
2. **Lazy-loading of heavy deps** — `puppeteer-core`, `markdown-it` and `telegramify-markdown` are `import()`-ed on first use instead of at module top level. Top-level imports pushed cold MCP startup past Claude Code's readiness window (~5–7 s), so `bot.pid` never appeared on a fresh boot (the `telegram_fork_coldstart_timeout` issue).

**NOT fork additions** — these are already in official 0.0.6: `discoverCommands()` (turns `tg/*.sh` into `/commands`) and puppeteer table/mermaid **rendering**. A plain-official plugin has table rendering; it just lacks the `act:` buttons and boots slower.

The fork is fully env-driven: `AGENT_NAME` is derived from `TELEGRAM_STATE_DIR`, and `SHARED_TG_DIR` / `AGENT_TG_DIR` from `homedir()`. The same `server.ts` works for every agent, unmodified.

## ⚠ Version labels lie — always diff before trusting a copy

`0.0.6` is a label, not a guarantee. Observed on the macOS host, 2026-07-30, in one directory:

| Field | Value |
|---|---|
| `.claude-plugin/plugin.json` → `version` | `0.0.6` |
| `package.json` → `version` | `0.0.1` |
| `server.ts` | 1038 lines, no `discoverCommands()`, no puppeteer |
| the real official 0.0.6 baseline | 1575 lines |

So a local marketplace checkout can be labelled 0.0.6 while being a far older build. **First step of any install or repair:**

```bash
diff <marketplace>/server.ts ~/agents/shared/telegram-fork/server.ts.official-0.0.6
```

If it doesn't match, do not use that checkout as a base — rebuild from `shared/telegram-fork/` per below.

## Where the plugin must live

`claude` reads plugins from **`CLAUDE_CONFIG_DIR/plugins`** = `~/agents/<name>/.claude/plugins`.

The most common fleet failure is putting it in the STATE dir (`~/.claude-agents/<name>/plugins/cache`, sometimes double-nested). Result: the telegram MCP can't load, no `bot.pid`, DMs silently dropped. The Windows `launch-agent.sh` still does this; the macOS one was fixed.

## Hand-installing the fork (fresh machine, or when the marketplace copy is unusable)

On macOS this is scripted: `bash ~/agents/scripts/seed-telegram-plugin.sh <agent> [--force]`. It prefers cloning a peer agent that already works (node_modules come along), else builds from scratch, then always overwrites `server.ts` from the canonical fork. What it does, for porting to other hosts:

**1. Create the plugin dir** at the path you will record as `installPath`:

```
~/agents/<name>/.claude/plugins/cache/claude-plugins-official/telegram/0.0.6/
```

**2. Populate the non-code files** from a marketplace checkout — `.claude-plugin/`, `.mcp.json`, `.npmrc`, `ACCESS.md`, `LICENSE`, `README.md`, `skills/`. (Even a stale checkout is fine for these.)

**3. Write `package.json`** — copy `shared/telegram-fork/package.json`. The dependency set is not guessable from the fork's static imports alone, because three deps are loaded via `import()` and one is invoked as a binary:

```json
"dependencies": {
  "@modelcontextprotocol/sdk": "^1.0.0",
  "grammy": "^1.21.0",
  "zod": "^3.23.8",
  "markdown-it": "^14.1.0",
  "telegramify-markdown": "^1.2.2",
  "puppeteer-core": "^23.0.0"
},
"devDependencies": {
  "@mermaid-js/mermaid-cli": "^11.16.0"
}
```

⚠ **`@mermaid-js/mermaid-cli` appears in no import statement.** `renderMermaid()` shells out to `MMDC_BIN` = `<plugin>/node_modules/.bin/mmdc`, and when it's missing the function just returns `null` — Mermaid diagrams silently degrade to a code fence with no error anywhere. Install it with `PUPPETEER_SKIP_DOWNLOAD=true` (the plugin passes its own `PUPPETEER_EXECUTABLE_PATH`).

**4. `bun install`** in that directory.

**5. Copy the fork's `server.ts`** over whatever is there.

**6. Register the plugin** in `~/agents/<name>/.claude/plugins/installed_plugins.json`:

```json
{"version": 2, "plugins": {"telegram@claude-plugins-official": [
  {"scope": "user",
   "installPath": "<HOME>/agents/<name>/.claude/plugins/cache/claude-plugins-official/telegram/0.0.6",
   "version": "0.0.6",
   "installedAt": "…", "lastUpdated": "…"}]}}
```

**7. ⚠ Register the marketplace** in `~/agents/<name>/.claude/plugins/known_marketplaces.json` — **including `installLocation`**:

```json
{"claude-plugins-official": {
  "source": {"source": "github", "repo": "anthropics/claude-plugins-official"},
  "installLocation": "<HOME>/.claude/plugins/marketplaces/claude-plugins-official",
  "lastUpdated": "…"}}
```

**Without `installLocation` the marketplace cannot be resolved, so the plugin is skipped entirely — with no error, warning or log line anywhere.** The symptoms are maximally misleading: `claude`'s command line correctly shows `--channels plugin:telegram@claude-plugins-official`, the MCP command from `.mcp.json` runs perfectly when you invoke it by hand, and yet no bun child is ever spawned and `bot.pid` never appears. Cost about an hour on 2026-07-30.

This step is easy to miss because it is normally invisible: when *claude* installs a plugin it writes this file itself. It only bites when you hand-seed, which is exactly what a cold restore requires.

**8. Also set, in the agent's `settings.json`:** `enabledPlugins["telegram@claude-plugins-official"] = true` and `extraKnownMarketplaces["claude-plugins-official"]`. (`_template` and `new-agent.sh` already do this.) These are necessary but **not sufficient** — they do not replace step 7.

**9. Restart the agent** and verify:

```bash
ls ~/.claude-agents/<name>/channels/telegram/bot.pid    # must appear within ~30 s
ps -eww -o pid,command | grep server.ts                 # bun server.ts child alive
```

## Repairing an existing agent

If the agent already has a working 0.0.6 dir with `node_modules`, `server.ts` alone is enough — copy it from `shared/telegram-fork/` or from a working peer agent, then restart to reload. Only a fresh machine needs the full sequence above.

## Diagnosing "agent is deaf to Telegram"

In order:

1. `bot.pid` present? If yes, the poller is up — the problem is access control, not the plugin. Check `access.json` (`dmPolicy`, `allowFrom` as **strings**, `groups` as an **object**).
2. Is there a `bun server.ts` child of the agent's `claude` process? No child ⇒ claude never launched the MCP ⇒ **suspect `known_marketplaces.json` / `installLocation` first**, before anything else.
3. Does `claude`'s command line include `--channels plugin:telegram@…`? If not, `has_telegram()` didn't see `.env` — check `TELEGRAM_STATE_DIR` and that the file exists.
4. Does the plugin dir match `installPath` in `installed_plugins.json`? Mismatch ⇒ the wrong-dir failure.
5. Run the `.mcp.json` command by hand to rule out the plugin code itself:
   ```bash
   TELEGRAM_STATE_DIR=<state> bun run --cwd <plugin-dir> --shell=bun --silent start < /dev/null
   ```
   Expect it to print `telegram channel: shutting down` and exit — that is **success**, not an error. MCP speaks stdio, so with no peer on stdin it shuts down immediately. This test proves the command and deps work; it says nothing about whether claude will launch it.
