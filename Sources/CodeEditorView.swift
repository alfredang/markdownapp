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
        tv.font = MarkdownStyler.body
        tv.textColor = fg
        tv.backgroundColor = bg
        tv.drawsBackground = true
        tv.insertionPointColor = NSColor(srgbRed: VSCode.termCaret.r, green: VSCode.termCaret.g, blue: VSCode.termCaret.b, alpha: 1)
        tv.textContainerInset = NSSize(width: 14, height: 14)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.string = text
        context.coordinator.textView = tv
        MarkdownStyler.apply(to: tv.textStorage, baseColor: fg)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
            MarkdownStyler.apply(to: tv.textStorage, baseColor: fg)
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
            MarkdownStyler.apply(to: tv.textStorage,
                                 baseColor: NSColor(srgbRed: VSCode.termFg.r, green: VSCode.termFg.g, blue: VSCode.termFg.b, alpha: 1))
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

/// Obsidian-style "Live Preview": styles Markdown inline in the editable NSTextView so headings
/// look like headings, **bold** is bold, `code` is monospaced, and links are colored — while the
/// underlying text stays plain Markdown.
enum MarkdownStyler {
    static let body   = NSFont.systemFont(ofSize: 15)
    static let bold   = NSFont.boldSystemFont(ofSize: 15)
    static let italic = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 15), toHaveTrait: .italicFontMask)
    static let code   = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)

    static func heading(_ level: Int) -> NSFont {
        switch level {
        case 1:  return .boldSystemFont(ofSize: 28)
        case 2:  return .boldSystemFont(ofSize: 23)
        case 3:  return .boldSystemFont(ofSize: 19)
        default: return .boldSystemFont(ofSize: 16)
        }
    }

    private static func c(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255, alpha: 1)
    }

    static func apply(to ts: NSTextStorage?, baseColor: NSColor) {
        guard let ts = ts else { return }
        let text = ts.string as NSString
        let full = NSRange(location: 0, length: ts.length)
        ts.beginEditing()
        ts.setAttributes([.font: body, .foregroundColor: baseColor], range: full)

        // Per-line: headings and block quotes.
        text.enumerateSubstrings(in: full, options: .byLines) { sub, range, _, _ in
            guard let sub = sub else { return }
            let t = sub.trimmingCharacters(in: .whitespaces)
            if let lvl = headingLevel(t) {
                ts.addAttribute(.font, value: heading(lvl), range: range)
                ts.addAttribute(.foregroundColor, value: c(0xFFFFFF), range: range)
            } else if t.hasPrefix(">") {
                ts.addAttribute(.font, value: italic, range: range)
                ts.addAttribute(.foregroundColor, value: c(0x9B9B9B), range: range)
            }
        }

        // Inline spans.
        style(#"\*\*([^*\n]+)\*\*"#, text) { ts.addAttribute(.font, value: bold, range: $0) }
        style(#"(?<![*\w])\*(?![*\s])([^*\n]+?)\*(?![*\w])"#, text) { ts.addAttribute(.font, value: italic, range: $0) }
        style(#"`([^`\n]+)`"#, text) {
            ts.addAttribute(.font, value: code, range: $0)
            ts.addAttribute(.foregroundColor, value: c(0xCE9178), range: $0)
        }
        style(#"\[\[[^\]\n]+\]\]"#, text) { ts.addAttribute(.foregroundColor, value: c(0x9D7CFF), range: $0) }
        style(#"\[[^\]\n]+\]\([^)\s]+\)"#, text) { ts.addAttribute(.foregroundColor, value: c(0x4FA6ED), range: $0) }

        ts.endEditing()
    }

    private static func headingLevel(_ t: String) -> Int? {
        guard t.hasPrefix("#") else { return nil }
        let hashes = t.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), t.dropFirst(hashes).first == " " else { return nil }
        return min(hashes, 4)
    }

    private static func style(_ pattern: String, _ text: NSString, _ apply: (NSRange) -> Void) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        re.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { m, _, _ in
            if let r = m?.range { apply(r) }
        }
    }
}
#endif
