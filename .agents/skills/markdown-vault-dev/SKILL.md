---
name: markdown-vault-dev
description: Develop and manage the Markdown Vault app — build/run the macOS app, follow its SwiftUI architecture and conventions, and use the mdwiki CLI to manage vault Markdown content. Use when modifying app code, adding views/extensions, or updating notes in a vault.
---

# Markdown Vault — Dev & Management Skill

Markdown Vault is a native SwiftUI Markdown editor (macOS/iPadOS/iOS). On macOS it is a VS Code-style
workspace (activity bar · explorer · editor · embedded terminals) with an extension marketplace.

## Build & run (macOS)
```bash
xcodegen generate                       # regenerate the project after editing project.yml / adding files
xcodebuild -project MarkdownVault.xcodeproj -scheme MarkdownVault \
  -destination 'platform=macOS' -configuration Debug -derivedDataPath /tmp/mvbuild build
# install + launch
rm -rf "/Applications/Markdown Vault.app"
cp -R "/tmp/mvbuild/Build/Products/Debug/Markdown Vault.app" "/Applications/"
open "/Applications/Markdown Vault.app"
```

## Architecture
- macOS root: `VSCodeLayout`; iOS root: `RootView` `TabView`.
- `VaultStore` (vault/file-tree/CRUD/bookmarks), `EditorPane` + `CodeEditorView` (NSTextView + slash
  menu) + `MarkdownPreview`/`MarkdownParser`, `TerminalController`/`TerminalSession`/`TerminalPanel`
  (SwiftTerm), `ExtensionRegistry`/`ExtensionsSidebar`/`ExtensionPanels` + `WikiService`.

## Conventions
- XcodeGen-managed; never hand-edit the `.xcodeproj`.
- Use `Theme.*` / `VSCode.*` tokens, not raw colors.
- Keep iOS compiling — macOS-only code goes in `#if os(macOS)`.
- Desktop build is **non-sandboxed** (embedded terminals). **Not App Store eligible** — for the
  iOS/iPadOS App Store build the macOS terminal code is excluded by `#if os(macOS)`.

## Manage vault content (the `mdwiki` CLI)
`Tools/mdwiki` (Python, no deps) creates/updates Markdown deterministically:
`init`, `new entity|concept`, `set`, `append`, `frontmatter`, `link`, `todo`, `check`, `index`,
`log`, `list`. Run from the vault root or pass `--vault <path>`. See `CLAUDE.md` for the full
reference and the LLM-wiki maintenance schema.

## Markdown conventions (what content looks like)
Obsidian-compatible: `[[wikilinks]]`, `![[embeds]]`, GFM tables, fenced code, and todos
`- [ ]` / `- [x]` (toggle live in Preview).
