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

/// VS Code "Dark Modern" palette tokens for the desktop editor chrome.
enum VSCode {
    static let accent      = Color(hex: 0x0078D4)   // focus blue
    static let editorBg    = Color(hex: 0x1E1E1E)
    static let sidebarBg   = Color(hex: 0x181818)
    static let activityBg  = Color(hex: 0x181818)
    static let panelBg     = Color(hex: 0x1E1E1E)
    static let tabBarBg    = Color(hex: 0x181818)
    static let tabActiveBg = Color(hex: 0x1E1E1E)
    static let border      = Color(hex: 0x2B2B2B)
    static let fg          = Color(hex: 0xCCCCCC)
    static let muted       = Color(hex: 0x8B8B8B)
    static let activeIcon  = Color(hex: 0xE7E7E7)
    static let hoverBg     = Color.white.opacity(0.06)
    static let selectionBg = Color(hex: 0x04395E)   // explorer selected row

    // Terminal colors (sRGB components, 0-1)
    static let termBg:    (r: Double, g: Double, b: Double) = (0x1E/255, 0x1E/255, 0x1E/255)
    static let termFg:    (r: Double, g: Double, b: Double) = (0xCC/255, 0xCC/255, 0xCC/255)
    static let termCaret: (r: Double, g: Double, b: Double) = (0xAE/255, 0xAF/255, 0xAD/255)
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
