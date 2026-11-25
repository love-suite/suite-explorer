import Foundation
import SuiteCore

/// The pinned folders at the top of the sidebar: Windows' Quick access, Finder's Favorites.
public final class QuickAccessStore {
    public static let shared = QuickAccessStore()
    public static let didChange = Notification.Name("QuickAccessDidChange")
    private static let key = "QuickAccessFolders"

    private let defaults: UserDefaults
    private let home: URL

    public init(defaults: UserDefaults = SuiteDefaults.explorer,
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.defaults = defaults
        self.home = home
    }

    /// Finder's Favorites (Applications, Desktop, Documents, Downloads) until the user changes the list.
    public var folders: [URL] {
        guard let paths = defaults.stringArray(forKey: Self.key) else {
            return [URL(fileURLWithPath: "/Applications", isDirectory: true)]
                + ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0, isDirectory: true) }
        }
        return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    public func isPinned(_ url: URL) -> Bool {
        folders.contains { $0.standardizedFileURL.path == url.standardizedFileURL.path }
    }

    /// Adds a folder at the end, or at `index`; a folder already there moves instead.
    public func pin(_ url: URL, at index: Int? = nil) {
        var list = folders.filter { $0.standardizedFileURL.path != url.standardizedFileURL.path }
        list.insert(url.standardizedFileURL, at: min(max(index ?? list.count, 0), list.count))
        save(list)
    }

    public func unpin(_ url: URL) {
        save(folders.filter { $0.standardizedFileURL.path != url.standardizedFileURL.path })
    }

    private func save(_ list: [URL]) {
        defaults.set(list.map(\.standardizedFileURL.path), forKey: Self.key)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
