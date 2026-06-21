import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            VaultView()
                .tabItem { Label("Vault", systemImage: "folder.fill") }
            FeedbackView()
                .tabItem { Label("Feedback", systemImage: "bubble.left.and.bubble.right.fill") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
    }
}
