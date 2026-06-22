import SwiftUI

/// Renders parsed markdown blocks as native SwiftUI — Bear-style images and Notion-style tables.
struct MarkdownPreview: View {
    let markdown: String
    /// Resolve an image reference (`src`) to an on-disk URL relative to the current file.
    var resolveImage: (String) -> URL?
    /// Called with the document-wide checkbox index when a checklist box is tapped
    /// (Obsidian-style live toggling). When nil, checkboxes are read-only.
    var onToggleCheckbox: ((Int) -> Void)? = nil

    private var blocks: [MarkdownBlock] { MarkdownParser.parse(markdown) }

    /// Each block paired with the running count of checkboxes that precede it, so a tapped
    /// box maps back to the Nth `- [ ]` line in the source.
    private var renderItems: [(block: MarkdownBlock, checkboxStart: Int)] {
        var result: [(MarkdownBlock, Int)] = []
        var cb = 0
        for b in blocks {
            result.append((b, cb))
            if case let .checklist(items) = b { cb += items.count }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(renderItems.enumerated()), id: \.offset) { _, item in
                    view(for: item.block, checkboxStart: item.checkboxStart)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .background(Theme.background)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock, checkboxStart: Int = 0) -> some View {
        switch block {
        case let .heading(level, text):
            inline(text).font(headingFont(level)).bold().padding(.top, level <= 2 ? 6 : 2)

        case let .paragraph(text):
            inline(text)

        case let .bulleted(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.indices, id: \.self) { idx in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Theme.accent)
                        inline(items[idx])
                    }
                }
            }

        case let .numbered(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.indices, id: \.self) { idx in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(idx + 1).").foregroundStyle(Theme.accent).monospacedDigit()
                        inline(items[idx])
                    }
                }
            }

        case let .checklist(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.indices, id: \.self) { idx in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Button {
                            onToggleCheckbox?(checkboxStart + idx)
                        } label: {
                            Image(systemName: items[idx].done ? "checkmark.square.fill" : "square")
                                .foregroundStyle(items[idx].done ? Theme.accent : Theme.mutedInk)
                        }
                        .buttonStyle(.plain)
                        .disabled(onToggleCheckbox == nil)
                        inline(items[idx].text)
                            .strikethrough(items[idx].done, color: Theme.mutedInk)
                            .foregroundStyle(items[idx].done ? Theme.mutedInk : Theme.ink)
                    }
                }
            }

        case let .code(_, code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        case let .quote(text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.accent).frame(width: 4)
                inline(text).foregroundStyle(Theme.mutedInk).italic()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)

        case let .table(headers, rows):
            TableBlock(headers: headers, rows: rows)

        case let .image(alt, src):
            imageView(alt: alt, src: src)

        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func imageView(alt: String, src: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if src.hasPrefix("http"), let url = URL(string: src) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFit()
                    } else if phase.error != nil {
                        imagePlaceholder(src)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if let url = resolveImage(src),
                      let data = try? Data(contentsOf: url),
                      let img = Image(platformData: data) {
                img.resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                imagePlaceholder(src)
            }
            if !alt.isEmpty, alt != src {
                Text(alt).font(.caption).foregroundStyle(Theme.mutedInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func imagePlaceholder(_ src: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "photo").foregroundStyle(Theme.mutedInk)
            Text("Missing image: \(src)").font(.caption).foregroundStyle(Theme.mutedInk)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title
        case 3: return .title2
        case 4: return .title3
        case 5: return .headline
        default: return .subheadline
        }
    }

    /// Render inline markdown (bold/italic/links/code) per line via AttributedString.
    private func inline(_ text: String) -> Text {
        let lines = text.components(separatedBy: "\n")
        var result = Text("")
        for (idx, raw) in lines.enumerated() {
            // Strip Obsidian wiki-link brackets for readability: [[Note]] -> Note
            var line = raw.replacingOccurrences(of: "[[", with: "")
            line = line.replacingOccurrences(of: "]]", with: "")
            let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            let attr = (try? AttributedString(markdown: line, options: opts)) ?? AttributedString(line)
            result = result + Text(attr)
            if idx < lines.count - 1 { result = result + Text("\n") }
        }
        return result
    }
}

/// Notion-style table: shaded header, hairline grid, equal-width flexible columns.
private struct TableBlock: View {
    let headers: [String]
    let rows: [[String]]

    private var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            row(cells: headers, isHeader: true)
            ForEach(rows.indices, id: \.self) { r in
                Divider()
                row(cells: rows[r], isHeader: false)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
        .frame(maxWidth: .infinity)
    }

    private func row(cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { c in
                let value = c < cells.count ? cells[c] : ""
                Text(value)
                    .font(isHeader ? .subheadline.bold() : .subheadline)
                    .foregroundStyle(isHeader ? Theme.ink : Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .overlay(alignment: .leading) {
                        if c > 0 { Divider() }
                    }
            }
        }
        .background(isHeader ? Theme.surface : Color.clear)
    }
}
