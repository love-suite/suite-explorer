import Foundation
import SuiteCore
import SuiteFilesCore

/// What the sidebar of Explorer windows shows, in Finder's order: Recents and Shared, the Favorites (the
/// pinned folders), then the Locations: iCloud Drive, cloud storage, this Mac, its disks, AirDrop and the
/// Trash. Each one can be turned off.
public enum SidebarPlace: String, CaseIterable, Codable, Sendable {
    case recents, shared
    /// Saved under its former name, so the choice made for Quick access carries over.
    case favorites = "quickAccess"
    case iCloudDrive, cloudStorage, computer, disks, airDrop, trash

    public var title: String {
        switch self {
        case .recents: return "Recents"
        case .shared: return "Shared"
        case .favorites: return "Favorites"
        case .iCloudDrive: return "iCloud Drive"
        case .cloudStorage: return "Cloud storage: Google Drive, OneDrive and others"
        case .computer: return "This Mac"
        case .disks: return "Disks"
        case .airDrop: return "AirDrop"
        case .trash: return "Trash"
        }
    }

    public static let shownByDefault: Set<SidebarPlace> = Set(allCases)

    /// The folder this place stands for, under `home`; nil for the places that are lists or actions.
    public func url(home: URL) -> URL? {
        switch self {
        case .iCloudDrive:
            return home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        case .trash: return home.appendingPathComponent(".Trash", isDirectory: true)
        default: return nil
        }
    }

    /// Where File Provider apps (Google Drive, OneDrive, Dropbox) keep their folders.
    public static func cloudStorageFolder(home: URL) -> URL {
        home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
    }
}

/// The places the user chose to show, saved in the defaults.
public struct SidebarPlaces: Equatable, Sendable {
    public private(set) var shown: Set<SidebarPlace>

    public init(shown: Set<SidebarPlace> = SidebarPlace.shownByDefault) {
        self.shown = shown
    }

    public func contains(_ place: SidebarPlace) -> Bool { shown.contains(place) }

    public mutating func set(_ place: SidebarPlace, shown isShown: Bool) {
        if isShown { shown.insert(place) } else { shown.remove(place) }
    }

    /// The shown places in the sidebar's order, `exists` leaving out what this Mac doesn't have (iCloud
    /// Drive turned off, for instance).
    public func ordered(exists: (SidebarPlace) -> Bool = { _ in true }) -> [SidebarPlace] {
        SidebarPlace.allCases.filter { shown.contains($0) && exists($0) }
    }

    // MARK: Defaults

    private static let key = "SidebarPlaces"

    /// Saved as the list of shown places; places added in later versions get their default, and places
    /// of earlier versions are forgotten.
    public static func load(from defaults: UserDefaults = SuiteDefaults.explorer) -> SidebarPlaces {
        guard let saved = defaults.dictionary(forKey: key) as? [String: Bool] else { return SidebarPlaces() }
        var places = SidebarPlaces()
        for place in SidebarPlace.allCases {
            if let isShown = saved[place.rawValue] { places.set(place, shown: isShown) }
        }
        return places
    }

    public func save(to defaults: UserDefaults = SuiteDefaults.explorer) {
        let values = Dictionary(uniqueKeysWithValues: SidebarPlace.allCases.map { ($0.rawValue, shown.contains($0)) })
        defaults.set(values, forKey: Self.key)
    }
}
