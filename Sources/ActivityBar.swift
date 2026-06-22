#if os(macOS)
import SwiftUI
import AppKit

/// The sections selectable from the activity bar that drive the side bar content.
enum ActivityItem: String, CaseIterable, Identifiable {
    case explorer, search, extensions
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .explorer:   return "doc.on.doc"
        case .search:     return "magnifyingglass"
        case .extensions: return "square.grid.2x2"
        }
    }
    var help: String {
        switch self {
        case .explorer:   return "Explorer"
        case .search:     return "Search"
        case .extensions: return "Extensions"
        }
    }
}

/// VS Code's far-left vertical icon strip. Selecting the active item toggles the side bar.
struct ActivityBar: View {
    @Binding var selection: ActivityItem
    @Binding var sidebarVisible: Bool
    var onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ActivityItem.allCases) { item in
                itemButton(item)
            }
            Spacer()
            AccountButton()
            bottomButton("gearshape", help: "Settings", action: onSettings)
        }
        .padding(.vertical, 6)
        .frame(width: 48)
        .frame(maxHeight: .infinity)
        .background(VSCode.activityBg)
        .overlay(alignment: .trailing) {
            Rectangle().fill(VSCode.border).frame(width: 1)
        }
    }

    private func itemButton(_ item: ActivityItem) -> some View {
        let isActive = selection == item && sidebarVisible
        return Button {
            if selection == item {
                sidebarVisible.toggle()
            } else {
                selection = item
                sidebarVisible = true
            }
        } label: {
            Image(systemName: item.icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(isActive ? VSCode.activeIcon : VSCode.muted)
                .frame(width: 48, height: 48)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(isActive ? VSCode.activeIcon : Color.clear)
                        .frame(width: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.help)
    }

    private func bottomButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(VSCode.muted)
                .frame(width: 48, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// VS Code-style "Accounts" menu — shows the Mac's iCloud sign-in status and a shortcut
/// to manage the Apple Account in System Settings.
private struct AccountButton: View {
    private var signedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }

    var body: some View {
        Menu {
            Section("Accounts") {
                Label(signedIn ? "iCloud — Signed In" : "iCloud — Not Signed In",
                      systemImage: signedIn ? "checkmark.icloud" : "icloud.slash")
                    .disabled(true)
            }
            Divider()
            if signedIn {
                Button("Manage Apple Account…") { openAppleIDSettings() }
            } else {
                Button("Sign In to iCloud…") { openAppleIDSettings() }
            }
            Button("iCloud Settings…") { openICloudSettings() }
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(VSCode.muted)
                .frame(width: 48, height: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(signedIn ? "Accounts — iCloud Signed In" : "Accounts")
    }

    private func openAppleIDSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings") {
            NSWorkspace.shared.open(url)
        }
    }
    private func openICloudSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane?iCloud") {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif
