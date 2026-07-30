# Porting the fleet to a new OS

What it actually takes to move `~/agents` to a different platform. Derived from the Windows → macOS port completed 2026-07-30, which took roughly ten categories of change — not just the hardcoded paths.

Work top to bottom; each step's verification is at the end.

## 1. Inventory the toolchain first

Required: a terminal multiplexer, **bash 5** (not 3.2 — the scripts use `${var^^}`, `[[ =~ ]]` with `BASH_REMATCH`, arrays), Node, bun, the Claude Code CLI, python3, git, and a puppeteer Chromium if you want table/Mermaid rendering.

Record real paths before writing anything — they go into the new host file.

## 2. Multiplexer

`psmux` (Windows) and `tmux` (Unix) are command-line compatible for everything the fleet uses (`new-session`, `new-window`, `list-panes -F`, `send-keys -l`, `select-pane -T`, `capture-pane`, `respawn-pane`, `has-session`, `kill-session`). A mechanical `s/\bpsmux\b/tmux/g` across `scripts/` is safe.

Also rename `AGENTS_PSMUX_SESSION` → `AGENTS_TMUX_SESSION` (or keep a neutral name).

Keep the **pane registry** even on real tmux, which does support per-pane options — one mechanism across hosts is worth more than the small simplification.

## 3. Strip the Windows layer

Three things, all mechanical:

- **MSYS2 re-exec preambles** — the `if [[ -z "${_AGENT_REEXEC:-}" ]] && [[ -x /c/msys64/usr/bin/bash ]]` block at the top of nearly every script. Already dead code on the Windows host itself (msys64 isn't installed there). Delete.
- **`export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'`** — Git-bash path mangling protection. Meaningless off Windows. Delete.
- **`to_win_path()`** in `lib/common.sh`, and every call site (`AGENTS_HOME_WIN`, `BASH_WIN`, `TG_DIR_WIN`). Delete the function rather than making it an identity — the call sites read as nonsense otherwise.

## 4. Shell selection — subtler than it looks

Two separate problems:

**Which bash.** macOS ships bash **3.2** at `/bin/bash`; the scripts need 5. `#!/usr/bin/env bash` is not enough, because a login shell inside a pane may not have Homebrew on PATH yet — chicken and egg. Pin the shebang to the absolute path (`#!/opt/homebrew/bin/bash`) and pin the multiplexer's `default-shell` / `default-command` to the same, with an env override for portability:

```bash
FLEET_BASH="${FLEET_BASH:-/opt/homebrew/bin/bash}"
[[ -x "$FLEET_BASH" ]] || die "bash 5 not found at $FLEET_BASH"
tmux set -g default-shell "$FLEET_BASH"
tmux set -g default-command "$FLEET_BASH -l"
```

**PATH inside a pane.** This is the single nastiest platform trap. `bash -l` reads `~/.bash_profile`; on a modern Mac the user's real environment (Homebrew `shellenv`, nvm, `~/.local/bin`) is set up in `~/.zprofile`, which bash never reads. A pane therefore has **no `claude`, no `bun`, no bash 5** and every launch fails with a bare "command not found".

Fix centrally in `lib/common.sh`, so every script and hook inherits it:

```bash
export PATH="$AGENTS_HOME/shared/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
```

## 5. `shared/bin/` — one indirection instead of many hardcodes

Create `~/agents/shared/bin/` with symlinks to `node`, `claude`, `bun`, `tmux`, and put it first on PATH. Point every `settings.json` hook and `statusLine` command at `shared/bin/node` rather than at, say, an nvm-versioned path. Upgrading nvm or Homebrew then means re-pointing one symlink, not rewriting every agent's config.

## 6. Rewrite hardcoded paths in configs

Per agent (and in `_template`): `settings.json`'s `TELEGRAM_STATE_DIR`, `statusLine.command`, and the Stop / SessionStart / SessionEnd hook commands. Note the two different encodings in the same file — `env` values use OS-native separators, while hook `command` strings use forward slashes even on Windows.

Sanity check afterwards, excluding `node_modules` or the grep is useless:

```bash
grep -rn "D:" --include=settings.json --include=CLAUDE.md ~/agents
```

## 7. GNU vs BSD userland

| GNU (Linux / Git-bash) | BSD (macOS) |
|---|---|
| `sed -i "s/…/…/"` | `sed -i '' "s/…/…/"` — and BSD sed will **not** expand `\n` in the replacement |
| `timeout 15 cmd` | no `timeout(1)`; use `gtimeout` or a bounded polling loop |
| `python` | `python3` only |
| `ls -l` shows dotfiles in some setups | never; use `ls -la` or `.env` looks missing |

For in-place edits, prefer `perl -i -pe` on both platforms — one syntax, real `\n` support, and passing values through the environment (`NAME="$NAME" perl -i -pe 's/__NAME__/$ENV{NAME}/g'`) keeps them from being parsed as regex or delimiters.

## 8. Re-examine the liveness / restart heuristics

Anything that reads the screen is platform-specific by construction. The concrete case: `start-agent.sh` decided "pane is at an idle shell" by matching a last line that is a lone `$`. macOS prompts are `<host>:<dir> <user>$`, so the check never matched and every restart aborted with "TUI still in %N after /exit" — even though the pane *was* idle.

Replace with `pane_is_alive()` from `common.sh` (the `claude.running` marker). Audit for other screen-scraping while you're there.

## 9. Credentials

Do not assume the Windows model. On macOS, Claude Code stores credentials in the **login Keychain**, globally — not per `CLAUDE_CONFIG_DIR` — so one OAuth covers the whole fleet, and the Windows "never copy `.credentials.json`, refresh tokens are single-use" rule simply doesn't apply. Check the platform's storage before planning N logins.

## 10. Plugins

Follow `telegram-plugin.md` end to end. Two things that will not be true on the new machine: the local marketplace checkout may be stale despite its version label, and nothing will have written `known_marketplaces.json` for you.

## Verification

The port is done when all of these pass — see `../SKILL.md` §11 for the same list in context:

```bash
bash -n scripts/*.sh scripts/tg/*.sh scripts/lib/common.sh   # syntax, all files
python3 -m json.tool <each settings.json>                    # valid JSON
scripts/start.sh                                             # session + windows + registry
scripts/status.sh                                            # every agent ✅ up
scripts/agent-send.sh controller "ping"                      # a real reply comes back
ls ~/.claude-agents/<name>/channels/telegram/bot.pid         # poller alive
tail scripts/tg-notify.log                                   # chat=<id> OK
```

And by eye: the pane status line renders, and a DM to the bot gets a reply carrying the context popup with working 🧹 / 🔄 buttons (those buttons are the fork's signature — if they're dead, you're running the official plugin).

Don't forget the **first-run wizard** (`../SKILL.md` §9): a freshly launched agent is sitting in onboarding, not at a prompt, and answering "yes" to the fullscreen renderer will break `capture-pane` for all your tooling.
