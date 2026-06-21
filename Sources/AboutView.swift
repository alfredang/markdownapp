import SwiftUI

/// About tab — app card, developer card + website link, version row.
struct AboutView: View {
    private let developerURL = URL(string: "https://www.tertiaryinfotech.com")!

    private var versionString: String {
        let i = Bundle.main.infoDictionary
        let s = i?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = i?["CFBundleVersion"] as? String ?? "1"
        return "\(s) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("About").font(.largeTitle.bold())

                // App card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .font(.title)
                            .foregroundStyle(Theme.accent)
                        Text("Markdown Vault").font(.title3.bold())
                    }
                    Text("A native Markdown notes app for Mac, iPad and iPhone. Open any local folder — fully compatible with your Obsidian vault — and write with live preview, embedded images, and clean tables.")
                        .foregroundStyle(Theme.mutedInk)
                }
                .appCard()

                // Developer card
                Text("DEVELOPER").font(.caption.weight(.semibold)).foregroundStyle(Theme.mutedInk)
                VStack(alignment: .leading, spacing: 0) {
                    Label("Tertiary Infotech Academy Pte Ltd", systemImage: "building.2.fill")
                        .padding(.vertical, 14)
                    Divider()
                    Link(destination: developerURL) {
                        Label("tertiaryinfotech.com", systemImage: "globe")
                    }
                    .padding(.vertical, 14)
                }
                .padding(.horizontal, 16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))

                // Version row
                HStack {
                    Text("Version")
                    Spacer()
                    Text(versionString).foregroundStyle(Theme.mutedInk)
                }
                .appCard()

                Text("Markdown Vault stores your notes as plain `.md` files on your device. Your content never leaves your Mac, iPad or iPhone.")
                    .font(.footnote)
                    .foregroundStyle(Theme.mutedInk)
            }
            .padding(22)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
    }
}
