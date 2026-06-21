import SwiftUI

enum EditorMode: String, CaseIterable, Identifiable {
    case edit = "Edit"
    case split = "Split"
    case preview = "Preview"
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .edit: return "square.and.pencil"
        case .split: return "rectangle.split.2x1"
        case .preview: return "eye"
        }
    }
}

/// Editor + live preview for a single markdown/text file. Autosaves on edit.
struct MarkdownEditorView: View {
    @EnvironmentObject var store: VaultStore
    let url: URL

    @State private var text: String = ""
    @State private var mode: EditorMode = .split
    @State private var saveTask: Task<Void, Never>?
    @Environment(\.horizontalSizeClass) private var hSize

    private var isWide: Bool { hSize != .compact }

    var body: some View {
        Group {
            switch effectiveMode {
            case .edit:
                editor
            case .preview:
                preview
            case .split:
                HStack(spacing: 0) {
                    editor
                    Divider()
                    preview
                }
            }
        }
        .navigationTitle(url.deletingPathExtension().lastPathComponent)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .task(id: url) {
            saveTask?.cancel()
            text = store.loadText(url)
        }
        .onDisappear { flushSave() }
    }

    /// On compact widths Split collapses to Edit (panes too narrow side-by-side).
    private var effectiveMode: EditorMode {
        (mode == .split && !isWide) ? .edit : mode
    }

    private var editor: some View {
        InsertableTextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .onChange(of: text) { _, newValue in scheduleSave(newValue) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
    }

    private var preview: some View {
        MarkdownPreview(markdown: text) { src in
            store.resolveImageURL(src, relativeTo: url)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button { insert(wrap: "**") } label: { Label("Bold", systemImage: "bold") }
                Button { insert(wrap: "*") } label: { Label("Italic", systemImage: "italic") }
                Button { insertLinePrefix("# ") } label: { Label("Heading", systemImage: "textformat.size") }
                Button { insertLinePrefix("- ") } label: { Label("Bullet List", systemImage: "list.bullet") }
                Button { insertLinePrefix("- [ ] ") } label: { Label("Checklist", systemImage: "checklist") }
                Divider()
                Button { insert(snippet: Snippets.table) } label: { Label("Table", systemImage: "tablecells") }
                Button { insert(snippet: Snippets.image) } label: { Label("Image", systemImage: "photo") }
                Button { insert(snippet: Snippets.codeBlock) } label: { Label("Code Block", systemImage: "curlybraces") }
            } label: {
                Label("Insert", systemImage: "plus.circle")
            }

            Picker("View", selection: $mode) {
                ForEach(EditorMode.allCases) { m in
                    Image(systemName: m.systemImage).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
        }
    }

    // MARK: - Saving
    private func scheduleSave(_ value: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            store.save(value, to: url)
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        store.save(text, to: url)
    }

    // MARK: - Insert helpers (append-based; simple and reliable cross-platform)
    private func insert(snippet: String) {
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += snippet
    }
    private func insert(wrap: String) { insert(snippet: "\(wrap)text\(wrap)") }
    private func insertLinePrefix(_ prefix: String) { insert(snippet: "\(prefix)") }

    private enum Snippets {
        static let table = """
        | Name | Status | Notes |
        | --- | --- | --- |
        | Item 1 | Done | First note |
        | Item 2 | In progress | Second note |
        """
        static let image = "![alt text](image.png)"
        static let codeBlock = "```swift\n// code\n```"
    }
}

/// A plain cross-platform multiline text editor wrapper (keeps a single call-site
/// in case we later swap in a richer editor with cursor-aware insertion).
private struct InsertableTextEditor: View {
    @Binding var text: String
    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .padding(8)
            #if os(iOS)
            .autocorrectionDisabled(false)
            #endif
    }
}
