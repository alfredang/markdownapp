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
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = MarkdownStyler.body
        tv.textColor = fg
        tv.backgroundColor = bg
        tv.drawsBackground = true
        tv.insertionPointColor = NSColor(srgbRed: VSCode.termCaret.r, green: VSCode.termCaret.g, blue: VSCode.termCaret.b, alpha: 1)
        tv.textContainerInset = NSSize(width: 18, height: 18)
        tv.defaultParagraphStyle = MarkdownStyler.paragraph
        tv.typingAttributes = [.font: MarkdownStyler.body, .foregroundColor: fg, .paragraphStyle: MarkdownStyler.paragraph]
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.string = text
        context.coordinator.textView = tv
        context.coordinator.highlight()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
            context.coordinator.highlight()
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

        private var fgColor: NSColor {
            NSColor(srgbRed: VSCode.termFg.r, green: VSCode.termFg.g, blue: VSCode.termFg.b, alpha: 1)
        }

        /// Re-apply Live Preview styling, revealing syntax only on the caret's line.
        func highlight() {
            guard let tv = textView, let ts = tv.textStorage else { return }
            let active = (tv.string as NSString).lineRange(for: tv.selectedRange())
            MarkdownStyler.apply(to: ts, baseColor: fgColor, activeLine: active)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            highlight()
            detectSlash(tv)
        }

        // Reveal/hide markers as the caret moves between lines (Obsidian Live Preview).
        func textViewDidChangeSelection(_ notification: Notification) {
            highlight()
        }

        /// Obsidian-style list continuation: Return on a list/todo line starts the next item;
        /// Return on an empty item ends the list.
        func textView(_ tv: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) { return indent(tv, out: false) }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) { return indent(tv, out: true) }
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let ns = tv.string as NSString
            let sel = tv.selectedRange()
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            var line = ns.substring(with: lineRange)
            if line.hasSuffix("\n") { line = String(line.dropLast()) }
            guard let prefix = listPrefix(line) else { return false }

            let content = String(line.dropFirst(prefix.count))
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                // Empty item → remove the prefix to end the list.
                let r = NSRange(location: lineRange.location, length: (line as NSString).length)
                if tv.shouldChangeText(in: r, replacementString: "") {
                    tv.textStorage?.replaceCharacters(in: r, with: "")
                    tv.didChangeText()
                }
                return true
            }
            let insert = "\n" + nextPrefix(prefix)
            if tv.shouldChangeText(in: sel, replacementString: insert) {
                tv.textStorage?.replaceCharacters(in: sel, with: insert)
                tv.didChangeText()
                tv.setSelectedRange(NSRange(location: sel.location + (insert as NSString).length, length: 0))
            }
            return true
        }

        private func listPrefix(_ line: String) -> String? {
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            for pat in [#"^(\s*[-*+] \[[ xX]\] )"#, #"^(\s*[-*+] )"#, #"^(\s*\d+\. )"#, #"^(\s*>+ )"#] {
                if let re = try? NSRegularExpression(pattern: pat),
                   let m = re.firstMatch(in: line, range: full) {
                    return ns.substring(with: m.range(at: 1))
                }
            }
            return nil
        }

        // MARK: - Auto-pairing & indentation (Obsidian-style)
        private var bypass = false
        private static let autoClose: [String: String] = ["(": ")", "[": "]", "{": "}"]
        private static let wrap: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "*": "*", "_": "_", "`": "`"]
        private static let closers: Set<String> = [")", "]", "}", "\"", "`"]

        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            guard !bypass, let text = text else { return true }
            let ns = tv.string as NSString

            // Wrap the current selection: "[text]" / **text** etc.
            if range.length > 0, let close = Self.wrap[text] {
                let inner = ns.substring(with: range)
                edit(tv, range, text + inner + close)
                tv.setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: (inner as NSString).length))
                return false
            }
            // Skip over an existing closing char instead of inserting a duplicate.
            if range.length == 0, Self.closers.contains(text), range.location < ns.length,
               ns.substring(with: NSRange(location: range.location, length: 1)) == text {
                tv.setSelectedRange(NSRange(location: range.location + 1, length: 0))
                return false
            }
            // Auto-close brackets.
            if range.length == 0, let close = Self.autoClose[text] {
                edit(tv, range, text + close)
                tv.setSelectedRange(NSRange(location: range.location + 1, length: 0))
                return false
            }
            return true
        }

        private func edit(_ tv: NSTextView, _ range: NSRange, _ string: String) {
            bypass = true
            if tv.shouldChangeText(in: range, replacementString: string) {
                tv.textStorage?.replaceCharacters(in: range, with: string)
                tv.didChangeText()
            }
            bypass = false
        }

        /// Tab / Shift-Tab indents or outdents a list line by two spaces (Obsidian-style).
        private func indent(_ tv: NSTextView, out: Bool) -> Bool {
            let ns = tv.string as NSString
            let sel = tv.selectedRange()
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let line = ns.substring(with: lineRange)
            guard listPrefix(line.hasSuffix("\n") ? String(line.dropLast()) : line) != nil else { return false }
            if out {
                let strip = line.hasPrefix("  ") ? 2 : (line.hasPrefix(" ") ? 1 : 0)
                guard strip > 0 else { return true }
                edit(tv, NSRange(location: lineRange.location, length: strip), "")
                tv.setSelectedRange(NSRange(location: max(lineRange.location, sel.location - strip), length: 0))
            } else {
                edit(tv, NSRange(location: lineRange.location, length: 0), "  ")
                tv.setSelectedRange(NSRange(location: sel.location + 2, length: 0))
            }
            return true
        }

        private func nextPrefix(_ prefix: String) -> String {
            if prefix.contains("[") {   // checkbox → new unchecked item
                return prefix.replacingOccurrences(of: "[x]", with: "[ ]")
                             .replacingOccurrences(of: "[X]", with: "[ ]")
            }
            let ns = prefix as NSString
            if let re = try? NSRegularExpression(pattern: #"^(\s*)(\d+)(\. )$"#),
               let m = re.firstMatch(in: prefix, range: NSRange(location: 0, length: ns.length)) {
                let indent = ns.substring(with: m.range(at: 1))
                let n = Int(ns.substring(with: m.range(at: 2))) ?? 1
                return "\(indent)\(n + 1)\(ns.substring(with: m.range(at: 3)))"
            }
            return prefix   // bullets repeat as-is
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

    /// Comfortable, Obsidian-like line spacing.
    static let paragraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 6
        p.paragraphSpacing = 6
        return p
    }()

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

    static func apply(to ts: NSTextStorage?, baseColor: NSColor, activeLine: NSRange = NSRange(location: -1, length: 0)) {
        guard let ts = ts else { return }
        let text = ts.string as NSString
        let full = NSRange(location: 0, length: ts.length)
        ts.beginEditing()
        ts.setAttributes([.font: body, .foregroundColor: baseColor, .paragraphStyle: paragraph], range: full)

        // Per-line: headings and block quotes (hide the "### " prefix off the active line).
        text.enumerateSubstrings(in: full, options: .byLines) { sub, range, _, _ in
            guard let sub = sub else { return }
            let t = sub.trimmingCharacters(in: .whitespaces)
            let isActive = NSIntersectionRange(range, activeLine).length > 0 || range.location == activeLine.location
            if let lvl = headingLevel(t) {
                ts.addAttribute(.font, value: heading(lvl), range: range)
                ts.addAttribute(.foregroundColor, value: c(0xFFFFFF), range: range)
                if !isActive {
                    let leading = sub.prefix { $0 == " " }.count
                    let hashes = t.prefix { $0 == "#" }.count
                    hide(ts, NSRange(location: range.location, length: min(leading + hashes + 1, range.length)))
                }
            } else if t.hasPrefix(">") {
                ts.addAttribute(.font, value: italic, range: range)
                ts.addAttribute(.foregroundColor, value: c(0x9B9B9B), range: range)
            }
        }

        // Inline spans — style the inner text, hide the delimiters off the active line.
        inline(#"\*\*([^*\n]+)\*\*"#, text, ts, activeLine) { ts.addAttribute(.font, value: bold, range: $0) }
        inline(#"__([^_\n]+)__"#, text, ts, activeLine) { ts.addAttribute(.font, value: bold, range: $0) }
        inline(#"(?<![*\w])\*(?![*\s])([^*\n]+?)\*(?![*\w])"#, text, ts, activeLine) { ts.addAttribute(.font, value: italic, range: $0) }
        inline(#"(?<![_\w])_(?![_\s])([^_\n]+?)_(?![_\w])"#, text, ts, activeLine) { ts.addAttribute(.font, value: italic, range: $0) }
        inline(#"`([^`\n]+)`"#, text, ts, activeLine) {
            ts.addAttribute(.font, value: code, range: $0)
            ts.addAttribute(.foregroundColor, value: c(0xCE9178), range: $0)
        }
        inline(#"\[\[([^\]\n]+)\]\]"#, text, ts, activeLine) { ts.addAttribute(.foregroundColor, value: c(0x9D7CFF), range: $0) }
        link(text, ts, activeLine)

        ts.endEditing()
    }

    private static func headingLevel(_ t: String) -> Int? {
        guard t.hasPrefix("#") else { return nil }
        let hashes = t.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), t.dropFirst(hashes).first == " " else { return nil }
        return min(hashes, 4)
    }

    /// Make a marker range zero-width and invisible (revealed only on the active line).
    private static func hide(_ ts: NSTextStorage, _ r: NSRange) {
        guard r.location >= 0, r.location + r.length <= ts.length, r.length > 0 else { return }
        ts.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.01), range: r)
        ts.addAttribute(.foregroundColor, value: NSColor.clear, range: r)
    }

    private static func isActive(_ match: NSRange, _ text: NSString, _ activeLine: NSRange) -> Bool {
        guard activeLine.location >= 0 else { return false }
        let line = text.lineRange(for: match)
        return NSIntersectionRange(line, activeLine).length > 0 || line.location == activeLine.location
    }

    /// Style the inner capture group; hide the surrounding delimiters when off the active line.
    private static func inline(_ pattern: String, _ text: NSString, _ ts: NSTextStorage, _ activeLine: NSRange, _ style: (NSRange) -> Void) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        re.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 2 else { return }
            let match = m.range, inner = m.range(at: 1)
            style(inner)
            if !isActive(match, text, activeLine) {
                let leftLen = inner.location - match.location
                let rightLen = (match.location + match.length) - (inner.location + inner.length)
                if leftLen > 0 { hide(ts, NSRange(location: match.location, length: leftLen)) }
                if rightLen > 0 { hide(ts, NSRange(location: inner.location + inner.length, length: rightLen)) }
            }
        }
    }

    /// `[text](url)` — color the text, hide `[`, `]`, `(url)` off the active line.
    private static func link(_ text: NSString, _ ts: NSTextStorage, _ activeLine: NSRange) {
        guard let re = try? NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(([^)\s]+)\)"#) else { return }
        re.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 3 else { return }
            let match = m.range, label = m.range(at: 1)
            ts.addAttribute(.foregroundColor, value: c(0x4FA6ED), range: label)
            ts.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: label)
            if !isActive(match, text, activeLine) {
                hide(ts, NSRange(location: match.location, length: label.location - match.location))
                let afterStart = label.location + label.length
                hide(ts, NSRange(location: afterStart, length: (match.location + match.length) - afterStart))
            }
        }
    }
}
#endif
