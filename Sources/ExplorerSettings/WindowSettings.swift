import SuiteCore
import Foundation

/// How Explorer windows open, shared by the windows, the menus and the settings window.
public enum WindowSettings {
    public static let didChange = Notification.Name("ExplorerWindowSettingsDidChange")
    private static let tabsKey = "UseTabs"
    private static let newTabKey = "OpenFoldersInNewTab"
    private static let oneWindowKey = "SideBySideInOneWindow"
    private static let labelsKey = "ShowToolbarLabels"

    /// How a folder tree is shown: not at all, as a narrow strip of icons, or icons with their names.
    public enum SidebarStyle: String, CaseIterable, Sendable {
        case hidden, icons, iconsAndNames
    }

    /// The folder tree on the left of every window.
    public static var leftSidebar: SidebarStyle {
        get { style(for: "LeftSidebar") }
        set { setStyle(newValue, for: "LeftSidebar") }
    }

    /// The second folder's tree, on the right while Side by Side.
    public static var rightSidebar: SidebarStyle {
        get { style(for: "RightSidebar") }
        set { setStyle(newValue, for: "RightSidebar") }
    }

    /// The style a hidden sidebar comes back in: the last one it was shown in.
    public static func shownStyle(left: Bool) -> SidebarStyle {
        let stored = SuiteDefaults.explorer.string(forKey: (left ? "LeftSidebar" : "RightSidebar") + "Shown")
        return stored.flatMap(SidebarStyle.init(rawValue:)) ?? .iconsAndNames
    }

    private static func style(for key: String) -> SidebarStyle {
        SuiteDefaults.explorer.string(forKey: key).flatMap(SidebarStyle.init(rawValue:)) ?? .iconsAndNames
    }

    private static func setStyle(_ style: SidebarStyle, for key: String) {
        SuiteDefaults.explorer.set(style.rawValue, forKey: key)
        if style != .hidden { SuiteDefaults.explorer.set(style.rawValue, forKey: key + "Shown") }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Opens the settings window on a tab (set by the app).
    public static var openSettings: ((_ tab: String) -> Void)?

    /// What the folder trees show (Quick access, home, Desktop, disks, Trash…).
    public static var sidebarPlaces: SidebarPlaces {
        get { SidebarPlaces.load() }
        set {
            newValue.save()
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Windows can hold several folders as tabs. On by default; off, every folder gets its own window.
    /// The toolbar's buttons show their name beside their icon, as Windows 11's command bar does; off
    /// (the default), icons only, the name in the tooltip.
    public static var showsToolbarLabels: Bool {
        get { SuiteDefaults.explorer.object(forKey: labelsKey) as? Bool ?? false }
        set { set(newValue, for: labelsKey) }
    }

    /// Which toolbar commands show as buttons, in the + menu, or nowhere.
    public static var toolbarLayout: ToolbarLayout {
        get { ToolbarLayout.load() }
        set {
            newValue.save()
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Restoring an item from the Trash opens the folder it went back to, with it selected. Off by
    /// default: the Trash stays in front.
    public static var opensFolderAfterRestore: Bool {
        get { SuiteDefaults.explorer.object(forKey: "OpenFolderAfterRestore") as? Bool ?? false }
        set { set(newValue, for: "OpenFolderAfterRestore") }
    }

    /// How wide new Explorer windows open (Settings › Toolbar can set it from its own width).
    public static var newWindowWidth: CGFloat {
        get { CGFloat(SuiteDefaults.explorer.object(forKey: "NewWindowWidth") as? Double ?? 1000) }
        set {
            SuiteDefaults.explorer.set(Double(newValue.rounded()), forKey: "NewWindowWidth")
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Explorer windows open last time come back at launch, after a restart or a crash too. On by default.
    public static var reopensWindows: Bool {
        get { SuiteDefaults.explorer.object(forKey: "ReopenWindows") as? Bool ?? true }
        set { set(newValue, for: "ReopenWindows") }
    }

    public static var usesTabs: Bool {
        get { SuiteDefaults.explorer.object(forKey: tabsKey) as? Bool ?? true }
        set { set(newValue, for: tabsKey) }
    }

    /// Folders opened from the desktop or other apps join the frontmost window as a new tab, as in
    /// Windows 11, instead of opening a window of their own. On by default; needs tabs.
    public static var opensFoldersInNewTab: Bool {
        get { usesTabs && (SuiteDefaults.explorer.object(forKey: newTabKey) as? Bool ?? true) }
        set { set(newValue, for: newTabKey) }
    }

    /// Side by Side shows the two folders in the same window, as two panes. On by default; off, they
    /// are two windows, each on half of the screen.
    public static var sideBySideInOneWindow: Bool {
        get { SuiteDefaults.explorer.object(forKey: oneWindowKey) as? Bool ?? true }
        set { set(newValue, for: oneWindowKey) }
    }

    private static func set(_ value: Bool, for key: String) {
        SuiteDefaults.explorer.set(value, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
