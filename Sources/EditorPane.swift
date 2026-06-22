#if os(macOS)
import SwiftUI

/// Center editor for the VS Code layout. Obsidian-style: render Markdown nicely (Preview),
/// show the raw source (Edit), or both side-by-side (Split). Autosaves on edit.
struct EditorPane: View {
    @EnvironmentObject var store: VaultStore
    let url: URL
    @Binding var mode: EditorMode

    @State private var text = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch mode {
            case .edit:
                rawEditor
            case .preview:
                preview
            case .split:
                HStack(spacing: 0) {
                    rawEditor
                    Divider().overlay(VSCode.border)
                    preview
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VSCode.editorBg)
        .task(id: url) {
            saveTask?.cancel()
            text = store.loadText(url)
        }
        .onDisappear { flush() }
    }

    private var rawEditor: some View {
        CodeEditorView(text: $text)
            .background(VSCode.editorBg)
            .onChange(of: text) { _, v in schedule(v) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var preview: some View {
        MarkdownPreview(markdown: text,
                        resolveImage: { store.resolveImageURL($0, relativeTo: url) },
                        onToggleCheckbox: toggleCheckbox)
    }

    /// Flip the Nth `- [ ]`/`- [x]` line in the source (Obsidian-style) and persist immediately.
    private func toggleCheckbox(_ index: Int) {
        var lines = text.components(separatedBy: "\n")
        var count = -1
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            let isUnchecked = trimmed.hasPrefix("- [ ]")
            let isChecked = trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]")
            guard isUnchecked || isChecked else { continue }
            count += 1
            if count == index {
                if isUnchecked {
                    lines[i] = lines[i].replacingOccurrences(of: "- [ ]", with: "- [x]")
                } else {
                    lines[i] = lines[i].replacingOccurrences(of: "- [x]", with: "- [ ]")
                                       .replacingOccurrences(of: "- [X]", with: "- [ ]")
                }
                break
            }
        }
        text = lines.joined(separator: "\n")
        store.save(text, to: url)
    }

    private func schedule(_ value: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            store.save(value, to: url)
        }
    }

    private func flush() {
        saveTask?.cancel()
        store.save(text, to: url)
    }
}

/// Compact dark segmented control for Edit / Split / Preview.
struct ModeToggle: View {
    @Binding var mode: EditorMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EditorMode.allCases) { m in
                Button { mode = m } label: {
                    Image(systemName: m.systemImage)
                        .font(.system(size: 11))
                        .foregroundStyle(mode == m ? VSCode.activeIcon : VSCode.muted)
                        .frame(width: 30, height: 22)
                        .background(mode == m ? VSCode.hoverBg : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(m.rawValue)
            }
        }
        .background(Color(hex: 0x2A2A2A), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(VSCode.border))
    }
}
#endif
