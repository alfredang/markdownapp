---
description: Regenerate the Xcode project and build Markdown Vault for macOS
---

Build the macOS app and report only the result.

1. `xcodegen generate`
2. `xcodebuild -project MarkdownVault.xcodeproj -scheme MarkdownVault -destination 'platform=macOS' -configuration Debug -derivedDataPath /tmp/mvbuild build 2>&1 | grep -E "error:|BUILD"`

If the build fails, summarize each `error:` line with its `file:line` and propose a fix. Keep iOS
compiling too — macOS-only code must stay inside `#if os(macOS)`.
