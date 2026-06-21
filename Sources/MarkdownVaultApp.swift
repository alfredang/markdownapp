import SwiftUI

@main
struct MarkdownVaultApp: App {
    @StateObject private var store = VaultStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Theme.accent)
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Markdown File") { store.requestNewFile() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("Open Vault Folder…") { store.requestOpenVault() }
                    .keyboardShortcut("o", modifiers: [.command])
            }
        }
        #endif
    }
}
