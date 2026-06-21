import SwiftUI
import UniformTypeIdentifiers

/// The main two-pane vault browser: file/folder tree on the left, editor/preview on the right.
struct VaultView: View {
    @EnvironmentObject var store: VaultStore
    @State private var showImporter = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    // Name-entry dialogs
    @State private var showNewFile = false
    @State private var showNewFolder = false
    @State private var newName = ""

    // Rename
    @State private var renameTarget: URL?
    @State private var renameText = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationTitle(store.vaultName)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        } detail: {
            detail
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { store.openVault(at: url) }
        }
        .task { store.restoreVaultIfNeeded() }
        // Bridge macOS menu commands
        .onChange(of: store.openVaultRequested) { _, v in if v { showImporter = true; store.openVaultRequested = false } }
        .onChange(of: store.newFileRequested) { _, v in if v { startNewFile(); store.newFileRequested = false } }
        // New file / folder dialogs
        .alert("New Markdown File", isPresented: $showNewFile) {
            TextField("Name", text: $newName)
            Button("Create") { store.createFile(named: newName) }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Created in \(store.targetDirectory()?.lastPathComponent ?? store.vaultName)") }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newName)
            Button("Create") { store.createFolder(named: newName) }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Rename", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let t = renameTarget { store.rename(t, to: renameText) }; renameTarget = nil }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
    }

    // MARK: - Sidebar
    @ViewBuilder
    private var sidebar: some View {
        if store.rootNode == nil {
            emptyVault
        } else {
            List(selection: $store.selectedFileURL) {
                if let children = store.rootNode?.children {
                    if children.isEmpty {
                        Text("This vault is empty.\nUse + to create a note.")
                            .font(.callout).foregroundStyle(Theme.mutedInk)
                    }
                    OutlineGroup(children, id: \.id, children: \.children) { node in
                        nodeLabel(node)
                    }
                }
            }
            .listStyle(.sidebar)
            .toolbar { sidebarToolbar }
        }
    }

    @ViewBuilder
    private func nodeLabel(_ node: FileNode) -> some View {
        if node.isDirectory {
            Label(node.name, systemImage: node.systemImage)
                .foregroundStyle(Theme.accent)
                .contextMenu { nodeMenu(node) }
        } else {
            Label(node.name, systemImage: node.systemImage)
                .tag(node.url)
                .contextMenu { nodeMenu(node) }
        }
    }

    @ViewBuilder
    private func nodeMenu(_ node: FileNode) -> some View {
        if node.isDirectory {
            Button { store.selectedFileURL = node.url; startNewFile() } label: { Label("New File Here", systemImage: "doc.badge.plus") }
            Button { store.selectedFileURL = node.url; startNewFolder() } label: { Label("New Folder Here", systemImage: "folder.badge.plus") }
            Divider()
        }
        Button { renameTarget = node.url; renameText = node.name } label: { Label("Rename", systemImage: "pencil") }
        Button(role: .destructive) { store.delete(node.url) } label: { Label("Delete", systemImage: "trash") }
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button { startNewFile() } label: { Label("New File", systemImage: "doc.badge.plus") }
                Button { startNewFolder() } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                Divider()
                Button { showImporter = true } label: { Label("Open Vault…", systemImage: "folder") }
                Button { store.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    private var emptyVault: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 52))
                .foregroundStyle(Theme.accent)
            Text("Open a Vault")
                .font(.title2.bold())
            Text("Choose any local folder of Markdown files — fully compatible with your Obsidian vault.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.mutedInk)
                .frame(maxWidth: 320)
            Button {
                showImporter = true
            } label: {
                Label("Open Folder…", systemImage: "folder")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)

            Button {
                store.openSampleVault()
            } label: {
                Label("Open Sample Vault", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Detail
    @ViewBuilder
    private var detail: some View {
        if let url = store.selectedFileURL {
            let node = FileNode(url: url, name: url.lastPathComponent,
                                isDirectory: false, children: nil)
            if node.isEditable {
                MarkdownEditorView(url: url)
                    .id(url)
            } else if node.isImage {
                ImageFileView(url: url)
            } else {
                ContentUnavailableView("Unsupported File",
                                       systemImage: "doc",
                                       description: Text(url.lastPathComponent))
            }
        } else {
            ContentUnavailableView("No File Selected",
                                   systemImage: "doc.text",
                                   description: Text("Pick a note from the sidebar, or create a new one."))
        }
    }

    // MARK: - Dialog launchers
    private func startNewFile() { newName = "Untitled"; showNewFile = true }
    private func startNewFolder() { newName = "New Folder"; showNewFolder = true }
}

/// Simple full-bleed viewer for image attachments selected in the tree.
struct ImageFileView: View {
    let url: URL
    var body: some View {
        Group {
            if let data = try? Data(contentsOf: url), let img = Image(platformData: data) {
                img.resizable().scaledToFit().padding()
            } else {
                ContentUnavailableView("Cannot Preview Image", systemImage: "photo")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle(url.lastPathComponent)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
