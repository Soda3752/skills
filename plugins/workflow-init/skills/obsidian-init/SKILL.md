---
name: obsidian-init
description: "Initialize an Obsidian vault and a project-scope MCP server (using @bitbonsai/mcpvault) inside the current project. Use this skill whenever the user wants to set up Obsidian for a project, attach a notes/vault area, configure project-scope MCP for Obsidian, or initialize an Obsidian vault — even if they don't say the exact word \"vault\". Triggers: \"幫專案建 obsidian\", \"設定 obsidian MCP\", \"project scope obsidian\", \"初始化 vault\", \"給這個專案加筆記區\", \"obsidian 接這個專案\", \"mcpvault\", \"set up obsidian for this project\", \"add obsidian vault\", \"wire up obsidian MCP server\". Run the workflow as specified — do not re-ask the user about vault name, gitignore behavior, or which MCP package to use; defaults are intentional."
---

# obsidian-init

Set up Obsidian for the current project: create an empty vault, add it to git ignore, and register a project-scope MCP server pointing to it. Four fixed steps. **Do not re-interview the user about which package, vault name, or whether to gitignore — those decisions are baked in.** If the user wants something different, they can tell you afterwards and you can adjust; the skill exists to skip the back-and-forth on the common case.

## What this gives the user

- `./vault/` with `.obsidian/` subfolder — Obsidian recognizes it as a real vault on first open
- `/vault/` line in `.gitignore` — personal notes don't get committed
- `.mcp.json` with `obsidian` server using `npx @bitbonsai/mcpvault@latest <ABS_PATH>/vault` — the project's `mcp__obsidian__*` tools (read_note, write_note, get_vault_stats, patch_note, list_directory, etc.) target this vault, overriding any user-scope `obsidian` server while inside this project

## Why mcpvault and not cyanheads/stevenstavrakis/etc.

`@bitbonsai/mcpvault` reads the vault directory directly from the filesystem. **It does not require Obsidian.app to be running, does not need the Local REST API plugin, and does not need an API key.** Other popular Obsidian MCP servers (cyanheads, MarkusPfundstein) speak to Obsidian over HTTP via the Local REST API plugin — that's heavier setup and a runtime dependency on the Obsidian app being open. mcpvault is the right default for "I just want a notes area wired up".

The tool names mcpvault exposes (`read_note`, `write_note`, `get_vault_stats`, `patch_note`, `get_frontmatter`, `update_frontmatter`, `read_multiple_notes`, `list_directory`, `manage_tags`, `list_all_tags`, `move_note`, `delete_note`, `search_notes`, `move_file`) are also what most users already have in their global MCP setup, so behavior stays consistent across projects.

## Pre-flight

1. Confirm the current working directory **is** the project root the user wants to set up. Claude Code's cwd is normally the project root, so this is usually fine — but if the cwd is a subdirectory, ask before proceeding.
2. Capture the absolute path of the project root. You'll need it verbatim for `.mcp.json` because **mcpvault's args do not expand `${workspaceFolder}` or any other variable** — Claude Code passes args as literal strings to the spawned process. Relative paths also can't be trusted because the cwd at MCP server launch time isn't guaranteed to be the project root.

## Step 1 — Create vault directory

```bash
mkdir -p <PROJECT_ROOT>/vault/.obsidian
```

`mkdir -p` is idempotent. If `vault/` already exists with content, leave it alone — the user may have been mid-setup.

## Step 2 — Update `.gitignore`

The block to ensure exists:

```
# Obsidian vault (project scope MCP)
/vault/
```

Three cases to handle:

- **`.gitignore` does not exist**: create it with just the block above.
- **`.gitignore` exists and already contains `/vault/`** (check via `grep -Fx "/vault/" .gitignore` — exact line match, no leading slash variants): do nothing. Don't append a duplicate.
- **`.gitignore` exists but does not contain `/vault/`**: append the block. Lead with a blank line if the existing file doesn't already end in one, so the block reads cleanly.

Use the `Edit` or `Write` tool, not shell heredocs — the file may have trailing-newline edge cases that shell appends mishandle.

## Step 3 — Create or merge `.mcp.json`

The server entry to install:

```json
{
  "obsidian": {
    "command": "npx",
    "args": [
      "@bitbonsai/mcpvault@latest",
      "<PROJECT_ROOT>/vault"
    ],
    "env": {}
  }
}
```

Substitute `<PROJECT_ROOT>` with the actual absolute path captured in pre-flight.

Three cases:

- **`.mcp.json` does not exist**: write a fresh file with `{ "mcpServers": { "obsidian": <entry above> } }`.
- **`.mcp.json` exists, no `obsidian` key under `mcpServers`**: read it, add the `obsidian` entry alongside the existing servers, write it back. Preserve all other servers exactly. Use `Read` + `Edit` rather than re-serializing the JSON wholesale to keep the user's original formatting intact where possible.
- **`.mcp.json` exists, already has an `obsidian` key**: stop and ask the user — overwrite, rename the new one (e.g., `obsidian-<projectname>`), or skip. Do not silently overwrite; the existing one might be a different package the user is depending on.

## Step 4 — Report and hand off

Tell the user, concisely:

1. What was created (vault path, gitignore line added or already present, .mcp.json status).
2. **How to activate**: the project-scope MCP server only loads after Claude Code reconnects to MCP. Restarting Claude Code or running `/mcp` triggers reconnect. The first connection shows a trust prompt for the `.mcp.json` file — they need to Approve it.
3. **Caveat about absolute path**: `.mcp.json` contains the project's absolute path. Fine for solo use; if they plan to commit `.mcp.json` for a team, the path won't transfer to other machines. Offer to add `.mcp.json` to `.gitignore` if they confirm it's solo.

## Idempotency

Running this skill twice on the same project should be safe and produce no duplicates:

- vault/ already there → no change
- /vault/ already in .gitignore → no append
- obsidian server already in .mcp.json → ask, don't clobber

If everything is already in place, say so plainly ("project already set up — nothing to do") rather than going through the motions.

## Things to avoid

- Asking the user to choose vault name, package, or gitignore behavior. Those choices are made. If they push back ("I want it called notes/ instead"), then adapt — but don't pre-emptively negotiate.
- Using `${workspaceFolder}` or `~` or relative paths in `.mcp.json` args. mcpvault won't expand them.
- Recommending cyanheads or MarkusPfundstein versions unless the user explicitly says they want to go through Obsidian's Local REST API plugin (e.g., they need Obsidian's full search index, dataview, etc.). For a "just give me a notes folder hooked up" request, mcpvault wins.
- Running `git add .mcp.json` or committing anything. The user decides what to commit.
