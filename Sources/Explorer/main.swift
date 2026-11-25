import AppKit
import ExplorerUI
import SuiteCore


// Escape hatch if the app was force-killed or crashed while Finder was kept closed: Finder started again,
// and the system Dock put back by Bar's own `--restore-bar`. (Finder's desktop is Desktop's:
// `Desktop --restore-finder`.)
if CommandLine.arguments.contains("--restore-finder") {
    if !FinderApp.isRunning { FinderApp.launch() }
    BarCompanion.restoreSystemDock()
    exit(0)
}

// Reopened by the previous copy (an update, Reopen, --relaunch): it is quitting; once it is gone, this
// copy carries on as Explorer.
AppRelauncher.waitForPreviousCopy()

// One Explorer at a time: two would fight over Finder. macOS may start another copy
// of the app (an older build, say) for "Show in Finder"; it hands over to the running one and leaves
// without touching Finder.
// The previous copy may still be listed for a moment after it has gone: never take it for another Explorer.
let me = ProcessInfo.processInfo.processIdentifier
let previous = AppRelauncher.previousCopy
if let bundleID = Bundle.main.bundleIdentifier,
   let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
       .first(where: { $0.processIdentifier != me && $0.processIdentifier != previous && !$0.isTerminated }) {
    if CommandLine.arguments.contains("--relaunch") {
        // `open -n Explorer.app --args --relaunch` (after a build): the running copy reopens itself, as for
        // an update, so the system Dock stays as it is; with `--background`, without opening its windows.
        ExplorerLink.send(AppRelauncher.isBackgroundLaunch ? .relaunchInBackground : .relaunch)
        // Long enough for the message to leave before this copy does.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    } else {
        running.activate()
    }
    exit(0)
}

#if DEBUG
let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
print("Explorer \(version) — build \(buildTimestamp)")
#endif

let app = NSApplication.shared
// No Dock icon until the app is in use; see AppDelegate.updateActivationPolicy().
app.setActivationPolicy(.accessory)
app.mainMenu = AppMenu.make(appName: "Explorer")
let delegate = AppDelegate()
app.delegate = delegate
app.run()
