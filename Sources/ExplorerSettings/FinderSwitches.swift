import Foundation
import SuiteCore

/// Explorer's Finder switches, as Explorer keeps them in its defaults; Explorer acts on them when told.
public final class FinderSwitches {
    public static let shared = FinderSwitches()
    private var defaults: UserDefaults { SuiteDefaults.explorer }

    private func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }

    public var usesExplorer: Bool {
        get { bool("UseExplorer", true) }
        set { defaults.set(newValue, forKey: "UseExplorer") }
    }

    public var opensFoldersFromOtherApps: Bool {
        get { bool("OpenFoldersFromOtherApps", true) }
        set { defaults.set(newValue, forKey: "OpenFoldersFromOtherApps") }
    }

    public var keepsFinderClosed: Bool {
        get { bool("QuitFinder", true) }
        set { defaults.set(newValue, forKey: "QuitFinder") }
    }

    public var redirectsFinder: Bool {
        get { bool("RedirectFinder", false) }
        set { defaults.set(newValue, forKey: "RedirectFinder") }
    }

    public var asksBeforeRedirecting: Bool {
        get { bool("RedirectFinderAsks", true) }
        set { defaults.set(newValue, forKey: "RedirectFinderAsks") }
    }
}

/// The menu bar extra's switch, in Explorer's defaults.
public enum MenuBarIcon {
    public static var isShown: Bool {
        get { SuiteDefaults.explorer.bool(forKey: "ShowMenuBarIcon") }
        set { SuiteDefaults.explorer.set(newValue, forKey: "ShowMenuBarIcon") }
    }
}
