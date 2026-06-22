#if os(macOS)
import SwiftUI
import AppKit

/// A plain-text Markdown source editor backed by NSTextView, with a Notion/Obsidian-style
/// "/" slash-command menu for inserting Markdown snippets and emoji at the caret.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = bg

        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textColor = fg
        tv.backgroundColor = bg
        tv.drawsBackground = true
        tv.insertionPointColor = NSColor(srgbRed: VSCode.termCaret.r, green: VSCode.termCaret.g, blue: VSCode.termCaret.b, alpha: 1)
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.string = text
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
        }
    }

    private var bg: NSColor { NSColor(srgbRed: VSCode.termBg.r, green: VSCode.termBg.g, blue: VSCode.termBg.b, alpha: 1) }
    private var fg: NSColor { NSColor(srgbRed: VSCode.termFg.r, green: VSCode.termFg.g, blue: VSCode.termFg.b, alpha: 1) }

    // MARK: - Coordinator
    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: CodeEditorView
        weak var textView: NSTextView?
        private var pendingSlash = 0

        init(_ parent: CodeEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            detectSlash(tv)
        }

        /// Show the slash menu when the user types "/" at the start of a token.
        private func detectSlash(_ tv: NSTextView) {
            let sel = tv.selectedRange()
            guard sel.length == 0, sel.location > 0 else { return }
            let ns = tv.string as NSString
            guard ns.substring(with: NSRange(location: sel.location - 1, length: 1)) == "/" else { return }
            if sel.location >= 2 {
                let before = ns.substring(with: NSRange(location: sel.location - 2, length: 1))
                if !(before == " " || before == "\n" || before == "\t") { return }
            }
            pendingSlash = sel.location - 1
            // Defer so the "/" is committed before the modal menu tracks the mouse/keys.
            DispatchQueue.main.async { [weak self] in self?.showMenu(tv) }
        }

        private func showMenu(_ tv: NSTextView) {
            let menu = NSMenu()
            for cmd in SlashCommand.all {
                if cmd.isSeparator { menu.addItem(.separator()); continue }
                let item = NSMenuItem(title: cmd.title, action: #selector(pick(_:)), keyEquivalent: "")
                item.image = NSImage(systemSymbolName: cmd.symbol, accessibilityDescription: nil)
                item.target = self
                item.representedObject = cmd
                menu.addItem(item)
            }
            // Anchor at the caret.
            var point = NSPoint(x: 0, y: 20)
            if let lm = tv.layoutManager, let tc = tv.textContainer {
                let gr = lm.glyphRange(forCharacterRange: NSRange(location: pendingSlash, length: 1), actualCharacterRange: nil)
                var r = lm.boundingRect(forGlyphRange: gr, in: tc)
                r.origin.x += tv.textContainerOrigin.x
                r.origin.y += tv.textContainerOrigin.y
                point = NSPoint(x: r.minX, y: r.maxY + 4)
            }
            menu.popUp(positioning: nil, at: point, in: tv)
        }

        @objc private func pick(_ sender: NSMenuItem) {
            guard let tv = textView, let cmd = sender.representedObject as? SlashCommand else { return }
            let range = NSRange(location: pendingSlash, length: 1)   // the "/"
            if cmd.opensEmojiPalette {
                replace(range, with: "", in: tv)
                tv.window?.makeFirstResponder(tv)
                NSApp.orderFrontCharacterPalette(tv)
                return
            }
            replace(range, with: cmd.snippet, in: tv)
            if let caret = cmd.caretOffset {
                tv.setSelectedRange(NSRange(location: range.location + caret, length: 0))
            }
        }

        private func replace(_ range: NSRange, with string: String, in tv: NSTextView) {
            guard tv.shouldChangeText(in: range, replacementString: string) else { return }
            tv.textStorage?.replaceCharacters(in: range, with: string)
            tv.didChangeText()
            parent.text = tv.string
        }
    }
}

/// A single entry in the slash-command menu.
struct SlashCommand {
    let title: String
    let symbol: String
    let snippet: String
    var caretOffset: Int? = nil
    var isSeparator = false
    var opensEmojiPalette = false

    static func sep() -> SlashCommand { SlashCommand(title: "", symbol: "", snippet: "", isSeparator: true) }

    static let all: [SlashCommand] = [
        SlashCommand(title: "Heading 1", symbol: "1.square", snippet: "# "),
        SlashCommand(title: "Heading 2", symbol: "2.square", snippet: "## "),
        SlashCommand(title: "Heading 3", symbol: "3.square", snippet: "### "),
        .sep(),
        SlashCommand(title: "Todo / Checklist", symbol: "checklist", snippet: "- [ ] "),
        SlashCommand(title: "Bullet List", symbol: "list.bullet", snippet: "- "),
        SlashCommand(title: "Numbered List", symbol: "list.number", snippet: "1. "),
        SlashCommand(title: "Quote", symbol: "text.quote", snippet: "> "),
        .sep(),
        SlashCommand(title: "Bold", symbol: "bold", snippet: "**bold**", caretOffset: 2),
        SlashCommand(title: "Italic", symbol: "italic", snippet: "*italic*", caretOffset: 1),
        SlashCommand(title: "Inline Code", symbol: "chevron.left.forwardslash.chevron.right", snippet: "`code`", caretOffset: 1),
        SlashCommand(title: "Link", symbol: "link", snippet: "[text](https://)", caretOffset: 1),
        SlashCommand(title: "Image", symbol: "photo", snippet: "![alt](image.png)", caretOffset: 2),
        .sep(),
        SlashCommand(title: "Code Block", symbol: "curlybraces.square", snippet: "```\n\n```\n", caretOffset: 4),
        SlashCommand(title: "Table", symbol: "tablecells", snippet: "| Column A | Column B |\n| --- | --- |\n| | |\n"),
        SlashCommand(title: "Divider", symbol: "minus", snippet: "\n---\n"),
        .sep(),
        SlashCommand(title: "✅  Done", symbol: "checkmark.circle", snippet: "✅ "),
        SlashCommand(title: "🚀  Rocket", symbol: "paperplane", snippet: "🚀 "),
        SlashCommand(title: "📝  Note", symbol: "note.text", snippet: "📝 "),
        SlashCommand(title: "⚠️  Warning", symbol: "exclamationmark.triangle", snippet: "⚠️ "),
        SlashCommand(title: "💡  Idea", symbol: "lightbulb", snippet: "💡 "),
        SlashCommand(title: "More Emoji…", symbol: "face.smiling", snippet: "", opensEmojiPalette: true),
    ]
}
#endif
