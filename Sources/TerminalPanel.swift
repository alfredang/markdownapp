#if os(macOS)
import SwiftUI

/// Owns the set of live terminal sessions. Held above the panel view so terminals keep
/// running even while the panel is collapsed.
final class TerminalController: ObservableObject {
    @Published var sessions: [TerminalSession] = []
    @Published var activeID: UUID?
    private var counter = 0

    var active: TerminalSession? { sessions.first { $0.id == activeID } }

    @discardableResult
    func newTerminal(directory: String, run command: String? = nil) -> TerminalSession {
        counter += 1
        let s = TerminalSession(directory: directory, index: counter)
        sessions.append(s)
        activeID = s.id
        if let command {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { s.run(command) }
        }
        return s
    }

    func select(_ id: UUID) { activeID = id }

    func close(_ id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].terminate()
        sessions.remove(at: idx)
        if activeID == id { activeID = sessions.last?.id }
    }

    func closeAll() {
        sessions.forEach { $0.terminate() }
        sessions.removeAll()
        activeID = nil
    }
}

/// VS Code-style terminal panel: a tab strip (one terminal per tab) plus toolbar controls,
/// and the active terminal filling the body.
struct TerminalPanel: View {
    @ObservedObject var controller: TerminalController
    let directory: String?
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(VSCode.border)
            body(for: controller.active)
        }
        .background(VSCode.panelBg)
        .onAppear { if controller.sessions.isEmpty { addTerminal() } }
    }

    // MARK: - Header (tabs + toolbar)
    private var header: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(controller.sessions) { session in
                        tab(session)
                    }
                }
            }
            Spacer(minLength: 8)
            toolbar
        }
        .frame(height: 35)
        .background(VSCode.tabBarBg)
    }

    private func tab(_ session: TerminalSession) -> some View {
        let isActive = session.id == controller.activeID
        return HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? VSCode.activeIcon : VSCode.muted)
            Text(session.title + (session.hasExited ? " (exited)" : ""))
                .font(.system(size: 12))
                .foregroundStyle(isActive ? VSCode.fg : VSCode.muted)
                .lineLimit(1)
            Button {
                controller.close(session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(VSCode.muted)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0.0)
        }
        .padding(.horizontal, 10)
        .frame(height: 35)
        .background(isActive ? VSCode.tabActiveBg : Color.clear)
        .overlay(alignment: .top) {
            Rectangle().fill(isActive ? VSCode.accent : Color.clear).frame(height: 1)
        }
        .overlay(alignment: .trailing) { Divider().overlay(VSCode.border) }
        .contentShape(Rectangle())
        .onTapGesture { controller.select(session.id) }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            toolButton("plus", help: "New Terminal") { addTerminal() }
            toolButton("trash", help: "Kill Active Terminal") {
                if let id = controller.activeID { controller.close(id) }
            }
            .disabled(controller.activeID == nil)
            toolButton("xmark", help: "Close Panel") { onClose() }
        }
        .padding(.trailing, 8)
    }

    private func toolButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(VSCode.fg)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Body
    @ViewBuilder
    private func body(for session: TerminalSession?) -> some View {
        if let session {
            TerminalViewHost(session: session)
                .id(session.id)
                .background(VSCode.panelBg)
        } else {
            VStack {
                Spacer()
                Text("No terminals. Press + to open one in the vault directory.")
                    .font(.system(size: 12))
                    .foregroundStyle(VSCode.muted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func addTerminal() {
        let dir = directory ?? FileManager.default.homeDirectoryForCurrentUser.path
        controller.newTerminal(directory: dir)
    }
}
#endif
