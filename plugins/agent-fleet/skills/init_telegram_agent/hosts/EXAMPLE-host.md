# Host: <machine name>

> **Template.** Copy this to `hosts/<your-host>.md`, fill it in, and **do not commit the filled-in copy.** A completed host file is a map of a machine running agents with `--dangerously-skip-permissions`: exact binary paths, what each agent is wired to, which bots exist, which repos it can push to. Keep it on the machine.
>
> Add a line for the new host to the table in `SKILL.md`, then delete this blockquote.

Ported from `<source host>` on `<date>`. Root is `<home dir>`.

Read `../SKILL.md` first — this file only covers what is specific to this machine.

## Roster

| Agent | Channel | Role |
|---|---|---|
| **master** | Telegram DM — bot `@…` | Top-privilege orchestrator, primary user-facing agent. Delegates lifecycle to controller. |
| **controller** | none (service) | Lifecycle manager. `--no-telegram`. Speaks via pane stdout + `agent-send.sh`. |
| … | | |

Agents that live on *other* hosts and must **not** be delegated to from here: `<list, or none>`. Keep them commented out in `AGENT_LIST` in `start.sh` as a reminder.

**Handover driver:** who restarts `master` when its context fills up? With a peer orchestrator (`submaster`), the two drive each other's restarts via `controller`. With only `controller`, it drives master's — and there is no second safety net, so record the manual fallback (`scripts/start-agent.sh master` from an attached session).

## Toolchain

| Tool | Version | Path |
|---|---|---|
| multiplexer (tmux / psmux) | | |
| bash | | **must be 5.x** — macOS ships 3.2 at `/bin/bash`, which cannot run these scripts |
| Node.js | | |
| bun | | |
| Claude Code CLI | | |
| Chromium (puppeteer) | | `~/.cache/puppeteer/chrome/<platform>-<version>` — install with `bun x puppeteer browsers install chrome`; NOT system Chrome |
| python3 | | scripts call `python3`, never `python` |

Pin these versions. The plugin fork and scripts were built against a specific set.

### Stable binary symlinks

Consider `~/agents/shared/bin/` holding symlinks (`node`, `claude`, `bun`) placed first on PATH, with every `settings.json` referencing those rather than a version-pinned path. A runtime upgrade then means re-pointing one link instead of rewriting every agent's config.

### PATH inside a pane

Record how PATH is made correct for panes on this OS. This is the most common way a port fails: a multiplexer pane spawns `bash -l`, which reads `~/.bash_profile` — not `~/.zprofile`, where Homebrew and nvm typically live — so `claude` and `bun` are simply absent and every launch dies with "command not found". See `../references/porting.md` §4.

## Claude OAuth

**Check how this platform stores credentials before planning N logins** — the models differ fundamentally:

- **File-based** (`<CLAUDE_CONFIG_DIR>/.credentials.json`): per-agent. Refresh tokens are single-use, so copying the file between agents **breaks** them. Every agent must log in separately.
- **OS keychain** (macOS): one global item, shared across every agent regardless of `CLAUDE_CONFIG_DIR`. Only the first agent on the machine actually logs in.

Record which applies here, and how it was verified.

## Plugin cache

Does `launch-agent.sh` seed a plugin cache on this host, and into which directory? It must be the **CONFIG** dir (`~/agents/<name>/.claude/plugins`); the STATE dir is the classic mistake. Note also whether the local marketplace checkout is trustworthy — see `../references/telegram-plugin.md`, "version labels lie".

## Autostart

How the fleet comes back after a reboot (Task Scheduler entry / launchd plist / systemd unit / "manually, run `start.sh`"). If it is deliberately absent, say why — e.g. on macOS the Keychain is locked before GUI login, which can break a shared OAuth credential at boot.

## External project repos

| Repo | Remote | Local clone | Agent |
|---|---|---|---|
| | | | |

## Platform gotchas

Anything that bit you here and would bite the next person. Examples from real hosts:

- **BSD vs GNU userland** — `sed -i` needs `sed -i ''` on macOS and won't expand `\n`; no `timeout(1)`; `ls -l` hides dotfiles so `.env` looks missing.
- **Git-bash path mangling** (Windows) — args that look like POSIX paths get rewritten (`/exit` → `C:\...\exit`), corrupting slash-commands sent via `send-keys`. Export `MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'`.
- **The idle-shell prompt is not a lone `$`** on most systems — which is why liveness must come from the `claude.running` marker (`SKILL.md` §4), never from reading the screen.

## Divergences worth folding back to other hosts

Fixes made here first that the other machines should also get. Keeping this list short is the point — long-lived divergence between hosts is how one of them quietly rots.
