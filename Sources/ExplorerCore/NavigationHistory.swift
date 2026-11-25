import Foundation

/// Back, forward and up, as in a browser or Windows Explorer.
public struct NavigationHistory {
    public private(set) var current: URL
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    public init(start: URL) {
        current = Self.normalized(start)
    }

    /// "/a", "/a/" and "/a/b/.." must compare equal, so every folder is rebuilt as a directory URL. Places
    /// that aren't folders (Recents) keep their own address.
    private static func normalized(_ url: URL) -> URL {
        guard url.isFileURL else { return url }
        return URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }
    /// Not from the root, nor from a place that isn't a folder.
    public var canGoUp: Bool { current.isFileURL && current.path != "/" }

    /// Visiting a new folder clears the forward history. Visiting the current folder does nothing.
    public mutating func go(to url: URL) {
        let url = Self.normalized(url)
        guard url != current else { return }
        backStack.append(current)
        forwardStack.removeAll()
        current = url
    }

    public mutating func back() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(current)
        current = previous
    }

    public mutating func forward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(current)
        current = next
    }

    public mutating func up() {
        guard canGoUp else { return }
        go(to: current.deletingLastPathComponent())
    }
}
