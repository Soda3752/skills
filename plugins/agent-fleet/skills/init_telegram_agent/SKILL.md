---
name: init_telegram_agent
description: Set up, provision and operate a fleet of Claude Code agents that talk over Telegram. Use when creating a new Telegram agent/bot, standing the fleet up on a new machine or a new OS, repairing an agent that has gone deaf to Telegram (no bot.pid), or restarting/stopping one. Also the reference for how such a fleet is built — CONFIG/STATE split, pane registry, the forked telegram plugin, inter-agent comms, lifecycle rules. Triggers: 建立 telegram agent, 新增 agent, 開一隻新 bot, agent 收不到 Telegram, 重啟 agent, fleet 移植到新電腦, init telegram agent, provision agent, fleet architecture.
---

# Claude Agent Fleet — Architecture & Key Techniques

A fleet of Claude Code agents living in one terminal-multiplexer session (`claude-agents`). Each agent = one window/pane, its own `CLAUDE_CONFIG_DIR`, and (except service agents) its own Telegram bot. Agents talk to each other via `agent-send.sh` (send-keys), and to the user via Telegram.

> **Scope.** This is a design + operations reference, not a turnkey installer. It documents a working pattern and the traps in it; the `~/agents/scripts/*` tooling it refers to is your own to write (or to carry over from an existing fleet). Read it as a blueprint, not as a package you install and run.

**This file holds only what is true on every host.** Anything machine-specific — agent roster, tool paths, version pins, multiplexer choice, platform gotchas — belongs in a per-host file under `hosts/`. Copy `hosts/EXAMPLE-host.md` per machine.

⚠ **Keep your real `hosts/*.md` out of version control.** A filled-in host file is a map of a machine that runs agents with `--dangerously-skip-permissions`: exact tool paths, what each agent is wired to, which bots exist. That belongs on the machine, not in a public repo. Only `EXAMPLE-host.md` ships here.

Deep-dive references, read on demand:

| Topic | File |
|---|---|
| The forked Telegram plugin — hand-install, repair, why version labels lie | `references/telegram-plugin.md` |
| Porting the fleet to a new OS — full delta checklist | `references/porting.md` |
| Per-host facts template | `hosts/EXAMPLE-host.md` |

---

## 1. Directory layout — CONFIG dir vs STATE dir (the central distinction)

Get this wrong and nothing works. Two separate trees, deliberately:

```
~/agents/                                ← CONFIG (belongs in version control)
├── _template/                           ← new-agent.sh clone source
├── <name>/
│   ├── CLAUDE.md                        ← role + @imports of shared rules
│   └── .claude/                         ← == CLAUDE_CONFIG_DIR for this agent
│       ├── settings.json                ← hooks / env / enabledPlugins
│       ├── skills/                      ← per-agent skills
│       ├── plugins/                     ← ★ where claude READS plugins
│       └── .credentials.json            ← per-agent OAuth (Windows only; macOS uses Keychain)
├── shared/rules/*.md                    ← @imported by every CLAUDE.md
├── shared/telegram-fork/                ← canonical fork source (see references/)
├── shared/stop-context.js, statusline.js
├── scripts/                             ← management scripts (§8)
└── .trash/YYYYMMDD/                     ← soft-delete (rm is banned, see security.md)

~/.claude-agents/                        ← STATE (runtime, never in version control)
├── pane-registry                        ← name<TAB>pane_id map (agent identity)
└── <name>/
    ├── channels/telegram/{.env, access.json, bot.pid, inbox/}
    ├── plugins/                         ← ⚠ claude does NOT read from here
    ├── claude.running                   ← touched while claude is foreground
    └── restart-requested                ← flag → launch-agent.sh relaunches on exit
```

- **`CLAUDE_CONFIG_DIR`** = `~/agents/<name>/.claude` (set by `launch-agent.sh`). Plugins, skills and credentials are read from **here**.
- **STATE dir** = `~/.claude-agents/<name>` (`AGENTS_STATE_HOME`). Telegram channel, markers, registry.
- The classic failure is putting the plugin cache in the STATE dir — see `references/telegram-plugin.md`.

## 2. Session & window model

- One session named `claude-agents`, **one window per agent** (window name == agent name; pane title set to match so the picker is self-describing).
- Window indices shift after restarts — always resolve an agent by **name**, never by index.
- `automatic-rename off` globally, or the running program overwrites window names.
- The multiplexer's default shell must be forced to a **login shell of the right bash**; see the host file, this is where platform differences bite hardest.

## 3. Agent identity — the pane registry

Agent→pane identity lives in an external registry at `~/.claude-agents/pane-registry` (`name<TAB>pane_id`), managed by `find_pane()` / `registry_set()` / `registry_clear()` in `scripts/lib/common.sh`.

Do **not** derive identity from:
- `pane_title` / `pane_current_command` — Claude Code rewrites both.
- multiplexer `@user-options` — psmux 3.3.4 stores them globally (last write wins). Real tmux supports per-pane options, but the registry is kept on both hosts so one mental model and one set of scripts cover them.

`start.sh` / `new-agent.sh` call `registry_set` at assign time; `start.sh` calls `registry_clear` on a fresh boot. **If you ever recreate a window by hand, `registry_set` the new pane** — otherwise `agent-send` and `find_pane` fail with "no pane found". (The Telegram poller doesn't use the registry; inter-agent messaging does.)

## 4. Is an agent alive? Use the marker, not the screen

`launch-agent.sh` touches `$STATE_DIR/claude.running` before exec'ing claude and clears it via an `EXIT` trap. `pane_is_alive()` in `common.sh` reads that marker. **This is the canonical liveness test.**

It matters because "pane has a process" is not the question: after `/exit` the pane falls back to an idle login shell (so the pane survives for `start-agent.sh` to recycle), and that is *down*, not *up*.

**Do not screen-scrape for a shell prompt.** The Windows fleet detected idle-bash by looking for a last line that is a lone `$`; that silently never matches on macOS, whose default prompt is `<host>:<dir> <user>$`, so restarts died with "TUI still in %N after /exit" while the pane was in fact already idle. Fixed 2026-07-30 by delegating to `pane_is_alive`.

Known gap (both hosts): `SIGKILL` or `kill-pane` bypasses the trap and leaves the marker stale. Clear it by hand before restarting.

## 5. Per-agent Telegram channel

Files in `~/.claude-agents/<name>/channels/telegram/`:

- `.env` — `TELEGRAM_BOT_TOKEN=...` (chmod 600). Wired in via the `TELEGRAM_STATE_DIR` env in the agent's `settings.json`.
- `access.json` — `dmPolicy` (`allowlist`|`pairing`|`disabled`), `allowFrom` (user-id **strings**), `groups` (an **object** keyed by chat_id → `{requireMention, allowFrom}`), `pending`, optional `ackReaction`.
- `bot.pid` — the bun MCP poller's PID, and the only alive signal. **No `bot.pid` = poller down = agent deaf to Telegram.**
- `inbox/` — attachment downloads.

**Edit `access.json` directly — never via the `/telegram:access` skill**, which hardcodes a global path (`~/.claude/channels/telegram/access.json`) and ignores per-agent `TELEGRAM_STATE_DIR`.

**Group mode:** add the group chat_id to `groups`. `requireMention:true` = only responds when @mentioned. Gotcha: a fresh bot has Group Privacy ON; supergroups (`-100…`) deliver @mentions fine but **basic groups (`-5xxxxxxxxx`) do not** → disable Group Privacy in BotFather (`/setprivacy` → Disable), then remove and re-add the bot. Sending *to* a group is unaffected.

The fleet runs a **forked** telegram plugin, not the official one — see `references/telegram-plugin.md`.

## 6. Agent launch (`launch-agent.sh`)

Internal wrapper run inside each pane (by `start.sh` / `new-agent.sh` / `start-agent.sh`). Never run it directly. It:

1. Sets `CLAUDE_CONFIG_DIR` = `~/agents/<name>/.claude`.
2. Sets `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` — **required**. The multiplexer server is typically spawned from inside a claude session, so every pane inherits `CLAUDE_CODE_CHILD_SESSION=1`, which disables transcript saving. `stop-context.js` derives context usage from the transcript, so without this the popup reports `0k / 模型:?`.
3. Optionally seeds a plugin cache (host-dependent — see the host file).
4. Detects `handover.md` → renames it to `handover.consumed.*` and schedules a kickoff inject after 12 s.
5. `exec claude --dangerously-skip-permissions [--channels plugin:telegram@claude-plugins-official]` (the `--channels` flag only when the agent has a `.env`).
6. Maintains the `claude.running` marker; on exit, honors `restart-requested` by re-exec'ing itself, else falls back to an idle login shell so the pane survives.

Per-agent `settings.json` carries: `TELEGRAM_STATE_DIR` env, Stop/SessionStart/SessionEnd hooks, `statusLine`, `enabledPlugins["telegram@claude-plugins-official"]`, `extraKnownMarketplaces`.

## 7. Inter-agent comms & lifecycle

- **Messaging:** `~/agents/scripts/agent-send.sh <target> "<msg>"` — send-keys into the target's pane (literal text + two Enters). Resolves the pane via the registry.
- **Lifecycle (stop/restart/kill):** orchestrators **delegate to `controller`**, never act directly:
  `agent-send.sh controller "請重啟 <name>"` → controller acts → replies `agent-send.sh master "controller: 已重啟 <name> ✅"`.
- **Per-instance ack (`agent-lifecycle-protect`):** EVERY stop/restart needs explicit, per-instance user ack. A prior ack does not cover the next one. No auto-restart — a 5-minute health-check cron was removed 2026-05-18 for violating this.
- **Long-context handover:** write `~/agents/<name>/handover.md` (done / pending / trigger) → tell the user → after ack, have *another* agent drive the restart via controller (never restart yourself). The new instance reads `handover.consumed.*` and continues. Which agent drives depends on the roster — see the host file.

## 8. Key scripts (`~/agents/scripts/`)

| Script | Purpose |
|---|---|
| `start.sh [restart]` | Boot the whole fleet (one window per `AGENT_LIST`+`SERVICE_LIST` entry). `restart` kills and recreates the session. |
| `launch-agent.sh <name>` | Internal per-pane wrapper (§6). Don't run directly. |
| `new-agent.sh <name> <token\|--no-telegram> [desc] [--owner <id>]` | Provision a new agent (§9). |
| `seed-telegram-plugin.sh <name> [--force]` | Install the forked telegram plugin into an agent's CONFIG dir. Called by `new-agent.sh`; also the repair tool. |
| `start-agent.sh <name>` / `stop.sh [name]` | Restart / stop a single agent in its existing pane. |
| `agent-send.sh <target> "<msg>"` | Inter-agent messaging via the registry. |
| `status.sh` / `gather-panes.sh` | Fleet state / capture panes. |
| `lib/common.sh` | Registry helpers, `pane_is_alive`, path helpers, `AGENTS_HOME`/`AGENTS_STATE_HOME`, PATH normalization. |
| `tg/restart.sh`, `tg/clean.sh` | Self-restart / clear, surfaced as bot `/commands` and `act:` buttons. |
| `tg-notify.sh`, `tg-notify-clear.sh` | Push a Telegram message via an agent's bot (SessionStart/SessionEnd → 🟢上線 / 👋離線). Takes a **percent-encoded** argument. |
| `telegram-auto-react.sh` | Hook: auto-react 👀 on inbound. |

## 9. Provisioning a new agent

1. Get a bot token from BotFather (plus the target GitHub repo, for guide agents).
2. `bash ~/agents/scripts/new-agent.sh <name> <bot-token> --owner <tg-user-id>` — clones `_template`, materializes the Telegram channel (owner pre-allowlisted), seeds the forked plugin, creates the window, launches. Use `--no-telegram` for service agents.
3. Overlay specializations the template lacks (role `CLAUDE.md`, skills, …).
4. Add `<name>` to `AGENT_LIST` in `start.sh` so it survives a reboot.
5. Walk the **first-run wizard** (below) in the agent's pane.
6. Git-autonomy is a **per-agent privilege** — never copy it implicitly; require an explicit user waiver.

### First-run wizard — every fresh `CLAUDE_CONFIG_DIR` hits it

A brand-new agent is *not* at a prompt after launch; it is sitting in Claude Code's onboarding, invisibly, until someone answers. Expect roughly this sequence:

1. Theme picker — Enter.
2. Login method → OAuth (host-dependent: on macOS the Keychain credential is shared, so only the very first agent on the machine actually logs in).
3. Security notes — Enter.
4. "Is this a project you trust?" → **Yes**.
5. "Allow external CLAUDE.md file imports?" → **Yes** (this is `shared/rules/*.md`; saying no silently strips every shared rule).
6. "Try the new fullscreen renderer?" → **Not now**. ⚠ It uses the alternate screen, which makes `capture-pane` return nothing — and pane capture is how `gather-panes.sh`, `stop.sh` and any manual diagnosis read an agent. Choosing "Yes" quietly blinds your tooling.

Drive it from outside with `send-keys` if you like; `Down` then `C-m` picks option 2.

## 10. Hooks & shared infra

- **`shared/stop-context.js`** (Stop hook): after each turn, posts a context-usage popup (bar + tokens + 🧹清空對話 / 🔄重啟 buttons) to the agent's chats. Reads the **transcript's** last assistant `message.usage`, so it needs transcript persistence (§6 step 2). Add `--groups` to also post to `access.json` groups (opt-in).
- **`shared/statusline.js`**: pane status line. Gets `context_window` directly from claude, so it is unaffected by transcript persistence.
- **Shared rules** (`shared/rules/`, `@`-imported by each `CLAUDE.md`): `security.md` (no `rm` — soft-delete to `.trash/`; never leak secrets), `karpathy-coding-guidelines.md`, `code-review-required.md`, `git-protect.md` (no auto commit/push), `agent-lifecycle-protect.md`, `no-askuserquestion-tool.md` (ask via Telegram + buttons, never the local TUI picker), `long-context-self-restart.md`.

## 11. Cold restore — order of operations

Rebuilding on a fresh machine, top to bottom:

1. **Install the toolchain** — versions and paths in the host file; `references/porting.md` if the OS differs.
2. **Stand up the forked telegram plugin** — `references/telegram-plugin.md`. Do this before first launch so agents boot with a working channel.
3. **Lay down `~/agents/`** — `_template`, `shared/`, `scripts/`, per-agent `CLAUDE.md` + `.claude/settings.json` + skills.
   ⚠ **OPEN GAP on every host so far:** `~/agents` has **no git repo or backup transport**, so on a truly fresh machine there is nothing to clone. Establish one first (private remote with a hard `.gitignore` for secrets, runtime state and plugin caches; or a periodic tarball).
4. **Restore secrets** (§12).
5. **`scripts/start.sh`** — creates the session, windows and registry, launches each agent.
6. **First-run wizard + OAuth** per agent (§9).
7. Clone external project repos on demand (host file).
8. Optionally recreate a boot autostart task.

**Acceptance checks — a restore isn't done until all of these pass:**

```
scripts/status.sh                                        # every agent ✅ up
ls ~/.claude-agents/<name>/channels/telegram/bot.pid     # exists for every telegram agent
scripts/agent-send.sh controller "ping"                  # target actually responds
tail ~/agents/scripts/tg-notify.log                      # chat=<id> OK, not FAIL
```
Plus, by eye: the pane status line renders, and a DM to the bot gets a reply with the context popup attached.

## 12. Secrets — not in any repo, no automated backup

| Secret | Location | Restore if lost |
|---|---|---|
| Telegram bot token | `~/.claude-agents/<name>/channels/telegram/.env` (chmod 600) | Re-issue via BotFather (`/token`), rewrite `.env`. |
| Access policy | `~/.claude-agents/<name>/channels/telegram/access.json` | Recreate: `dmPolicy`, `allowFrom`, `groups`. |
| Claude OAuth | Windows: `~/agents/<name>/.claude/.credentials.json` · macOS: login Keychain | See the host file — the two platforms differ fundamentally. |

**Action item, still open:** set up an off-machine encrypted backup of `~/.claude-agents/*/channels/telegram/`. Do NOT commit it.

