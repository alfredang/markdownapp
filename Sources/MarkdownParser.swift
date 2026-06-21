import Foundation

/// A renderable block of markdown.
enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulleted([String])
    case numbered([String])
    case checklist([(done: Bool, text: String)])
    case code(language: String, code: String)
    case quote(String)
    case table(headers: [String], rows: [[String]])
    case image(alt: String, src: String)
    case rule
}

/// A small, dependency-free GFM-flavoured block parser. Good enough for live preview of
/// Obsidian/Bear notes: headings, lists, checklists, fenced code, block-quotes, pipe tables,
/// images (`![alt](src)` and Obsidian `![[embed]]`), and horizontal rules.
enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        var para: [String] = []

        func flushParagraph() {
            if !para.isEmpty {
                blocks.append(.paragraph(para.joined(separator: "\n")))
                para.removeAll()
            }
        }

        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block
            if t.hasPrefix("```") {
                flushParagraph()
                let lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1 // closing fence
                blocks.append(.code(language: lang, code: code.joined(separator: "\n")))
                continue
            }

            if t.isEmpty { flushParagraph(); i += 1; continue }

            if let h = headingMatch(t) {
                flushParagraph(); blocks.append(.heading(level: h.0, text: h.1)); i += 1; continue
            }

            if t == "---" || t == "***" || t == "___" {
                flushParagraph(); blocks.append(.rule); i += 1; continue
            }

            // Pipe table: header row followed by a separator row
            if line.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flushParagraph()
                let headers = splitRow(line)
                var rows: [[String]] = []
                i += 2
                while i < lines.count, lines[i].contains("|"),
                      !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(splitRow(lines[i])); i += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            if let img = imageMatch(t) {
                flushParagraph(); blocks.append(.image(alt: img.0, src: img.1)); i += 1; continue
            }

            if t.hasPrefix(">") {
                flushParagraph()
                var q: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard l.hasPrefix(">") else { break }
                    q.append(String(l.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(q.joined(separator: "\n")))
                continue
            }

            if checklistItem(t) != nil {
                flushParagraph()
                var items: [(Bool, String)] = []
                while i < lines.count, let c = checklistItem(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(c); i += 1
                }
                blocks.append(.checklist(items.map { (done: $0.0, text: $0.1) }))
                continue
            }

            if isBullet(t) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isBullet(l) else { break }
                    items.append(String(l.dropFirst(2)))
                    i += 1
                }
                blocks.append(.bulleted(items))
                continue
            }

            if numberedContent(t) != nil {
                flushParagraph()
                var items: [String] = []
                while i < lines.count, let c = numberedContent(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(c); i += 1
                }
                blocks.append(.numbered(items))
                continue
            }

            para.append(t)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    // MARK: - Helpers
    private static func headingMatch(_ s: String) -> (Int, String)? {
        var level = 0
        var idx = s.startIndex
        while idx < s.endIndex, s[idx] == "#" { level += 1; idx = s.index(after: idx) }
        guard level > 0, level <= 6, idx < s.endIndex, s[idx] == " " else { return nil }
        return (level, String(s[s.index(after: idx)...]).trimmingCharacters(in: .whitespaces))
    }

    private static func isBullet(_ t: String) -> Bool {
        t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ")
    }

    private static func numberedContent(_ t: String) -> String? {
        guard let dot = t.firstIndex(of: ".") else { return nil }
        let num = t[t.startIndex..<dot]
        guard !num.isEmpty, num.allSatisfy(\.isNumber) else { return nil }
        let after = t.index(after: dot)
        guard after < t.endIndex, t[after] == " " else { return nil }
        return String(t[t.index(after: after)...])
    }

    private static func checklistItem(_ t: String) -> (Bool, String)? {
        for (prefix, done) in [("- [ ]", false), ("- [x]", true), ("- [X]", true)] {
            if t.hasPrefix(prefix) {
                return (done, String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private static func isTableSeparator(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") else { return false }
        return t.allSatisfy { "-:| ".contains($0) }
    }

    private static func splitRow(_ s: String) -> [String] {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func imageMatch(_ s: String) -> (String, String)? {
        // Obsidian embed: ![[file.png]]
        if s.hasPrefix("![[") && s.hasSuffix("]]") {
            let inner = String(s.dropFirst(3).dropLast(2))
            return (inner, inner)
        }
        // Markdown image: ![alt](src)
        guard s.hasPrefix("!["), let close = s.firstIndex(of: "]") else { return nil }
        let afterClose = s.index(after: close)
        guard afterClose < s.endIndex, s[afterClose] == "(", s.hasSuffix(")") else { return nil }
        let alt = String(s[s.index(s.startIndex, offsetBy: 2)..<close])
        let src = String(s[s.index(afterClose, offsetBy: 1)..<s.index(before: s.endIndex)])
        return (alt, src)
    }
}
