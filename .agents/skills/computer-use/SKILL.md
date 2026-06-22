---
name: computer-use
description: Drive the macOS GUI of Markdown Vault (or any Mac app) via screenshots + AppleScript/System Events — open the vault, click menus, navigate native Open/Save panels, verify UI. Use when a task needs real mouse/keyboard interaction with the running app (e.g. "open my vault", "click Extensions", "take a screenshot") rather than file edits.
---

# Computer Use — driving the Mac app

Use macOS UI scripting (not Playwright — that's browsers only) to operate the running app.

## Golden rules
1. **Always screenshot first, then act, then screenshot to verify.** Never fire blind keystrokes.
   `screencapture -x -o /tmp/s.png` then Read it.
2. **Guard focus before every keystroke** — a notification can steal focus:
   ```bash
   osascript -e 'tell application "Markdown Vault" to activate'
   osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'
   ```
   Only send keys if the frontmost process is the target. (Learned the hard way: blind keys once
   landed in WhatsApp.)
3. Prefer **menu items / keyboard shortcuts** over coordinate clicks when possible.

## Open the user's vault (sandbox-free build → bookmark, or via the Open panel)
The app is non-sandboxed, so the cleanest deterministic way is to write a plain bookmark to its
defaults, then launch:
```bash
osascript -e 'quit app "Markdown Vault"'; sleep 1
xcrun swift - <<'SWIFT'
import Foundation
let path = "/Users/alfredang/Documents/Supporting Document/Obsidian Vaults/Alfred_Obsidian"
let url = URL(fileURLWithPath: path, isDirectory: true)
let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
let d = UserDefaults(suiteName: "com.tertiaryinfotech.markdownapp")!
d.set(data, forKey: "vault.bookmark"); d.set(true, forKey: "vault.onboarded"); d.synchronize()
SWIFT
open "/Applications/Markdown Vault.app"
```

Alternative — drive the native **Open Vault** panel (⌘O), which runs in the
`com.apple.appkit.xpc.openAndSavePanelService` process:
```bash
osascript -e 'tell application "Markdown Vault" to activate'
osascript -e 'tell application "System Events" to keystroke "o" using {command down}'   # Open Vault
# in the panel: ⌘⇧G, type the absolute path, Return, Return
```

## Screenshot a single window (for README/verification)
```bash
# get window bounds, then capture that rect
osascript -e 'tell application "System Events" to tell process "Markdown Vault" to get {position, size} of front window'
screencapture -x -o -R"x,y,w,h" /tmp/win.png
```

## Useful in-app shortcuts
⌘P quick-open · ⌘B side bar · ⌃` terminal · ⌘O open vault · ⌘N new file.
