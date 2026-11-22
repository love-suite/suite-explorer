import AppKit
import SuiteCore
import FinderGuard
import ExplorerCore
import ExplorerSettings
import ExplorerUI
import SuiteFilesUI

/// The icon in the menu bar's right side, with New Explorer Window, the Finder switch and Settings.
/// Off by default: the app's own menu bar covers the same commands.
enum MenuBarExtra {
    static let didChange = Notification.Name("MenuBarExtraDidChange")
    private static let key = "ShowMenuBarIcon"

    static var isShown: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var switchItem: NSMenuItem?
    private var signalSources: [DispatchSourceSignal] = []
    private var refreshingMenuBar = false
    /// Logout, restart or shutdown under way: quitting then isn't quitting Explorer for good.
    private var isPoweringOff = false

    // MARK: Launch and quit

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The "reveal" event sent for "Show in Finder" once we are the default folder viewer ('misc'/'mvis').
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleReveal(_:replyEvent:)),
            forEventClass: AEEventClass(kAEMiscStandards), andEventID: AEEventID(kAEMakeObjectsVisible))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        WindowSettings.openSettings = { SettingsApp.show(tab: $0) }
        // The shared file views open folders and show items in Explorer's windows; what needs root to be
        // erased goes to Suite Trash, which Explorer holds.
        FileViewer.openFolder = { ExplorerWindowController.open($0) }
        FileViewer.reveal = { ExplorerWindowController.reveal($0) }
        FileActions.didPutBack = { restored in
            // The folder it went back to opens, if chosen (Settings › Trash); off by default.
            if WindowSettings.opensFolderAfterRestore { ExplorerWindowController.reveal(restored) }
        }
        FileActions.eraseNeedingRoot = { PrivilegedEraser.erase($0) }
        ClipboardCompanion.start()
        BindingsCompanion.start()
        FileUndo.recordTrashingInOtherApps()
        SettingsApp.startListening()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.isPoweringOff = true }
        restoreFinderOnSignals()
        FinderReplacement.shared.start()
        // The windows of last time, as they were, while Explorer manages files.
        if WindowSettings.reopensWindows, FinderReplacement.shared.usesExplorer, !AppRelauncher.isBackgroundLaunch {
            ExplorerWindowController.restoreSession()
        }
        SuiteUpdater.explorer.start()
        updateStatusItem()
        NotificationCenter.default.addObserver(forName: MenuBarExtra.didChange, object: nil, queue: .main) {
            [weak self] _ in self?.updateStatusItem()
        }
        ExplorerWindowController.onLastWindowClosed = { [weak self] in self?.updateActivationPolicy() }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appDidBecomeActive),
                           name: NSApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidResignActive),
                           name: NSApplication.didResignActiveNotification, object: nil)

        // `Explorer <path>` from the command line opens that folder.
        if let start = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }).flatMap(PathParser.parse) {
            ExplorerWindowController.open(start)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Finder, kept closed while Explorer ran, comes back for its windows (not when Explorer reopens
        // itself: the new copy keeps it closed).
        guard !AppRelauncher.isRelaunching, !FinderApp.isRunning else { return }
        FinderApp.launch()
    }

    /// Ctrl+C, closing the terminal or `kill`: quit as usual, so Finder comes back.
    private func restoreFinderOnSignals() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: Dock icon and menu bar

    /// Finder's Dock icon can't be removed, so ours only shows while the app is in use: when it is
    /// active (a window clicked) or has Explorer windows open, which Cmd+Tab and the Dock must
    /// reach (the settings have their own app and icon). macOS only gives the menu bar to apps that have a
    /// Dock icon.
    private func updateActivationPolicy() {
        let inUse = NSApp.isActive || ExplorerWindowController.hasOpenWindows
        let policy: NSApplication.ActivationPolicy = inUse ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    @objc private func appDidBecomeActive() {
        guard !refreshingMenuBar, NSApp.activationPolicy() == .accessory else { return }
        NSApp.setActivationPolicy(.regular)
        // An app that is already active doesn't get its menu bar after the policy change until it is
        // activated again, so hand activation to the Dock for an instant and take it back.
        refreshingMenuBar = true
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.refreshingMenuBar = false }
        }
    }

    @objc private func appDidResignActive() {
        guard !refreshingMenuBar else { return }
        updateActivationPolicy()
    }

    /// Clicking our Dock icon: open a window if none is open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !ExplorerWindowController.hasOpenWindows {
            ExplorerWindowController.open(FileManager.default.homeDirectoryForCurrentUser, newWindow: true)
        }
        return false
    }

    // MARK: Requests from other apps

    func application(_ application: NSApplication, open urls: [URL]) {
        log("open", urls)
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if values?.isDirectory == true && values?.isPackage != true {
                ExplorerWindowController.open(url)
            } else {
                ExplorerWindowController.reveal([url])
            }
        }
    }

    @objc private func handleReveal(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let direct = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        let descriptors = direct.numberOfItems > 0
            ? (1...direct.numberOfItems).compactMap { direct.atIndex($0) }
            : [direct]
        let urls = descriptors.compactMap { $0.coerce(toDescriptorType: typeFileURL)?.fileURLValue }
        log("reveal", urls)
        ExplorerWindowController.reveal(urls)
    }

    private func log(_ kind: String, _ urls: [URL]) {
        FileHandle.standardError.write(Data("Explorer: \(kind) request for \(urls.map(\.path))\n".utf8))
    }

    // MARK: Status item

    private func updateStatusItem() {
        if MenuBarExtra.isShown, statusItem == nil {
            setUpStatusItem()
            FileHandle.standardError.write(Data("Explorer: menu bar icon shown\n".utf8))
        } else if !MenuBarExtra.isShown, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            FileHandle.standardError.write(Data("Explorer: menu bar icon removed\n".utf8))
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "Explorer") {
            item.button?.image = image
        } else {
            item.button?.title = "Ex"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(menuItem(NSLocalizedString("New Explorer Window", comment: ""), #selector(openHome)))
        menu.addItem(.separator())
        let switchItem = menuItem(NSLocalizedString("Switch to Finder", comment: ""), #selector(switchApps))
        menu.addItem(switchItem)
        self.switchItem = switchItem
        menu.addItem(menuItem(NSLocalizedString("Settings", comment: ""), #selector(showSettings(_:))))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("Quit Explorer", comment: ""),
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        switchItem?.title = FinderReplacement.shared.usesExplorer
            ? NSLocalizedString("Switch to Finder", comment: "")
            : NSLocalizedString("Switch to Explorer", comment: "")
    }

    @objc func showAboutPanel(_ sender: Any?) {
#if DEBUG
        NSApp.orderFrontStandardAboutPanel(options: [
            .version: "build \(buildTimestamp)"
        ])
#else
        NSApp.orderFrontStandardAboutPanel(nil)
#endif
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsApp.show()
    }

    @objc private func switchApps() {
        FinderReplacement.shared.usesExplorer.toggle()
    }

    @objc private func openHome() {
        ExplorerWindowController.open(FileManager.default.homeDirectoryForCurrentUser, newWindow: true)
    }
}
