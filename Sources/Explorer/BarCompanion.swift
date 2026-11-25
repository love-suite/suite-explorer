import AppKit
import SuiteCore

/// The Dock, an app of its own (Bar.app, repository suite-bar), seen from Explorer: `--restore-finder`
/// asks it to put the system Dock back. Bar starts by itself at login while turned on.
enum BarCompanion {
    static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: SuiteBarApp.bundleID)
    }

    /// For `--restore-finder`: the system Dock as it was, by Bar's own `--restore-bar`.
    static func restoreSystemDock() {
        guard let executable = appURL.flatMap({ Bundle(url: $0)?.executableURL }) else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--restore-bar"]
        try? process.run()
        process.waitUntilExit()
    }
}
