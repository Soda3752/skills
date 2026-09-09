---
name: screen-api-wiki
description: "Build (and keep updating) an Obsidian wiki that documents an app screen-by-screen — each screen page carries its screenshot, the UI-element-to-field mapping, and links to every API it calls; each API page carries the screenshots of the screens that call it and the field-to-UI mapping back. Bidirectional, field-level. Also handles setup: diagnoses and fixes the missing pieces (vault, mcpvault MCP, Multi-Column Markdown plugin, screenshot source) before generating anything. Use this whenever the user wants app documentation organized by screen, asks which APIs a screen calls or which screens an API feeds, wants a wiki/knowledge base of their app's UI and API surface, or wants existing screen/API docs refreshed after code changes. Triggers: \"整理專案的 obsidian wiki\", \"每個畫面會打什麼 API\", \"畫面跟 API 的對照\", \"欄位對到畫面上哪裡\", \"幫我做 APP 的知識庫\", \"畫面文件\", \"API 文件加截圖\", \"wiki 補上新畫面\", \"文件跟程式碼對不上\", \"document each screen and its APIs\", \"build an obsidian wiki for this app\", \"which screens call this endpoint\", \"map API fields to UI elements\", \"refresh the screen docs\", \"截圖用 playwright 拍\", \"前端專案的畫面文件\", \"screenshot every route with playwright\". Handles both mobile (Kotlin Multiplatform / Compose) and web front-end projects (React / Next / Vue / Svelte) — it detects which and follows the matching scan and screenshot playbook, using Playwright for web captures."
---

# screen-api-wiki

Turn a codebase into an Obsidian wiki whose spine is **the screens the user actually sees**, cross-linked with the APIs behind them at field level.

Works on two project shapes — **mobile** (KMP / Compose) and **web front-end** (React / Next / Vue / Svelte / TanStack). The workflow, page layout, and validation are identical; only the scan rules and the screenshot source differ, and each has its own reference file.

The thing that makes this worth doing (and the thing a generic "document the API" pass misses): a developer looking at `¥850` on a product card wants to know it came from `unit_price` in `GET /api/orders`. A developer looking at `unit_price` wants to know it shows up as the price line on the product card. Both directions get asked, so both directions get written.

## What the user ends up with

```
vault/
├─ 00-首頁.md              index + global flow diagram
├─ 10-畫面/                one page per screen: screenshot | element↔field | flow | UiState
├─ 20-API/                 one page per endpoint: full req/res schema + screenshots of callers
├─ 30-資料模型/            one page per model: fields + "which screen shows this"
├─ 40-機制/                cross-cutting: auth/crypto, error recovery, domain invariants
├─ 50-對照/欄位對照總表.md  one flat table: screen | element | field | API
└─ attachments/*.png       screenshots
```

Screen pages and API pages both use a two-column layout — screenshot on the left, a real markdown table on the right — via the Multi-Column Markdown plugin. That plugin is a hard requirement for the layout; see `references/multi-column.md`.

## Step 0 — Doctor

Never start generating before this. A wiki full of broken image embeds or unrendered `--- start-multi-column` markers is worse than no wiki, and it is expensive to unwind once written.

Check and report as a list, then ask the user to confirm before fixing anything:

| Check | How | If missing |
|---|---|---|
| Vault exists | `ls -d vault/.obsidian` | delegate to `obsidian-init` (same plugin) |
| MCP wired | `grep -q obsidian .mcp.json` | `obsidian-init` handles it |
| Multi-Column plugin | `ls vault/.obsidian/plugins/multi-column-markdown` | guide the install, see `references/multi-column.md` |
| Project shape | see "Detect the project shape" below | neither → say plainly what that costs, then ask |
| Screenshots available | see `references/screenshots.md` | pick a source **with** the user |
| Playwright (web only) | `ls node_modules/playwright` | `npm i -D playwright && npx playwright install chromium` |

### Detect the project shape

```bash
ls */src/commonMain/kotlin 2>/dev/null && echo KMP
[ -f package.json ] && grep -qE '"(react|vue|svelte|next|nuxt)"' package.json && echo WEB
```

| Result | Read for scanning | Screenshots |
|---|---|---|
| KMP | `references/scan-kmp.md` | existing folder / Roborazzi / Appium |
| Web | `references/scan-web.md` | existing folder / **Playwright** (`scripts/shoot-web.mjs`) |
| Both (a repo with app + front-end) | ask which one this wiki is for; doing both in one vault makes the screen index incoherent | — |
| Neither | say so plainly — the scan rules are written against those two shapes, and anything else falls back to inference with patchier screen↔API coverage — then ask whether to continue | — |

Two of these deserve a real conversation rather than a silent default:

**Screenshots.** There are three sources and they cost wildly different amounts of the user's time (minutes vs. half an hour). Do not decide this alone — `references/screenshots.md` has the tradeoffs, present them and let the user pick.

**Vault already has content.** If `vault/10-畫面/` already exists, this is an update, not a build. Jump to "Incremental update" below.

## Step 1 — Scan the codebase

Read `references/scan-kmp.md` or `references/scan-web.md` — whichever matches the shape you detected — for what to grep and in what order. The short version: enumerate routes → screens → ViewModels → Repositories → endpoints → models, and write the inventory down before writing any page.

Two things to extract that are easy to skip and expensive to add back later:

- **Which API each screen calls, and at what moment** (on entry, on a button, in a background loop). "Calls `GET /orders`" is much less useful than "calls it on entry, on pull-to-refresh, and after a successful report".
- **Fields that never reach the UI.** They are worth an explicit line ("回應有但畫面不用"). Otherwise the next reader assumes the doc is incomplete and re-derives it.
- **What is not from the server at all** — locally computed totals, URL/query-driven state, build-time constants, optimistic updates. Marking these "純本機 / 純前端" saves the next reader from hunting for a backend field that doesn't exist.

Show the inventory to the user before generating. It is much cheaper to correct "you missed the camera screen" here than after 40 pages exist.

## Step 2 — Get the screenshots

Follow the source the user chose in Step 0. For web projects that means filling in a `routes.json` **together with the user** and running `scripts/shoot-web.mjs`; the reference file covers the config format, the selector-vs-timeout tradeoff, and why credentials go in env vars. Copy every image into `vault/attachments/` with a **stable, ordinal, descriptive** filename (`03-採購中.png`), because those names get embedded in dozens of pages and renaming later means editing all of them.

Then map each screenshot to a screen **and to a section within that screen** (list state vs. dialog vs. bottom sheet). Confirm the mapping with the user if any screenshot is ambiguous — a screenshot filed under the wrong screen quietly poisons every cross-link that points at it.

Screens with no screenshot are fine. Write the page without one and say so in a line; do not invent a mockup.

## Step 3 — Generate

Page templates, section names, and the exact two-column block format are in `references/vault-layout.md` — note that web projects use wider images and a different column split, since a 1440-wide desktop capture is unreadable at the mobile width. Follow the section headings there literally, because cross-page links target them as anchors (`[[今日採購#商品卡]]`) and drifting heading text silently breaks them.

Order matters. Write in this sequence:

1. **30-資料模型** first — every other page links into it, and writing models first forces you to settle field names once.
2. **20-API** — full request/response tables. Every field gets a row, including the ones the UI ignores.
3. **10-畫面** — screenshot + element↔field mapping + operation flow.
4. **40-機制** — the cross-cutting things that don't belong to one screen (auth, error recovery, any "never auto-retry this" rules).
5. **50-對照 + 00-首頁** last, once every page name is final.

Then add the reverse links: each model and API page gets a "欄位 → 畫面元素" section, each screen page gets "畫面 ↔ 欄位". This second pass is where the wiki stops being a list of endpoints and starts being navigable.

### One decision worth making deliberately

In screen-page tables, the "來源" column can link to either the model page or the API page. Link the **API**. Someone reading a screen page is asking "where does this number come from over the wire", and one more hop through a model page is friction. Models keep their own reverse-mapping section for the opposite question.

## Step 4 — Validate

```bash
scripts/validate-vault.sh <vault-path>
```

It checks four things that are trivially automatable and painful to catch by eye: broken `[[wikilinks]]`, `#anchors` pointing at headings that don't exist, `![[image.png]]` embeds with no file behind them, and unbalanced `start-multi-column` / `column-break` / `end-multi-column` triples.

Two failure modes it catches that come up almost every time:

- **A heading with a `[[link]]` inside it.** Obsidian will not resolve `[[Page#Heading with [[a link]]]]`. Keep headings plain text.
- **Renamed or merged sections.** Merging `### 頁首` and `### 開工卡` into one heading orphans every link that pointed at either. The script reports it; fix the referrers, don't recreate the heading.

Run it until it is clean, then tell the user which single page to open first to sanity-check the rendering (pick one with a two-column block and a mermaid diagram in it).

## Incremental update

When the vault already exists, treat hand-edits as authoritative. The user has been reading and correcting these pages; silently regenerating over their notes destroys the most valuable content in the vault.

1. Re-scan the code and diff against the vault: which screens/APIs/models are new, gone, or renamed.
2. Report the diff and let the user choose what to apply.
3. Add new pages. For existing pages, **only** rewrite the specific sections whose backing code changed, and say which ones you touched.
4. For removals, don't delete — mark the page `> ⚠ 這支已從程式碼移除（<日期>）` and fix inbound links. A deleted page takes its accumulated commentary with it.
5. Re-run the validator.

## Things to avoid

- Generating pages before the doctor passes, or before the user has confirmed the screen/API inventory.
- Inventing screenshots (ASCII mockups, placeholder images) for screens you couldn't capture. A missing screenshot is honest; a fake one gets mistaken for the real UI.
- Documenting only the happy path. The rows that earn their keep are the conflict responses, the "this field is required or the backend silently defaults it" notes, and the "this endpoint deliberately does not retry" rules. Mine the code comments — that reasoning is usually already written down next to the code.
- Restating an endpoint's field table on the screen page. Screen pages say what the user sees and link out; API pages own the schema.
- Committing the vault. `obsidian-init` gitignores it on purpose; the user decides otherwise.
