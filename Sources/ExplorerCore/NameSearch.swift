import Foundation

/// Finds items by name inside folders by walking them, beside Spotlight: it also finds what Spotlight
/// doesn't index (folders it skips, disks without an index, files just created). Names match as in
/// Finder: every word typed, in any order, ignoring case and accents.
public enum NameSearch {
    /// True if every word of `text` appears in `name`.
    public static func matches(_ name: String, _ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return false }
        return words.allSatisfy { name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Walks `folders` and reports matching items in batches of `batchSize` (and a last, smaller one),
    /// stopping after `limit` matches or `maxVisited` items, or once `isCancelled` says so. Packages
    /// (apps, bundles) count as files: their insides are not searched.
    public static func search(_ text: String, in folders: [URL], showHidden: Bool = false, limit: Int = 2000,
                              maxVisited: Int = 400_000, batchSize: Int = 50,
                              isCancelled: () -> Bool = { false }, report: ([URL]) -> Void) {
        var found = 0, visited = 0
        var batch: [URL] = []
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !showHidden { options.insert(.skipsHiddenFiles) }
        // Nested folders (both a folder and one inside it) are walked once.
        let roots = folders.map(\.standardizedFileURL).filter { folder in
            !folders.map(\.standardizedFileURL).contains { other in
                other != folder && folder.path.hasPrefix(other.path == "/" ? "/" : other.path + "/")
            }
        }
        outer: for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                              options: options, errorHandler: { _, _ in true })
            else { continue }
            for case let url as URL in walker {
                visited += 1
                if visited % 500 == 0, isCancelled() { break outer }
                guard matches(url.lastPathComponent, text) else {
                    if visited >= maxVisited { break outer }
                    continue
                }
                batch.append(url)
                found += 1
                if batch.count >= batchSize {
                    report(batch)
                    batch = []
                }
                if found >= limit || visited >= maxVisited { break outer }
            }
        }
        if !batch.isEmpty, !isCancelled() { report(batch) }
    }
}
