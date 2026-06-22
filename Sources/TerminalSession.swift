#if os(macOS)
import SwiftUI
import AppKit
import SwiftTerm

/// One live terminal = one tab. Owns a SwiftTerm `LocalProcessTerminalView` that runs a
/// real login shell started in the vault directory. The view is created once and reused so
/// SwiftUI re-renders never restart the shell.
final class TerminalSession: NSObject, ObservableObject, Identifiable, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let terminalView: LocalProcessTerminalView
    let directory: String

    @Published var title: String
    @Published var hasExited = false

    /// Sequential label like VS Code ("zsh", "zsh (2)", …)
    init(directory: String, index: Int) {
        self.directory = directory
        self.terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let shellName = (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        self.title = index <= 1 ? (shellName as NSString).lastPathComponent
                                : "\((shellName as NSString).lastPathComponent) (\(index))"
        super.init()

        applyTheme()
        terminalView.processDelegate = self

        let shell = shellName
        let env = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        // Login + interactive shell, started already inside the vault directory.
        terminalView.startProcess(executable: shell,
                                  args: ["-l"],
                                  environment: env,
                                  currentDirectory: directory)
    }

    private func applyTheme() {
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        terminalView.nativeBackgroundColor = NSColor(srgbRed: VSCode.termBg.r, green: VSCode.termBg.g, blue: VSCode.termBg.b, alpha: 1)
        terminalView.nativeForegroundColor = NSColor(srgbRed: VSCode.termFg.r, green: VSCode.termFg.g, blue: VSCode.termFg.b, alpha: 1)
        terminalView.caretColor = NSColor(srgbRed: VSCode.termCaret.r, green: VSCode.termCaret.g, blue: VSCode.termCaret.b, alpha: 1)
    }

    func focus() {
        terminalView.window?.makeFirstResponder(terminalView)
    }

    /// Feed a command line to the running shell (as if typed), followed by Return.
    func run(_ command: String) {
        terminalView.send(txt: command + "\n")
    }

    func terminate() {
        terminalView.processDelegate = nil
        // Best-effort: terminate the child shell.
        terminalView.terminate()
    }

    // MARK: - LocalProcessTerminalViewDelegate
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Keep the short shell label; ignore noisy OSC titles unless useful.
        guard !title.isEmpty else { return }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { self.hasExited = true }
    }
}

/// Thin SwiftUI host for a session's terminal view. Identity is the session, so the NSView
/// instance is preserved across layout changes.
struct TerminalViewHost: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> LocalProcessTerminalView { session.terminalView }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}
#endif
