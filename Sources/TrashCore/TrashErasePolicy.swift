import Foundation

/// What Suite Trash, running as root, agrees to erase: only items inside one of the caller's Trash
/// folders, the same ones `SuiteCore`'s `TrashLocations` gathers (the home `.Trash`, iCloud Drive's
/// `~/Library/Mobile Documents/.Trash` and each disk's `.Trashes/<uid>`). The helper can't link SuiteCore
/// (AppKit, the user's defaults), so the list is built here again; a test keeps both the same.
public enum TrashErasePolicy {

    /// A Trash folder: a trusted base, resolved as it is (the home folder, a mounted disk), then folders
    /// below it the user owns and could replace with symbolic links, so none of them may be one.
    public struct Root: Equatable, Sendable {
        public let base: String
        public let components: [String]

        public init(base: String, components: [String]) {
            self.base = base
            self.components = components
        }

        public var path: String { ([base] + components).joined(separator: "/") }
    }

    /// The caller's Trash folders: the home one, iCloud Drive's, then each disk's but the startup disk's
    /// (whose Trash is the home one).
    public static func roots(home: String, volumes: [String], uid: uid_t) -> [Root] {
        var roots = [Root(base: home, components: [".Trash"]),
                     Root(base: home, components: ["Library", "Mobile Documents", ".Trash"])]
        for volume in volumes where standardized(volume) != "/" {
            roots.append(Root(base: volume, components: [".Trashes", "\(uid)"]))
        }
        return roots
    }

    /// Why a path is refused.
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case notAbsolute(String)
        case notAnItem(String)
        case notFound(String)
        case outsideTrash(String)

        public var description: String {
            switch self {
            case .notAbsolute(let path): "\u{201C}\(path)\u{201D} wasn't erased: its path isn't a full path."
            case .notAnItem(let path): "\u{201C}\(path)\u{201D} wasn't erased: it doesn't name an item."
            case .notFound(let path): "\u{201C}\(name(path))\u{201D} wasn't erased: its folder no longer exists."
            case .outsideTrash(let path): "\u{201C}\(name(path))\u{201D} wasn't erased: it isn't in the Trash."
            }
        }

        private func name(_ path: String) -> String { (path as NSString).lastPathComponent }
    }

    /// The path to erase, its folder resolved (symbolic links and `..`), if it is inside one of `roots`
    /// and isn't one of them. The item itself is kept as it is: a symbolic link in the Trash is erased,
    /// not what it points to.
    public static func check(_ path: String, roots: [Root],
                             resolve: (String) -> String? = realPath,
                             isSymbolicLink: (String) -> Bool = isSymbolicLink) -> Result<String, Refusal> {
        guard path.hasPrefix("/") else { return .failure(.notAbsolute(path)) }
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        let name = (trimmed as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name != "/" else { return .failure(.notAnItem(path)) }
        guard let folder = resolve((trimmed as NSString).deletingLastPathComponent)
        else { return .failure(.notFound(path)) }
        let item = folder == "/" ? "/" + name : folder + "/" + name
        let trashes = roots.compactMap { canonical($0, resolve: resolve, isSymbolicLink: isSymbolicLink) }
        guard trashes.contains(where: { item.hasPrefix($0 + "/") }) else { return .failure(.outsideTrash(path)) }
        return .success(item)
    }

    /// The root's real path, or nil when it doesn't exist or a folder below its base is a symbolic link.
    static func canonical(_ root: Root, resolve: (String) -> String?,
                          isSymbolicLink: (String) -> Bool) -> String? {
        guard var path = resolve(root.base) else { return nil }
        for component in root.components {
            guard !component.isEmpty, component != ".", component != "..", !component.contains("/")
            else { return nil }
            path = path == "/" ? "/" + component : path + "/" + component
            if isSymbolicLink(path) { return nil }
        }
        // Exists, and is what it says once resolved (nothing swapped along the way).
        guard resolve(path) == path else { return nil }
        return path
    }

    /// `realpath(3)`: symbolic links and `..` resolved; nil when the path doesn't exist.
    public static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    public static func isSymbolicLink(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }

    private static func standardized(_ path: String) -> String {
        (path as NSString).standardizingPath
    }
}
