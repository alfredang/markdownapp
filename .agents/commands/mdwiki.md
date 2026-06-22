---
description: Run the mdwiki CLI to create/update Markdown content in a vault
argument-hint: <mdwiki subcommand and args>
---

Run the vault content CLI: `Tools/mdwiki $ARGUMENTS`

Pass `--vault <path>` (or set `MDVAULT`) to target a vault other than the current directory.
Common uses:

- `Tools/mdwiki --vault "$MDVAULT" init`
- `Tools/mdwiki --vault "$MDVAULT" new concept "Topic" --title "Title"`
- `Tools/mdwiki --vault "$MDVAULT" todo wiki/concepts/topic.md "task"`
- `Tools/mdwiki --vault "$MDVAULT" index`
- `Tools/mdwiki --vault "$MDVAULT" log ingest "summary"`

See `CLAUDE.md` for the full command list and the wiki maintenance schema.
