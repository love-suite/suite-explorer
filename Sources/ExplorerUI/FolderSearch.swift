import ExplorerCore
import Foundation
import SuiteFilesCore

/// A search as you type, for the toolbar's search box: Spotlight (names, and contents from three
/// letters) over the whole Mac or the chosen folders, and for folders also a walk of the folders by
/// name, which finds what Spotlight doesn't index. Spotlight's answer shows at once (a fraction of a
/// second); the walk adds what it finds behind it, without holding anything up. Results arrive merged on
/// the main thread, with whether the walk is still going; items are read off the main thread.
final class FolderSearch {
    static let limit = 2000

    private let query = NSMetadataQuery()
    private let onResults: (_ items: [FileItem], _ stillLooking: Bool) -> Void
    private var observers: [NSObjectProtocol] = []
    private let work = DispatchQueue(label: "Explorer.FolderSearch", qos: .userInitiated)
    private let walk = DispatchQueue(label: "Explorer.FolderSearch.walk", qos: .utility)
    // Touched on the main thread only.
    private var spotlight: [URL] = []
    private var walked: [URL] = []
    private var items: [URL: FileItem] = [:]
    private var delivered = 0
    // "No results" waits for Spotlight's answer, not for the walk.
    private var spotlightDone = false
    private var walkDone = true
    private var cancelled = false
    private let cancelFlag = CancelFlag()

    /// `folders` empty: the whole Mac.
    init(text: String, in folders: [URL], showHidden: Bool,
         onResults: @escaping (_ items: [FileItem], _ stillLooking: Bool) -> Void) {
        self.onResults = onResults
        query.predicate = Self.predicate(for: text)
        query.searchScopes = folders.isEmpty ? [NSMetadataQueryLocalComputerScope] : folders
        query.notificationBatchingInterval = 0.1
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryGatheringProgress,
                     .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) {
                [weak self] note in
                if note.name == .NSMetadataQueryDidFinishGathering { self?.spotlightDone = true }
                self?.takeSpotlightResults()
            })
        }
        query.start()

        guard !folders.isEmpty else { return }
        walkDone = false
        let flag = cancelFlag
        walk.async { [weak self] in
            NameSearch.search(text, in: folders, showHidden: showHidden, limit: Self.limit,
                              isCancelled: { flag.isSet }) { batch in
                let read = batch.map(DirectoryLoader.item(at:))
                DispatchQueue.main.async {
                    guard let self, !self.cancelled else { return }
                    for item in read { self.items[item.url] = item }
                    self.walked += batch
                    self.deliver()
                }
            }
            DispatchQueue.main.async {
                guard let self, !self.cancelled else { return }
                self.walkDone = true
                self.deliver()
            }
        }
    }

    /// Spotlight's own syntax: every word typed in the name, or the text in the contents from three letters.
    private static func predicate(for text: String) -> NSPredicate {
        func escaped(_ word: Substring) -> String {
            word.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "*", with: "\\*")
        }
        let words = text.split(whereSeparator: \.isWhitespace)
        let name = words.map { "kMDItemFSName == \"*\(escaped($0))*\"cd" }.joined(separator: " && ")
        var query = "(\(name))"
        if text.count >= 3 {
            query += " || kMDItemTextContent == \"\(escaped(Substring(text)))*\"cdw"
        }
        return NSPredicate(fromMetadataQueryString: query) ?? NSPredicate(format: "%K LIKE[cd] %@",
                                                                           NSMetadataItemFSNameKey, "*\(text)*")
    }

    private func takeSpotlightResults() {
        query.disableUpdates()
        let count = min(query.resultCount, Self.limit)
        var urls: [URL] = []
        urls.reserveCapacity(count)
        for index in 0..<count {
            if let item = query.result(at: index) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                urls.append(URL(fileURLWithPath: path))
            }
        }
        query.enableUpdates()
        let missing = urls.filter { items[$0] == nil }
        guard !missing.isEmpty else {
            spotlight = urls
            deliver()
            return
        }
        work.async { [weak self] in
            let read = missing.map(DirectoryLoader.item(at:))
            DispatchQueue.main.async {
                guard let self, !self.cancelled else { return }
                for item in read { self.items[item.url] = item }
                self.spotlight = urls
                self.deliver()
            }
        }
    }

    private var deliveryPending = false

    /// Spotlight's results, then the walk's that Spotlight didn't find; at most ten times a second, the
    /// first ones at once.
    private func deliver() {
        guard !deliveryPending else { return }
        if delivered == 0 {
            deliverNow()
            return
        }
        deliveryPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, !self.cancelled else { return }
            self.deliveryPending = false
            self.deliverNow()
        }
    }

    private func deliverNow() {
        var seen = Set<URL>()
        var results: [FileItem] = []
        for url in spotlight + walked where seen.insert(url).inserted {
            guard let item = items[url] else { continue }
            results.append(item)
            if results.count >= Self.limit { break }
        }
        if results.isEmpty && !spotlightDone { return }
        delivered += 1
        onResults(results, !walkDone)
    }

    func stop() {
        cancelled = true
        cancelFlag.set()
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    deinit { stop() }
}

/// Tells the walk, on its own queue, to stop.
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
