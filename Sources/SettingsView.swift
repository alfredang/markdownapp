import SwiftUI

/// Settings tab — vault management and display preferences.
struct SettingsView: View {
    @EnvironmentObject var store: VaultStore
    @AppStorage("settings.previewDefault") private var previewDefault = false
    @AppStorage("editor.multipleTabs") private var multipleTabs = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings").font(.largeTitle.bold())

                // Vault
                Text("VAULT").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label("Current Vault", systemImage: "folder.fill")
                        Spacer()
                        Text(store.vaultName).foregroundStyle(Theme.mutedInk)
                    }
                    .padding(.vertical, 14)
                    Divider()
                    Button {
                        store.requestOpenVault()
                    } label: {
                        Label("Open Another Folder…", systemImage: "folder.badge.plus")
                    }
                    .padding(.vertical, 14)
                    Divider()
                    Button(role: .destructive) {
                        store.closeVault()
                    } label: {
                        Label("Close Vault", systemImage: "xmark.circle")
                    }
                    .padding(.vertical, 14)
                }
                .padding(.horizontal, 16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))

                // Display
                Text("DISPLAY").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                VStack(alignment: .leading, spacing: 0) {
                    Toggle(isOn: $store.showHiddenFiles) {
                        Label("Show Hidden Files", systemImage: "eye")
                    }
                    .padding(.vertical, 12)
                    Divider()
                    Toggle(isOn: $previewDefault) {
                        Label("Open Notes in Preview", systemImage: "doc.text.image")
                    }
                    .padding(.vertical, 12)
                    #if os(macOS)
                    Divider()
                    Toggle(isOn: $multipleTabs) {
                        Label("Show Multiple Editor Tabs", systemImage: "rectangle.split.3x1")
                    }
                    .padding(.vertical, 12)
                    #endif
                }
                .padding(.horizontal, 16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
                .tint(Theme.accent)
            }
            .padding(22)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        // Bridge the importer used elsewhere — settings just toggles the request flag.
    }
}
