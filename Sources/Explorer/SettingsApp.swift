import AppKit
import ExplorerCore
import ExplorerSettings
import ExplorerUI
import SuiteCore
import SuiteFilesCore
import SuiteFilesUI

/// Suite Settings, the settings as an app of its own: Explorer's menus open it on a tab, and Explorer
/// applies what it writes, does what it asks and tells it what changed (`ExplorerLink`).
enum SettingsApp {
    static let bundleID = "local.suite.settings"

    /// Opens Suite Settings on `tab`, or says it isn't installed.
    static func show(tab: String? = nil) {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            DistributedNotificationCenter.default().postNotificationName(
                ExplorerLink.showNotification, object: nil, userInfo: tab.map { ["tab": $0] }, deliverImmediately: true)
            running.activate()
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Suite Settings isn't installed", comment: "")
            alert.informativeText = NSLocalizedString("Explorer's settings are an app of their own. Install Suite Settings to change them.", comment: "")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = tab.map { ["--tab", $0] } ?? []
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    // MARK: Explorer's side of the link

    private static var observers: [NSObjectProtocol] = []
    private static var pendingReport: DispatchWorkItem?

    /// At launch: answers Suite Settings' commands, and tells it when settings change here.
    static func startListening() {
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: ExplorerLink.commandNotification, object: nil, queue: .main) { note in
            guard let raw = note.object as? String, let command = ExplorerLink.Command(rawValue: raw) else { return }
            switch command {
            case .applySettings: applyFromDefaults()
            case .checkForUpdates: SuiteUpdater.explorer.check(userInitiated: true)
            case .allowWindowFitting: break // Asked of the Dock now (BarMessage).
            case .emptyTrash: FileActions.emptyTrash()
            case .relaunch: AppRelauncher.relaunch()
            case .relaunchInBackground: AppRelauncher.relaunch(inBackground: true)
            case .reportStatus: report()
            }
        })
        // Files another app of the suite (the Dock) asks Explorer to open as it opens them.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: ExplorerLink.openFilesNotification, object: nil, queue: .main) { note in
            ExplorerLink.files(of: note).forEach(FileActions.openFile)
        })
        for name in [DisplaySettings.didChange, WindowSettings.didChange,
                     FinderReplacement.didChange, QuickAccessStore.didChange,
                     SuiteUpdater.didChange, MenuBarExtra.didChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                report()
            })
        }
        report()
    }

    /// Settings were written elsewhere (Suite Settings, a profile): the parts that keep settings read
    /// them again, as a change made here would apply, and the rest redraws.
    static func applyFromDefaults() {
        // Written by another process: read them from the preferences daemon, not from this app's cache,
        // which may not have caught up yet.
        CFPreferencesAppSynchronize(SuiteDefaults.explorerDomain as CFString)
        // A profile of an earlier version: its settings converted first.
        SuiteUpdater.explorer.bringSettingsUpToDate()
        FileHandle.standardError.write(Data("Explorer: settings applied from Suite Settings\n".utf8))
        FinderReplacement.shared.reloadFromDefaults()
        SuiteUpdater.explorer.settings = UpdateSettings.load()
        for name in [DisplaySettings.didChange, WindowSettings.didChange, QuickAccessStore.didChange,
                     FolderViewStore.didChange, MenuBarExtra.didChange,
                     FinderReplacement.didChange] {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }

    /// Writes down what Settings shows about Explorer, then tells it, once for a burst of changes.
    private static func report() {
        pendingReport?.cancel()
        let work = DispatchWorkItem {
            let defaults = SuiteDefaults.explorer
            defaults.set(SuiteUpdater.explorer.describeState(), forKey: ExplorerLink.StatusKey.updaterState)
            defaults.set(DefaultFileViewer.canBeSet, forKey: ExplorerLink.StatusKey.canSetDefaultViewer)
            DistributedNotificationCenter.default().postNotificationName(ExplorerLink.explorerDidChange, object: nil,
                                                                         userInfo: nil, deliverImmediately: true)
        }
        pendingReport = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
}
