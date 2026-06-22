import SwiftUI
import UniformTypeIdentifiers

/// Owns the currently-open Obsidian-compatible vault (a local folder), its file tree,
/// the selected file, and all file-system CRUD. Persists the vault via a security-scoped
/// bookmark so it re-opens on next launch.
@MainActor
final class VaultStore: ObservableObject {
    @Published var rootURL: URL?
    @Published var rootNode: FileNode?
    @Published var selectedFileURL: URL?

    /// Toggles wired to menu commands / toolbar on macOS.
    @Published var openVaultRequested = false
    @Published var newFileRequested = false

    @Published var showHiddenFiles = false {
        didSet { UserDefaults.standard.set(showHiddenFiles, forKey: Keys.showHidden); refresh() }
    }

    private enum Keys {
        static let bookmark = "vault.bookmark"
        static let showHidden = "settings.showHidden"
        static let onboarded = "vault.onboarded"
    }

    private var accessing: URL?

    init() {
        showHiddenFiles = UserDefaults.standard.bool(forKey: Keys.showHidden)
    }

    // MARK: - Menu bridges
    func requestOpenVault() { openVaultRequested = true }
    func requestNewFile() { newFileRequested = true }

    // MARK: - Opening / restoring a vault
    func openVault(at url: URL) {
        stopAccessing()
        // Non-sandboxed build: a scoped call isn't required, but harmless if it succeeds.
        if url.startAccessingSecurityScopedResource() {
            accessing = url
        }
        rootURL = url
        saveBookmark(for: url)
        refresh()
    }

    /// Copy the bundled sample vault into the app's Documents directory (writable, no
    /// security scope needed) and open it. Great for first-run and trying the app.
    func openSampleVault() {
        guard let bundled = Bundle.main.url(forResource: "SampleVault", withExtension: nil) else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dest = docs.appendingPathComponent("Sample Vault", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.copyItem(at: bundled, to: dest)
        }
        stopAccessing()
        rootURL = dest
        saveBookmark(for: dest)
        refresh()
        selectedFileURL = dest.appendingPathComponent("Welcome.md")
    }

    func restoreVaultIfNeeded() {
        guard rootURL == nil else { return }
        // First-ever launch with no saved vault: seed the sample vault for onboarding.
        if UserDefaults.standard.data(forKey: Keys.bookmark) == nil {
            if !UserDefaults.standard.bool(forKey: Keys.onboarded) {
                UserDefaults.standard.set(true, forKey: Keys.onboarded)
                openSampleVault()
            }
            return
        }
        guard let data = UserDefaults.standard.data(forKey: Keys.bookmark) else { return }
        var stale = false
        // Try a plain resolution first; fall back to a security-scoped one so bookmarks
        // saved by an earlier sandboxed build still resolve.
        var resolved: URL?
        for options in bookmarkResolutionOptionSets {
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: options,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                resolved = url
                break
            }
        }
        guard let url = resolved else { return }
        if url.startAccessingSecurityScopedResource() {
            accessing = url
        }
        rootURL = url
        if stale { saveBookmark(for: url) }
        refresh()
    }

    func closeVault() {
        stopAccessing()
        rootURL = nil
        rootNode = nil
        selectedFileURL = nil
        UserDefaults.standard.removeObject(forKey: Keys.bookmark)
    }

    /// Resolution options to attempt, in order. Plain bookmarks work in this non-sandboxed
    /// build; the security-scoped variant is kept as a fallback for legacy bookmarks.
    private var bookmarkResolutionOptionSets: [URL.BookmarkResolutionOptions] {
        #if os(macOS)
        return [[], [.withSecurityScope]]
        #else
        return [[]]
        #endif
    }

    private func saveBookmark(for url: URL) {
        // Non-sandboxed macOS uses plain bookmarks (no security scope needed).
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: Keys.bookmark)
        }
    }

    private func stopAccessing() {
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
    }

    var vaultName: String { rootURL?.lastPathComponent ?? "No Vault" }

    // MARK: - Tree building
    func refresh() {
        guard let rootURL else { rootNode = nil; return }
        rootNode = buildNode(at: rootURL, isRoot: true)
    }

    private func buildNode(at url: URL, isRoot: Bool = false) -> FileNode {
        let name = url.lastPathComponent
        var children: [FileNode]? = nil
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDir {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants])) ?? []
            let kids = contents
                .filter { showHiddenFiles || !$0.lastPathComponent.hasPrefix(".") }
                .filter { url in
                    let dir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if dir { return true }
                    let e = url.pathExtension.lowercased()
                    return FileNode.editableExtensions.contains(e)
                        || FileNode.imageExtensions.contains(e)
                        || e == "pdf"
                }
                .map { buildNode(at: $0) }
                .sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            children = kids
        }
        return FileNode(url: url, name: name, isDirectory: isDir, children: children)
    }

    // MARK: - Reading / writing
    func loadText(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func save(_ text: String, to url: URL) {
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    // MARK: - CRUD
    /// Directory new items should be created in, based on the current selection.
    func targetDirectory() -> URL? {
        guard let rootURL else { return nil }
        guard let sel = selectedFileURL else { return rootURL }
        let isDir = (try? sel.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return isDir ? sel : sel.deletingLastPathComponent()
    }

    @discardableResult
    func createFile(named rawName: String, in directory: URL? = nil) -> URL? {
        guard let dir = directory ?? targetDirectory() else { return nil }
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "Untitled" }
        if (name as NSString).pathExtension.isEmpty { name += ".md" }
        let url = uniqueURL(in: dir, name: name)
        FileManager.default.createFile(atPath: url.path, contents: Data("# \(url.deletingPathExtension().lastPathComponent)\n\n".utf8))
        refresh()
        selectedFileURL = url
        return url
    }

    @discardableResult
    func createFolder(named rawName: String, in directory: URL? = nil) -> URL? {
        guard let dir = directory ?? targetDirectory() else { return nil }
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "New Folder" }
        let url = uniqueURL(in: dir, name: name)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        refresh()
        return url
    }

    func delete(_ url: URL) {
        try? FileManager.default.trashOrRemove(url)
        if selectedFileURL == url { selectedFileURL = nil }
        refresh()
    }

    @discardableResult
    func rename(_ url: URL, to rawName: String) -> URL? {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if !isDir && (name as NSString).pathExtension.isEmpty {
            let oldExt = url.pathExtension
            if !oldExt.isEmpty { name += "." + oldExt }
        }
        let dest = url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            if selectedFileURL == url { selectedFileURL = dest }
            refresh()
            return dest
        } catch { return nil }
    }

    private func uniqueURL(in dir: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = dir.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            n += 1
            let newName = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = dir.appendingPathComponent(newName)
        }
        return candidate
    }

    // MARK: - Image resolution (Bear / Obsidian embeds)
    /// Resolve a markdown/Obsidian image reference to an on-disk URL.
    /// Handles `![[image.png]]`, `![alt](relative/path.png)`, optional `|size` suffix.
    func resolveImageURL(_ src: String, relativeTo fileURL: URL?) -> URL? {
        var name = src
        if let bar = name.firstIndex(of: "|") { name = String(name[..<bar]) }   // Obsidian size hint
        name = name.removingPercentEncoding ?? name
        name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.hasPrefix("http") else { return nil }

        let direct = [
            fileURL?.deletingLastPathComponent().appendingPathComponent(name),
            rootURL?.appendingPathComponent(name)
        ].compactMap { $0 }
        for c in direct where FileManager.default.fileExists(atPath: c.path) { return c }

        // Fall back to searching the whole vault by file name (Obsidian shortest-path behaviour).
        if let root = rootURL {
            let base = (name as NSString).lastPathComponent
            if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let u as URL in en where u.lastPathComponent == base { return u }
            }
        }
        return nil
    }
}

private extension FileManager {
    /// Move to Trash where available (macOS / iOS 11+), else hard delete.
    func trashOrRemove(_ url: URL) throws {
        do {
            try trashItem(at: url, resultingItemURL: nil)
        } catch {
            try removeItem(at: url)
        }
    }
}
