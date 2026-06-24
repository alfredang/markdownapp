import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import CoreServices   // FSEvents — live folder watching
#endif

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

    /// Explorer sort direction (folders always group first). Persisted.
    @Published var sortAscending = true {
        didSet { UserDefaults.standard.set(sortAscending, forKey: Keys.sortAsc); refresh() }
    }

    /// Recently-opened vault folders, most-recent first (Obsidian-style vault switcher).
    @Published var recentVaults: [URL] = []

    /// Per-vault custom display names, keyed by folder path. Lets you rename a vault's
    /// shown name without touching the folder on disk.
    @Published private var displayNames: [String: String] = [:]

    private enum Keys {
        static let bookmark = "vault.bookmark"
        static let showHidden = "settings.showHidden"
        static let onboarded = "vault.onboarded"
        static let sortAsc = "settings.sortAscending"
        static let recents = "vault.recents"
        static let displayNames = "vault.displayNames"
    }

    private var accessing: URL?

    init() {
        showHiddenFiles = UserDefaults.standard.bool(forKey: Keys.showHidden)
        sortAscending = UserDefaults.standard.object(forKey: Keys.sortAsc) as? Bool ?? true
        recentVaults = (UserDefaults.standard.array(forKey: Keys.recents) as? [String] ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        displayNames = UserDefaults.standard.dictionary(forKey: Keys.displayNames) as? [String: String] ?? [:]
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
        addRecent(url)
        refresh()
        startWatching(url)
    }

    /// Add a folder to the top of the recent-vaults list (deduped, capped).
    private func addRecent(_ url: URL) {
        var list = recentVaults.filter { $0.standardizedFileURL != url.standardizedFileURL }
        list.insert(url, at: 0)
        recentVaults = Array(list.prefix(10))
        UserDefaults.standard.set(recentVaults.map(\.path), forKey: Keys.recents)
    }

    func removeRecent(_ url: URL) {
        recentVaults.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        UserDefaults.standard.set(recentVaults.map(\.path), forKey: Keys.recents)
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
        addRecent(dest)
        refresh()
        startWatching(dest)
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
        addRecent(url)
        refresh()
        startWatching(url)
    }

    func closeVault() {
        stopWatching()
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

    var vaultName: String {
        guard let rootURL else { return "No Vault" }
        return displayNames[rootURL.path] ?? rootURL.lastPathComponent
    }

    /// The vault's real folder name on disk (ignores any custom display name).
    var vaultFolderName: String { rootURL?.lastPathComponent ?? "No Vault" }

    /// Rename the *display* name of the current vault (does not move the folder).
    /// Pass an empty/whitespace string to clear the override and fall back to the folder name.
    func renameVault(to newName: String) {
        guard let rootURL else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == rootURL.lastPathComponent {
            displayNames[rootURL.path] = nil
        } else {
            displayNames[rootURL.path] = trimmed
        }
        UserDefaults.standard.set(displayNames, forKey: Keys.displayNames)
    }

    /// Display name for any vault URL (used by the recent-vaults list).
    func displayName(for url: URL) -> String {
        displayNames[url.path] ?? url.lastPathComponent
    }

    // MARK: - Tree building
    func refresh() {
        guard let rootURL else { rootNode = nil; return }
        rootNode = buildNode(at: rootURL, isRoot: true)
    }

    // MARK: - Live folder watching (auto-sync)
    #if os(macOS)
    private var fsStream: FSEventStreamRef?
    private var autoRefreshWork: DispatchWorkItem?

    /// Watch the vault folder (recursively) for any on-disk change — files created,
    /// deleted, or renamed by agents, git, Finder, the terminal — and refresh the tree.
    private func startWatching(_ url: URL) {
        stopWatching()
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let store = Unmanaged<VaultStore>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in store.scheduleAutoRefresh() }
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.4,                      // coalesce bursts within 0.4s
            flags) else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        fsStream = stream
    }

    private func stopWatching() {
        guard let stream = fsStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        fsStream = nil
    }

    /// Debounce rapid change bursts into a single refresh.
    func scheduleAutoRefresh() {
        autoRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        autoRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    #else
    private func startWatching(_ url: URL) {}
    private func stopWatching() {}
    #endif

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
                // Show every file type (only the hidden-files toggle filters dotfiles).
                // Non-editable files still open to a graceful "Unsupported File" view.
                .filter { showHiddenFiles || !$0.lastPathComponent.hasPrefix(".") }
                .map { buildNode(at: $0) }
                .sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                    let order = lhs.name.localizedStandardCompare(rhs.name)
                    return sortAscending ? order == .orderedAscending : order == .orderedDescending
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
