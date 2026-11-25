import AppKit
import FinderGuard

/// Keeps Finder closed while Explorer runs and Finder's desktop is hidden (Desktop shows its own): Finder
/// showing the desktop is never quit. When something brings Finder back (a Dock click, "Get Info",
/// emptying the Trash and so on), it is left alone until it has no window and isn't frontmost.
final class FinderQuitter {
    private static let defaultsKey = "QuitFinder"

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.defaultsKey)
            if isEnabled { quitIfIdle() } else if !FinderApp.isRunning { FinderApp.launch() }
        }
    }

    private var observer: NSObjectProtocol?

    init() {
        UserDefaults.standard.register(defaults: [Self.defaultsKey: true])
        isEnabled = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == FinderApp.bundleID else { return }
            self?.quitIfIdle()
        }
    }

    /// Set while the user has switched back to Finder: the preference is kept but not acted on.
    var isSuspended = false {
        didSet { if !isSuspended { quitIfIdle() } }
    }

    func quitIfIdle() {
        guard isEnabled, !isSuspended, GuardedApps.finderDesktopHidden, FinderApp.isRunning,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier != FinderApp.bundleID else { return }
        // Without permission to ask Finder, assume it is in use rather than closing someone's window.
        guard let windows = try? FinderApp.windowCount(), windows == 0 else { return }
        FinderApp.quit()
    }
}
