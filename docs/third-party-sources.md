# 第三方來源

這裡的 skill / plugin 都不 vendor 進本 repo，只記來源。換機器時照表重裝。

不 vendor 的理由：它們有各自的上游與授權，複製一份進來就等於分岔——上游修了 bug 這裡不會知道，而且散布別人的作品需要確認授權。記來源則沒有這些問題。

## Marketplace

```
/plugin marketplace add anthropics/claude-plugins-official
/plugin marketplace add anthropics/skills
/plugin marketplace add mattpocock/skills
/plugin marketplace add phuryn/pm-skills
/plugin marketplace add willseltzer/claude-handoff
/plugin marketplace add microsoft/Webwright
/plugin marketplace add https://github.com/netlify/context-and-tools.git
```

| Marketplace | 來源 |
| --- | --- |
| `claude-plugins-official` | `anthropics/claude-plugins-official` |
| `anthropic-agent-skills` | `anthropics/skills` |
| `mattpocock` | `mattpocock/skills` |
| `pm-skills` | `phuryn/pm-skills` |
| `handoff-marketplace` | `willseltzer/claude-handoff` |
| `webwright` | `microsoft/Webwright` |
| `netlify-context-and-tools` | `netlify/context-and-tools` |

## 使用者層級（user scope）常用 plugin

```
/plugin install claude-code-setup@claude-plugins-official
/plugin install context7@claude-plugins-official
/plugin install skill-creator@claude-plugins-official
/plugin install claude-md-management@claude-plugins-official
/plugin install gitlab@claude-plugins-official
/plugin install swift-lsp@claude-plugins-official
/plugin install mattpocock-skills@mattpocock
/plugin install handoff@handoff-marketplace
```

專案層級的（`frontend-design`、`pm-product-discovery`、`pyright-lsp` 等）跟著各專案走，不列在這裡——它們是專案需求，不是個人環境的一部分。

## GitNexus 相關 skill

`~/.claude/skills/` 底下的七個 `gitnexus-*`（`cli` / `guide` / `exploring` / `debugging` / `impact-analysis` / `refactoring` / `pr-review`）疑似是 [GitNexus](https://www.npmjs.com/package/gitnexus) 隨附產生的，著作歸屬未確認，因此不收進本 repo。

需要的話裝 GitNexus 本身即可：

```bash
npx gitnexus analyze
```

本 repo 收錄的 `gitnexus-init` 是自寫的初始化 SOP，與上述七份無關。
