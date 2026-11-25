import ExplorerCore
import ExplorerSettings
import Foundation
import SuiteFilesCore

/// What a place that isn't a folder holds, as Finder shows it: Recents, the files opened in the last 30
/// days (Spotlight); Shared, what is shared in iCloud Drive; this Mac, its disks. Items are read off the
/// main thread and arrive on it, once.
final class PlaceContents {
    static let limit = 500

    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private var cancelled = false
    private let onItems: ([FileItem]) -> Void
    private static let work = DispatchQueue(label: "Explorer.PlaceContents", qos: .userInitiated)

    init(_ place: VirtualPlace, onItems: @escaping ([FileItem]) -> Void) {
        self.onItems = onItems
        switch place {
        case .recents: startRecents()
        case .shared: read(Self.sharedInICloudDrive)
        case .computer: read(Self.disks)
        }
    }

    func stop() {
        cancelled = true
        query?.stop()
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil
    }

    deinit { stop() }

    private func read(_ urls: @escaping () -> [URL]) {
        Self.work.async { [weak self] in
            let items = urls().prefix(Self.limit).map(DirectoryLoader.item(at:))
            DispatchQueue.main.async {
                guard let self, !self.cancelled else { return }
                self.onItems(Array(items))
            }
        }
    }

    // MARK: Recents

    private func startRecents() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(fromMetadataQueryString: "kMDItemLastUsedDate >= $time.today(-30)")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering,
                                                          object: query, queue: .main) { [weak self] _ in
            self?.takeRecents()
        }
        self.query = query
        query.start()
    }

    private func takeRecents() {
        guard let query else { return }
        query.stop()
        let paths = (0..<query.resultCount).compactMap {
            (query.result(at: $0) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String
        }
        read { paths.map(URL.init(fileURLWithPath:)).filter(Self.isRecentDocument) }
    }

    /// Documents, as Finder's Recents lists them: no folders, apps or files the system keeps in the Library
    /// (iCloud Drive excepted).
    private static func isRecentDocument(_ url: URL) -> Bool {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path + "/"
        let mobileDocuments = library + "Mobile Documents/"
        if url.path.hasPrefix(library) && !url.path.hasPrefix(mobileDocuments) { return false }
        if url.pathComponents.contains(where: { $0.hasPrefix(".") }) { return false }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory != true && values?.isPackage != true
    }

    // MARK: Shared

    /// The items of iCloud Drive shared with others or by others; what a shared folder holds isn't listed
    /// on its own.
    private static func sharedInICloudDrive() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let drive = SidebarPlace.iCloudDrive.url(home: home) else { return [] }
        let keys: [URLResourceKey] = [.ubiquitousSharedItemCurrentUserRoleKey, .isPackageKey]
        guard let walk = FileManager.default.enumerator(at: drive, includingPropertiesForKeys: keys,
                                                        options: [.skipsHiddenFiles]) else { return [] }
        var shared: [URL] = []
        var visited = 0
        for case let url as URL in walk {
            visited += 1
            if visited > 50_000 || shared.count >= limit { break }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.ubiquitousSharedItemCurrentUserRole != nil {
                shared.append(url)
                walk.skipDescendants()
            } else if values?.isPackage == true {
                walk.skipDescendants()
            }
        }
        return shared
    }

    // MARK: This Mac

    private static func disks() -> [URL] {
        FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
    }
}
