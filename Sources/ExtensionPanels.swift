#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Wiki service (scaffolding)

/// Scaffolds and inspects a Karpathy-style LLM-maintained wiki inside the vault:
/// immutable `raw/` sources, an LLM-owned `wiki/`, and a `CLAUDE.md` schema.
enum WikiService {
    static func isInitialized(_ root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("wiki/index.md").path)
    }

    static func initialize(_ root: URL) {
        let fm = FileManager.default
        let dirs = ["wiki", "wiki/entities", "wiki/concepts", "raw"]
        for d in dirs {
            try? fm.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        write(root.appendingPathComponent("CLAUDE.md"), schema, overwrite: false)
        write(root.appendingPathComponent("wiki/index.md"), indexTemplate, overwrite: false)
        write(root.appendingPathComponent("wiki/log.md"), logTemplate, overwrite: false)
        write(root.appendingPathComponent("wiki/entities/.gitkeep"), "", overwrite: false)
        write(root.appendingPathComponent("wiki/concepts/.gitkeep"), "", overwrite: false)
        write(root.appendingPathComponent("raw/.gitkeep"), "", overwrite: false)
    }

    private static func write(_ url: URL, _ contents: String, overwrite: Bool) {
        if !overwrite && FileManager.default.fileExists(atPath: url.path) { return }
        try? contents.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static let schema = """
    # Wiki (LLM) — Maintenance Schema

    You maintain a persistent, LLM-curated wiki for this vault (the "Karpathy wiki" pattern).
    There are three layers:

    - `raw/` — immutable source documents. Never edit these.
    - `wiki/` — the wiki you own and keep current.
    - `CLAUDE.md` — this schema.

    ## Files
    - `wiki/index.md` — catalog of every wiki page, grouped by category, one line each. Update on every ingest.
    - `wiki/log.md` — append-only operations log. Never rewrite; only append `## [YYYY-MM-DD] op | summary`.
    - `wiki/entities/<name>.md` — one page per person/org/product.
    - `wiki/concepts/<topic>.md` — one page per concept/theme.

    ## Conventions
    - Cross-link pages with Obsidian wikilinks: `[[page_name]]`.
    - Each page starts with YAML frontmatter: `tags`, `updated`, `sources`.
    - Flag contradictions explicitly, citing the source.

    ## Operations
    - **Ingest** `<source>`: read it, extract entities & concepts, create/update ~10–15 pages,
      update `wiki/index.md`, append to `wiki/log.md`.
    - **Query** `<question>`: answer from wiki pages with `[[links]]`; file good answers as new pages.
    - **Lint**: report stale claims, orphan pages, contradictions, and missing cross-references.

    Use the `mdwiki` helper (see Tools/mdwiki) for deterministic file operations when available.
    """

    static let indexTemplate = """
    # Wiki Index

    The catalog of all wiki pages. Updated on every ingest.

    ## Entities
    _None yet._

    ## Concepts
    _None yet._
    """

    static let logTemplate = """
    # Wiki Log

    Append-only. Newest at the bottom.
    """
}

// MARK: - Extensions side bar (marketplace)

/// VS Code-style EXTENSIONS view: search + install / uninstall the curated catalog.
struct ExtensionsSidebar: View {
    @ObservedObject private var registry = ExtensionRegistry.shared
    @State private var query = ""

    private var filtered: [AppExtension] {
        guard !query.isEmpty else { return registry.catalog }
        return registry.catalog.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("EXTENSIONS")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(VSCode.muted)
                .padding(.horizontal, 12).frame(height: 35)
            Divider().overlay(VSCode.border)
            TextField("Search Extensions in Marketplace", text: $query)
                .textFieldStyle(.plain).font(.system(size: 12)).padding(6)
                .background(Color(hex: 0x3C3C3C), in: RoundedRectangle(cornerRadius: 4))
                .padding(8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { ext in
                        ExtensionRow(ext: ext, registry: registry)
                        Divider().overlay(VSCode.border)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(VSCode.sidebarBg)
    }
}

private struct ExtensionRow: View {
    let ext: AppExtension
    @ObservedObject var registry: ExtensionRegistry

    var body: some View {
        let installed = registry.isInstalled(ext.id)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ext.symbol)
                .font(.system(size: 26))
                .foregroundStyle(VSCode.accent)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(ext.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(VSCode.fg)
                    Spacer()
                    Text(ext.installs).font(.system(size: 10)).foregroundStyle(VSCode.muted)
                }
                Text(ext.summary).font(.system(size: 11)).foregroundStyle(VSCode.muted).lineLimit(3)
                Text(ext.publisher).font(.system(size: 10)).foregroundStyle(VSCode.muted)
                HStack(spacing: 6) {
                    if ext.comingSoon {
                        Text("Coming soon").font(.system(size: 11))
                            .foregroundStyle(VSCode.muted)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(VSCode.hoverBg, in: RoundedRectangle(cornerRadius: 4))
                    } else if installed {
                        if ext.hasPanel {
                            smallButton("Manage", prominent: true) {
                                NotificationCenter.default.post(name: .openExtension, object: ext.id)
                            }
                        }
                        smallButton("Uninstall") { registry.uninstall(ext.id) }
                    } else {
                        smallButton("Install", prominent: true) { registry.install(ext.id) }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func smallButton(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .medium))
                .foregroundStyle(prominent ? .white : VSCode.fg)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(prominent ? VSCode.accent : Color(hex: 0x3C3C3C), in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Wiki extension panel

struct WikiPanel: View {
    @EnvironmentObject var store: VaultStore
    var runInTerminal: (String) -> Void
    var onClose: () -> Void

    @State private var initialized = false
    @State private var question = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(icon: "books.vertical.fill", title: "Wiki (LLM)")

            Text("Turn this vault into a self-maintaining knowledge wiki. Drop sources into `raw/`, then let Claude Code read them and keep `wiki/` — entity & concept pages, `[[links]]`, the index, and the log — up to date.")
                .font(.system(size: 12)).foregroundStyle(VSCode.muted)

            if initialized {
                Label("Wiki is initialized in this vault.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(.green)
            } else {
                Button("Initialize Wiki in Vault") {
                    if let r = store.rootURL { WikiService.initialize(r); store.refresh(); initialized = true }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.rootURL == nil)
            }

            Divider()

            Text("Ingest").font(.system(size: 13, weight: .semibold))
            Text("Read the current note and integrate it into the wiki.").font(.system(size: 11)).foregroundStyle(VSCode.muted)
            Button("Ingest Current Note") { ingestCurrent() }
                .disabled(store.selectedFileURL == nil)

            Divider()

            Text("Ask the Wiki").font(.system(size: 13, weight: .semibold))
            HStack {
                TextField("Question…", text: $question).textFieldStyle(.roundedBorder)
                Button("Ask") { ask() }.disabled(question.isEmpty)
            }

            Divider()
            Button("Lint Wiki (health check)") { runInTerminal(lintCommand) }

            Spacer()
            HStack { Spacer(); Button("Close", action: onClose) }
        }
        .padding(20)
        .frame(width: 520, height: 520)
        .background(VSCode.editorBg)
        .onAppear { initialized = store.rootURL.map { WikiService.isInitialized($0) } ?? false }
    }

    private func header(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(VSCode.accent)
            Text(title).font(.system(size: 18, weight: .bold))
            Spacer()
        }
    }

    private func ingestCurrent() {
        guard let file = store.selectedFileURL else { return }
        let rel = relativePath(file)
        runInTerminal("claude \"Ingest the note '\(rel)' into the wiki per CLAUDE.md: extract entities and concepts, create or update the relevant wiki pages with [[links]], update wiki/index.md, and append a line to wiki/log.md.\"")
    }

    private func ask() {
        let q = question.replacingOccurrences(of: "\"", with: "\\\"")
        runInTerminal("claude \"Answer from the wiki per CLAUDE.md, citing [[pages]]: \(q)\"")
        question = ""
    }

    private var lintCommand: String {
        "claude \"Lint the wiki per CLAUDE.md: list stale claims, orphan pages, contradictions, and missing cross-references. Do not edit files, just report.\""
    }

    private func relativePath(_ url: URL) -> String {
        guard let root = store.rootURL else { return url.lastPathComponent }
        return url.path.replacingOccurrences(of: root.path + "/", with: "")
    }
}

// MARK: - GitHub extension panel

struct GitHubPanel: View {
    @EnvironmentObject var store: VaultStore
    var runInTerminal: (String) -> Void
    var onClose: () -> Void

    @State private var commitMessage = "Update vault"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 26)).foregroundStyle(VSCode.accent)
                Text("GitHub").font(.system(size: 18, weight: .bold))
                Spacer()
            }

            Text("Version your vault with Git and GitHub. These actions run in the terminal using the GitHub CLI (`gh`) and `git`, scoped to the vault folder.")
                .font(.system(size: 12)).foregroundStyle(VSCode.muted)

            Group {
                Text("Account").font(.system(size: 13, weight: .semibold))
                HStack {
                    Button("Sign in with GitHub") { runInTerminal("gh auth login") }
                    Button("Check Status") { runInTerminal("gh auth status") }
                }
            }
            Divider()
            Group {
                Text("Repository").font(.system(size: 13, weight: .semibold))
                Button("Initialize Git Repo") { runInTerminal("git init && git add -A") }
                HStack {
                    TextField("Commit message", text: $commitMessage).textFieldStyle(.roundedBorder)
                    Button("Commit") {
                        let m = commitMessage.replacingOccurrences(of: "\"", with: "\\\"")
                        runInTerminal("git add -A && git commit -m \"\(m)\"")
                    }
                }
                Button("Push to GitHub") { runInTerminal("git push") }
                Button("Create GitHub Repo (gh)") { runInTerminal("gh repo create --source=. --private --push") }
            }

            Spacer()
            HStack { Spacer(); Button("Close", action: onClose) }
        }
        .padding(20)
        .frame(width: 520, height: 480)
        .background(VSCode.editorBg)
    }
}

extension Notification.Name {
    static let openExtension = Notification.Name("openExtension")
}
#endif
