import AppKit
import ExplorerUI
import SuiteCore

/// Bindings, the keyboard shortcuts app (repository suite-bindings), seen from Explorer: Explorer starts it
/// at launch (unless it is turned off in Settings › Bindings), and keeps it told where the keyboard is in
/// Explorer (a folder window, another window), which only Explorer knows and Bindings' rules can be limited
/// to. Its rules are edited in Suite Settings. The desktop is Desktop.app's, which Explorer can't tell.
enum BindingsCompanion {
    private static var observers: [NSObjectProtocol] = []

    static func start() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in publishContext() })
        }
        // Bindings started after Explorer: it asks.
        observers.append(BindingsMessage.requestExplorerContext.observe { _ in publishContext() })
        if BindingsApp.isEnabled { BindingsApp.launch() }
    }

    /// Where the keyboard is, from the key window.
    static func context(of window: NSWindow) -> ExplorerContext {
        if window.windowController is ExplorerWindowController { return .folderWindow }
        return .otherWindow
    }

    private static func publishContext() {
        guard let window = NSApp.keyWindow else { return }
        context(of: window).post()
    }
}
