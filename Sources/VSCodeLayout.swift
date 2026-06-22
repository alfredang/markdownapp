#if os(macOS)
import SwiftUI
import AppKit

/// The full VS Code-style desktop shell:
/// Activity bar · collapsible Explorer/Search side bar · editor · collapsible terminal panel.
struct VSCodeLayout: View {
    @EnvironmentObject var store: VaultStore
    @StateObject private var terminals = TerminalController()

    @State private var activity: ActivityItem = .explorer
    @State private var sidebarVisible = true
    @State private var terminalVisible = false

    @State private var sidebarWidth: CGFloat = 260
    @State private var terminalWidth: CGFloat = 520
    @State private var dragStartSidebar: CGFloat?
    @State private var dragStartTerminal: CGFloat?

    @State private var showSettings = false
    @State private var showAbout = false
    @State private var editorMode: EditorMode = .edit   // Live Preview (editable, styled)
    @State private var showQuickOpen = false
    @State private var activeExtension: String?
    @AppStorage("editor.multipleTabs") private var multipleTabs = true
    @State private var openTabs: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                ActivityBar(selection: $activity,
                            sidebarVisible: $sidebarVisible,
                            onSettings: { showSettings = true })

                if sidebarVisible {
                    sidebar
                        .frame(width: sidebarWidth)
                    DragDivider(onChanged: { dx in
                        let start = dragStartSidebar ?? sidebarWidth
                        if dragStartSidebar == nil { dragStartSidebar = start }
                        sidebarWidth = min(560, max(170, start + dx))
                    }, onEnded: { dragStartSidebar = nil })
                }

                editorArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if terminalVisible {
                    DragDivider(onChanged: { dx in
                        let start = dragStartTerminal ?? terminalWidth
                        if dragStartTerminal == nil { dragStartTerminal = start }
                        terminalWidth = min(1100, max(280, start - dx))
                    }, onEnded: { dragStartTerminal = nil })
                    TerminalPanel(controller: terminals,
                                  directory: store.rootURL?.path,
                                  onClose: { terminalVisible = false })
                        .frame(width: terminalWidth)
                }
            }
            statusBar
        }
        .background(VSCode.editorBg)
        .background(WindowAccessor())
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .overlay {
            if showQuickOpen {
                QuickOpenPalette(isPresented: $showQuickOpen) { url in
                    store.selectedFileURL = url
                }
            }
        }
        .task { store.restoreVaultIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTerminal)) { _ in
            terminalVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            sidebarVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTerminal)) { _ in
            terminalVisible = true
            terminals.newTerminal(directory: store.rootURL?.path ?? NSHomeDirectory())
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTerminalAt)) { note in
            if let path = note.object as? String {
                terminalVisible = true
                terminals.newTerminal(directory: path)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickOpen)) { _ in
            showQuickOpen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openExtension)) { note in
            activeExtension = note.object as? String
        }
        .onChange(of: store.selectedFileURL) { _, url in openTab(url) }
        .onChange(of: multipleTabs) { _, multi in
            if !multi { openTabs = store.selectedFileURL.map { [$0] } ?? [] }
        }
        .sheet(isPresented: $showSettings) { sheet { SettingsView() } }
        .sheet(isPresented: $showAbout) { sheet { AboutView() } }
        .sheet(item: Binding(get: { activeExtension.map { IdentifiedString($0) } },
                             set: { activeExtension = $0?.value })) { item in
            switch item.value {
            case "wiki-llm":
                WikiPanel(runInTerminal: runInTerminal, onClose: { activeExtension = nil })
            case "github":
                GitHubPanel(runInTerminal: runInTerminal, onClose: { activeExtension = nil })
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Side bar content
    @ViewBuilder
    private var sidebar: some View {
        switch activity {
        case .explorer:   ExplorerSidebar()
        case .search:     SearchSidebar()
        case .extensions: ExtensionsSidebar()
        }
    }

    private func runInTerminal(_ command: String) {
        terminalVisible = true
        terminals.newTerminal(directory: store.rootURL?.path ?? NSHomeDirectory(), run: command)
    }

    // MARK: - Editor area
    private var displayedTabs: [URL] {
        multipleTabs ? openTabs : (store.selectedFileURL.map { [$0] } ?? [])
    }

    private func openTab(_ url: URL?) {
        guard let url else { return }
        if multipleTabs {
            if !openTabs.contains(url) { openTabs.append(url) }
        } else {
            openTabs = [url]
        }
    }

    private func closeTab(_ url: URL) {
        openTabs.removeAll { $0 == url }
        if store.selectedFileURL == url { store.selectedFileURL = openTabs.last }
    }

    private var editorArea: some View {
        VStack(spacing: 0) {
            if !displayedTabs.isEmpty {
                editorTabBar
                Divider().overlay(VSCode.border)
            }
            Group {
                if let url = store.selectedFileURL {
                    let node = FileNode(url: url, name: url.lastPathComponent, isDirectory: false, children: nil)
                    if node.isEditable {
                        EditorPane(url: url, mode: $editorMode).id(url)
                    } else if node.isImage {
                        ImageFileView(url: url)
                    } else {
                        welcome
                    }
                } else {
                    welcome
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(VSCode.editorBg)
    }

    @ViewBuilder
    private var editorTabBar: some View {
        let isEditable = store.selectedFileURL.map {
            FileNode.editableExtensions.contains($0.pathExtension.lowercased())
        } ?? false
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(displayedTabs, id: \.self) { url in
                        editorTab(url)
                    }
                }
            }
            Spacer(minLength: 8)
            if isEditable {
                ModeToggle(mode: $editorMode).padding(.trailing, 10)
            }
        }
        .frame(height: 35)
        .background(VSCode.tabBarBg)
    }

    private func editorTab(_ url: URL) -> some View {
        let active = store.selectedFileURL == url
        return HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 11)).foregroundStyle(Color(hex: 0x6FB3D2))
            Text(url.lastPathComponent)
                .font(.system(size: 12))
                .foregroundStyle(active ? VSCode.fg : VSCode.muted)
                .lineLimit(1)
            Button { closeTab(url) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(VSCode.muted).frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 35)
        .background(active ? VSCode.tabActiveBg : Color.clear)
        .overlay(alignment: .top) { Rectangle().fill(active ? VSCode.accent : Color.clear).frame(height: 1) }
        .overlay(alignment: .trailing) { Divider().overlay(VSCode.border) }
        .contentShape(Rectangle())
        .onTapGesture { store.selectedFileURL = url }
    }

    /// VS Code-style title bar: traffic-light gap · centered command/search bar · layout toggles.
    private var topBar: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 72)          // space for the traffic lights
            Spacer(minLength: 8)
            commandCenter
            Spacer(minLength: 8)
            layoutToggleButtons
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(VSCode.activityBg)
        .overlay(alignment: .bottom) { Rectangle().fill(VSCode.border).frame(height: 1) }
    }

    private var commandCenter: some View {
        Button { showQuickOpen = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(VSCode.muted)
                Text(store.vaultName).font(.system(size: 12)).foregroundStyle(VSCode.fg)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .frame(maxWidth: 520)
            .background(VSCode.editorBg, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(VSCode.border))
        }
        .buttonStyle(.plain)
        .help("Search Files (⌘P)")
    }

    private var layoutToggleButtons: some View {
        HStack(spacing: 2) {
            topToggle("sidebar.leading", on: sidebarVisible, help: "Toggle Primary Side Bar (⌘B)") {
                sidebarVisible.toggle()
            }
            topToggle("sidebar.trailing", on: terminalVisible, help: "Toggle Terminal Panel (⌃`)") {
                toggleTerminalPanel()
            }
        }
    }

    private func topToggle(_ icon: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(on ? VSCode.activeIcon : VSCode.muted)
                .frame(width: 30, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func toggleTerminalPanel() {
        if !terminalVisible && terminals.sessions.isEmpty {
            terminals.newTerminal(directory: store.rootURL?.path ?? NSHomeDirectory())
        }
        terminalVisible.toggle()
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 56)).foregroundStyle(VSCode.muted.opacity(0.4))
            Text("Select a file in the Explorer to start editing")
                .font(.system(size: 13)).foregroundStyle(VSCode.muted)
            shortcut("Toggle Terminal", "⌃`")
            shortcut("Toggle Side Bar", "⌘B")
            shortcut("New Terminal", "⌃⇧`")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VSCode.editorBg)
    }

    private func shortcut(_ name: String, _ keys: String) -> some View {
        HStack(spacing: 12) {
            Text(name).font(.system(size: 12)).foregroundStyle(VSCode.muted)
            Text(keys).font(.system(size: 12, design: .monospaced)).foregroundStyle(VSCode.fg)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(VSCode.hoverBg, in: RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Status bar
    private var statusBar: some View {
        HStack(spacing: 12) {
            Label(store.vaultName, systemImage: "folder")
                .font(.system(size: 11)).foregroundStyle(.white)
            Spacer()
            Button {
                terminalVisible = true
                terminals.newTerminal(directory: store.rootURL?.path ?? NSHomeDirectory())
            } label: {
                Label("Terminal", systemImage: "terminal").font(.system(size: 11)).foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Text("Markdown").font(.system(size: 11)).foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(VSCode.accent)
    }

    @ViewBuilder
    private func sheet<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(minWidth: 460, minHeight: 420)
    }
}

/// A thin, draggable divider that resizes an adjacent panel (VS Code style).
/// `onChanged` receives the cumulative horizontal drag offset from the gesture start.
private struct DragDivider: View {
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? VSCode.accent : VSCode.border)
            .frame(width: hovering ? 2 : 1)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 3)            // widen the hit target to ~7pt
            .contentShape(Rectangle())
            .onHover { h in
                hovering = h
                if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                // Track in GLOBAL space: the divider itself shifts as the panel resizes,
                // so a local translation would feed back on itself and the drag wouldn't work.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in onChanged(value.translation.width) }
                    .onEnded { _ in onEnded() }
            )
    }
}

/// ⌘P quick-open palette: fuzzy filename filter over the vault, floating from the top.
private struct QuickOpenPalette: View {
    @EnvironmentObject var store: VaultStore
    @Binding var isPresented: Bool
    var onOpen: (URL) -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }
            VStack(spacing: 0) {
                TextField("Search files by name", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(10)
                    .focused($focused)
                    .onSubmit { if let first = results.first { open(first) } }
                Divider().overlay(VSCode.border)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results, id: \.self) { url in
                            Button { open(url) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(Color(hex: 0x6FB3D2))
                                    Text(url.lastPathComponent).font(.system(size: 13)).foregroundStyle(VSCode.fg)
                                    Spacer()
                                    Text(relativePath(url)).font(.system(size: 11)).foregroundStyle(VSCode.muted).lineLimit(1)
                                }
                                .padding(.horizontal, 12).frame(height: 26).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            .frame(width: 560)
            .background(Color(hex: 0x252526), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(VSCode.border))
            .shadow(radius: 24, y: 8)
            .padding(.top, 52)
        }
        .onAppear { focused = true }
        .onExitCommand { isPresented = false }
    }

    private func open(_ url: URL) { onOpen(url); isPresented = false }

    private func relativePath(_ url: URL) -> String {
        guard let root = store.rootURL else { return "" }
        return url.deletingLastPathComponent().path.replacingOccurrences(of: root.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var results: [URL] {
        guard let root = store.rootURL else { return [] }
        var out: [URL] = []
        if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let u as URL in en {
                guard FileNode.editableExtensions.contains(u.pathExtension.lowercased()) else { continue }
                if query.isEmpty || u.lastPathComponent.localizedCaseInsensitiveContains(query) {
                    out.append(u)
                    if out.count >= 200 { break }
                }
            }
        }
        return out
    }
}

/// Minimal VS Code-style search side bar (in-vault filename filter).
private struct SearchSidebar: View {
    @EnvironmentObject var store: VaultStore
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SEARCH")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(VSCode.muted)
                .padding(.horizontal, 12).frame(height: 35)
            Divider().overlay(VSCode.border)
            TextField("Search files", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(6)
                .background(Color(hex: 0x3C3C3C), in: RoundedRectangle(cornerRadius: 4))
                .padding(8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(matches, id: \.self) { url in
                        Button { store.selectedFileURL = url } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(Color(hex: 0x6FB3D2))
                                Text(url.lastPathComponent).font(.system(size: 12)).foregroundStyle(VSCode.fg).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 12).frame(height: 22).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(VSCode.sidebarBg)
    }

    private var matches: [URL] {
        guard !query.isEmpty, let root = store.rootURL else { return [] }
        var out: [URL] = []
        if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let u as URL in en where u.lastPathComponent.localizedCaseInsensitiveContains(query) {
                if FileNode.editableExtensions.contains(u.pathExtension.lowercased()) { out.append(u) }
                if out.count >= 200 { break }
            }
        }
        return out
    }
}

/// Makes the window title bar transparent and full-size so our custom top bar shares the
/// same row as the traffic-light buttons (VS Code style).
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            // Must stay false: when true, AppKit swallows drags on "background" views
            // (like the resize dividers) to move the window. The title bar still moves it.
            w.isMovableByWindowBackground = false
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Lightweight Identifiable wrapper so a String can drive `.sheet(item:)`.
struct IdentifiedString: Identifiable {
    let value: String
    var id: String { value }
    init(_ value: String) { self.value = value }
}

extension Notification.Name {
    static let toggleTerminal = Notification.Name("toggleTerminal")
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let newTerminal = Notification.Name("newTerminal")
    static let quickOpen = Notification.Name("quickOpen")
}
#endif
