import AppKit

/// Finder itself: whether it runs, starting and quitting it, asking it about its windows. Its desktop is
/// Desktop's business (suite-desktop), not Explorer's.
enum FinderApp {
    static let bundleID = "com.apple.finder"

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// A polite quit (Apple event), after which macOS leaves Finder closed until something needs it.
    static func quit() {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
    }

    static func launch() {
        run("/usr/bin/open", ["-g", "-b", bundleID])
    }

    private static let countWindowsScript = NSAppleScript(source: """
        tell application "Finder" to return count of Finder windows
        """)

    /// Asking a Finder that isn't running would launch it, so callers check `isRunning` first.
    static func windowCount() throws -> Int {
        var error: NSDictionary?
        guard let result = countWindowsScript?.executeAndReturnError(&error) else {
            throw NSError(domain: "FinderApp", code: (error?[NSAppleScript.errorNumber] as? Int) ?? -1)
        }
        return Int(result.int32Value)
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            FileHandle.standardError.write(Data("Could not run \(path): \(error)\n".utf8))
        }
    }
}
