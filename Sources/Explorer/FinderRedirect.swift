import AppKit
import ExplorerUI

/// When enabled, Finder is hidden the moment it comes forward, so its window never reaches the screen.
/// Then, unless `asksFirst` is off, the user is asked whether they meant to use Finder: if not, its
/// windows reopen in Explorer and are closed in Finder; if so, Finder is shown again.
final class FinderRedirect {
    private static let enabledKey = "RedirectFinder"
    private static let asksKey = "RedirectFinderAsks"

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            updateObserver()
        }
    }

    var asksFirst: Bool {
        didSet { UserDefaults.standard.set(asksFirst, forKey: Self.asksKey) }
    }

    /// Called once Finder's windows have moved to Explorer.
    var onRedirected: (() -> Void)?
    /// Set while the user has switched back to Finder: the preference is kept but not acted on.
    var isSuspended = false

    private var observer: NSObjectProtocol?
    private var isBusy = false
    /// Set when the user chose to keep Finder; cleared once Finder has no window left.
    private var finderAllowed = false
    /// Showing Finder again re-activates it; that activation must not ask a second time.
    private var graceUntil = Date.distantPast

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Self.asksKey: true])
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        asksFirst = defaults.bool(forKey: Self.asksKey)
        updateObserver()
    }

    private func updateObserver() {
        let center = NSWorkspace.shared.notificationCenter
        if isEnabled, observer == nil {
            observer = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                          object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == FinderApp.bundleID else { return }
                self?.finderActivated(app)
            }
        } else if !isEnabled, let observer {
            center.removeObserver(observer)
            self.observer = nil
        }
    }

    private func finderActivated(_ finder: NSRunningApplication) {
        guard !isSuspended, !isBusy, Date() > graceUntil else { return }
        if finderAllowed {
            if (try? FinderApp.windowCount()) ?? 0 > 0 { return }
            finderAllowed = false
        }
        finder.hide()
        isBusy = true
        if asksFirst {
            DispatchQueue.main.async { self.ask(finder) }
        } else {
            redirect()
        }
    }

    private func ask(_ finder: NSRunningApplication) {
        let alert = NSAlert()
        alert.messageText = "Did you mean to open Finder?"
        alert.informativeText = "Choose Explorer to show Finder's windows in Explorer instead and close them in Finder."
        alert.addButton(withTitle: "Open Explorer")
        alert.addButton(withTitle: "Keep Finder")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        NSApp.activate(ignoringOtherApps: true)
        let useExplorer = alert.runModal() == .alertFirstButtonReturn

        if alert.suppressionButton?.state == .on {
            // Remembered answer: Explorer means redirect automatically, Finder means stop redirecting.
            if useExplorer { asksFirst = false } else { isEnabled = false }
        }
        if useExplorer {
            redirect()
        } else {
            isBusy = false
            finderAllowed = true
            graceUntil = Date().addingTimeInterval(1)
            finder.unhide()
            finder.activate()
        }
    }

    private func redirect() {
        // A Dock click makes Finder create its window just after activating; collect it once it exists.
        collect(after: 0.25, retry: true)
    }

    private func collect(after delay: TimeInterval, retry: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let folders: [URL]
            do {
                folders = try Self.takeFinderWindows()
            } catch {
                self.isBusy = false
                self.isEnabled = false
                Self.explainPermission(error)
                return
            }
            if folders.isEmpty && retry {
                self.collect(after: 0.5, retry: false)
                return
            }
            self.isBusy = false
            let targets = folders.isEmpty ? [FileManager.default.homeDirectoryForCurrentUser] : folders
            targets.forEach { ExplorerWindowController.open($0) }
            self.onRedirected?()
        }
    }

    // MARK: Talking to Finder

    private static let takeWindowsScript = NSAppleScript(source: """
        tell application "Finder"
            set folderPaths to {}
            repeat with w in (every Finder window)
                try
                    set end of folderPaths to POSIX path of (target of w as alias)
                end try
            end repeat
            close every Finder window
            return folderPaths
        end tell
        """)

    /// Returns the folders Finder's windows were showing, then closes those windows.
    private static func takeFinderWindows() throws -> [URL] {
        let result = try run(takeWindowsScript)
        guard result.numberOfItems > 0 else { return [] }
        return (1...result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private static func run(_ script: NSAppleScript?) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error) else {
            throw NSError(domain: "FinderRedirect",
                          code: (error?[NSAppleScript.errorNumber] as? Int) ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: (error?[NSAppleScript.errorMessage] as? String)
                                     ?? "Unknown error"])
        }
        return result
    }

    private static func explainPermission(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Explorer can't take over Finder's windows"
        alert.informativeText = """
            macOS needs your permission to let this app control Finder. Allow it in \
            System Settings › Privacy & Security › Automation, then turn the option back on.
            """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        }
    }
}
