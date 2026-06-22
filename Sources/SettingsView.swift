import SwiftUI

/// Settings tab — vault management and display preferences.
struct SettingsView: View {
    @EnvironmentObject var store: VaultStore
    @AppStorage("settings.previewDefault") private var previewDefault = false
    @AppStorage("editor.multipleTabs") private var multipleTabs = true

    @State private var showRename = false
    @State private var renameText = ""

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
                        Button {
                            renameText = store.vaultName
                            showRename = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Rename this vault")
                        .disabled(store.rootURL == nil)
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

                // Recent vaults — one-click switching, Obsidian-style.
                let others = store.recentVaults.filter { $0.standardizedFileURL != store.rootURL?.standardizedFileURL }
                if !others.isEmpty {
                    Text("RECENT VAULTS").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(others.enumerated()), id: \.element) { index, url in
                            if index > 0 { Divider() }
                            HStack {
                                Button {
                                    store.openVault(at: url)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Label(store.displayName(for: url), systemImage: "folder")
                                        Text(url.path)
                                            .font(.caption2)
                                            .foregroundStyle(Theme.mutedInk)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Button {
                                    store.removeRecent(url)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove from recent list")
                            }
                            .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
                }

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
