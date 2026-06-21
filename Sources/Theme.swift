import SwiftUI

/// Single source of truth for the brand palette. Reference these tokens everywhere,
/// never raw `Color` literals (see the `mobile-ios-design` skill).
enum Theme {
    static let primary = Color(hex: 0x7C5CFF)     // violet — Obsidian-flavoured accent
    static let secondary = Color(hex: 0x4C8DFF)   // blue — links / selected
    static let highlight = Color(hex: 0xFFB020)   // amber — badges / highlights
    static let accent = primary

    #if os(macOS)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .underPageBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    #else
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    #endif

    static let ink = Color.primary
    static let mutedInk = Color.secondary
    static let hairline = Color.primary.opacity(0.08)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// Reusable elevated card surface — white/elevated, continuous corners, hairline border.
struct AppCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )
    }
}

extension View {
    func appCard(padding: CGFloat = 16) -> some View { modifier(AppCard(padding: padding)) }
}
