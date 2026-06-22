---
description: Build, install to /Applications, and launch Markdown Vault (macOS)
---

Build (per build-app), then install and launch:

1. `osascript -e 'quit app "Markdown Vault"'`
2. `rm -rf "/Applications/Markdown Vault.app" && cp -R "/tmp/mvbuild/Build/Products/Debug/Markdown Vault.app" "/Applications/"`
3. `open "/Applications/Markdown Vault.app"`
4. Optionally screenshot the window for verification with `screencapture -x -o -R"<x,y,w,h>" /tmp/app.png`.

Report install + launch status.
