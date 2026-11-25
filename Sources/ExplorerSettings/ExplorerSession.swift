import Foundation
import SuiteCore

/// The Explorer windows open, kept as they change so they come back as they were after a quit, a restart
/// or a crash: each window's place and size, its tabs in order with the one in front, and for each tab its
/// folder, the second folder Side by Side, and the preview pane. A folder's view (icons, list, sorting) is
/// already remembered per folder.
public struct ExplorerSession: Codable, Equatable, Sendable {
    /// One tab (or a window without tabs).
    public struct Tab: Codable, Equatable, Sendable {
        /// The folder, then the second one Side by Side.
        public var folders: [String]
        /// Which of the two folders is active.
        public var activePane: Int
        public var showsPreview: Bool

        public init(folders: [String], activePane: Int = 0, showsPreview: Bool = false) {
            self.folders = folders
            self.activePane = activePane
            self.showsPreview = showsPreview
        }
    }

    /// One window: its frame and its tabs.
    public struct Window: Codable, Equatable, Sendable {
        public var frame: [Double]
        public var tabs: [Tab]
        public var selectedTab: Int

        public init(frame: CGRect, tabs: [Tab], selectedTab: Int = 0) {
            self.frame = [frame.minX, frame.minY, frame.width, frame.height].map(Double.init)
            self.tabs = tabs
            self.selectedTab = selectedTab
        }

        public var rect: CGRect {
            guard frame.count == 4 else { return .zero }
            return CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])
        }
    }

    public var windows: [Window]

    public init(windows: [Window] = []) {
        self.windows = windows
    }

    /// The same session without the folders that are gone (a disk unplugged, a folder deleted): a tab
    /// keeps the folders left, a tab with none is dropped, and a window with no tab too.
    public func existing(_ exists: (String) -> Bool) -> ExplorerSession {
        var kept: [Window] = []
        for var window in windows {
            let selected = window.tabs.indices.contains(window.selectedTab) ? window.tabs[window.selectedTab] : nil
            window.tabs = window.tabs.compactMap { tab in
                var tab = tab
                tab.folders = tab.folders.filter(exists)
                guard !tab.folders.isEmpty else { return nil }
                tab.activePane = min(tab.activePane, tab.folders.count - 1)
                return tab
            }
            guard !window.tabs.isEmpty else { continue }
            window.selectedTab = selected.flatMap { old in window.tabs.firstIndex { $0.folders.first == old.folders.first } } ?? 0
            kept.append(window)
        }
        return ExplorerSession(windows: kept)
    }

    // MARK: Defaults

    private static let key = "ExplorerSession"

    public static func load(from defaults: UserDefaults = SuiteDefaults.explorer) -> ExplorerSession {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ExplorerSession.self, from: $0) } ?? ExplorerSession()
    }

    public func save(to defaults: UserDefaults = SuiteDefaults.explorer) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}
