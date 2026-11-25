import AppKit
import FinderGuard
import ExplorerUI
import SuiteFilesUI

/// Explorer in place of Finder for file windows, or Finder back, with one switch. "In place" covers keeping
/// Finder closed (while Desktop shows the desktop), redirecting it, and handling "Show in Finder" from
/// other apps; each part keeps its own preference while Finder is in use. The desktop is Desktop's
/// (suite-desktop).
final class FinderReplacement {
    static let shared = FinderReplacement()
    static let didChange = Notification.Name("FinderReplacementDidChange")
    private static let modeKey = "UseExplorer"
    private static let viewerKey = "OpenFoldersFromOtherApps"

    let quitter = FinderQuitter()
    let redirect = FinderRedirect()

    var usesExplorer: Bool {
        didSet { changed(Self.modeKey, usesExplorer); apply() }
    }

    /// "Show in Finder" in other apps opens Explorer (the NSFileViewer setting).
    var opensFoldersFromOtherApps: Bool {
        didSet { changed(Self.viewerKey, opensFoldersFromOtherApps); applyViewer() }
    }

    var keepsFinderClosed: Bool {
        get { quitter.isEnabled }
        set { quitter.isEnabled = newValue; notify() }
    }

    var redirectsFinder: Bool {
        get { redirect.isEnabled }
        set { redirect.isEnabled = newValue; notify() }
    }

    var asksBeforeRedirecting: Bool {
        get { redirect.asksFirst }
        set { redirect.asksFirst = newValue; notify() }
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Self.modeKey: true, Self.viewerKey: true])
        usesExplorer = defaults.bool(forKey: Self.modeKey)
        opensFoldersFromOtherApps = defaults.bool(forKey: Self.viewerKey)
        redirect.onRedirected = { [weak quitter] in quitter?.quitIfIdle() }
    }

    /// Takes the switches written in the defaults (a profile loaded), each applied as if turned in Settings.
    func reloadFromDefaults() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.modeKey) != usesExplorer { usesExplorer.toggle() }
        if defaults.bool(forKey: Self.viewerKey) != opensFoldersFromOtherApps { opensFoldersFromOtherApps.toggle() }
        for (key, keyPath) in [("QuitFinder", \FinderReplacement.keepsFinderClosed),
                               ("RedirectFinder", \FinderReplacement.redirectsFinder),
                               ("RedirectFinderAsks", \FinderReplacement.asksBeforeRedirecting)] {
            if let value = defaults.object(forKey: key) as? Bool, value != self[keyPath: keyPath] {
                self[keyPath: keyPath] = value
            }
        }
    }

    func start() {
        apply()
    }

    private func apply() {
        quitter.isSuspended = !usesExplorer
        redirect.isSuspended = !usesExplorer
        if usesExplorer {
            quitter.quitIfIdle()
        } else if !FinderApp.isRunning {
            // Finder manages files again: it comes back for its windows.
            FinderApp.launch()
        }
        applyViewer()
    }

    private func applyViewer() {
        guard DefaultFileViewer.canBeSet else { return }
        DefaultFileViewer.setThisApp(usesExplorer && opensFoldersFromOtherApps)
    }

    private func changed(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
