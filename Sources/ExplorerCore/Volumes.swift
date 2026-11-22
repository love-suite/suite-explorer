import Foundation
import SuiteCore

/// A mounted disk as the sidebar and This Mac show it: its name, its kind, whether it can be ejected.
public struct VolumeInfo: Equatable {
    public enum Kind: Equatable { case internalDisk, externalDisk, network }

    public let url: URL
    public let name: String
    public let kind: Kind
    /// Removable disks, disk images and network shares, as Finder offers them an eject button; never the
    /// startup disk nor another internal disk.
    public let canEject: Bool

    public static let resourceKeys: Set<URLResourceKey> = [
        .volumeLocalizedNameKey, .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsRemovableKey,
        .volumeIsEjectableKey, .volumeIsRootFileSystemKey,
    ]

    public init(url: URL, name: String, isInternal: Bool, isLocal: Bool, isRemovable: Bool, isEjectable: Bool,
                isRootFileSystem: Bool) {
        self.url = url
        self.name = name
        kind = !isLocal ? .network : isInternal ? .internalDisk : .externalDisk
        canEject = !isRootFileSystem && (isEjectable || isRemovable || !isLocal || !isInternal)
    }

    /// Reads the volume's properties; nil when it can't be read (it was just unmounted).
    public init?(url: URL) {
        guard let values = try? url.resourceValues(forKeys: Self.resourceKeys) else { return nil }
        self.init(url: url, name: values.volumeLocalizedName ?? url.lastPathComponent,
                  isInternal: values.volumeIsInternal ?? false,
                  isLocal: values.volumeIsLocal ?? true,
                  isRemovable: values.volumeIsRemovable ?? false,
                  isEjectable: values.volumeIsEjectable ?? false,
                  isRootFileSystem: values.volumeIsRootFileSystem ?? (url.path == "/"))
    }

    /// The disks mounted now, as Finder lists them (hidden system volumes left out).
    public static func mounted() -> [VolumeInfo] {
        (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(resourceKeys),
                                               options: [.skipHiddenVolumes]) ?? []).compactMap(VolumeInfo.init(url:))
    }

    /// Whether `url` is the volume itself or lies on it.
    public func contains(_ url: URL) -> Bool {
        Self.path(url.standardizedFileURL.path, isOn: self.url.standardizedFileURL.path)
    }

    /// Whether `path` is `volumePath` or inside it; "/" holds everything, "/Volumes/A" not "/Volumes/AB".
    public static func path(_ path: String, isOn volumePath: String) -> Bool {
        let volume = volumePath.hasSuffix("/") ? String(volumePath.dropLast()) : volumePath
        if volume.isEmpty { return true }
        return path == volume || path.hasPrefix(volume + "/")
    }
}

/// What is typed in Connect to Server, made into the address macOS mounts: `smb://server/share` as is,
/// `server/share` as SMB (Finder's default), and Windows' `\\server\share` too.
public enum ServerAddress {
    /// The schemes Finder connects to: file sharing, WebDAV, FTP (read only), screen sharing.
    public static let schemes: Set<String> = ["smb", "cifs", "afp", "nfs", "ftp", "ftps", "http", "https", "vnc"]

    public static func url(from typed: String) -> URL? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("\\\\") {
            text = "smb://" + text.dropFirst(2).replacingOccurrences(of: "\\", with: "/")
        }
        if !text.contains("://") { text = "smb://" + text }
        guard let components = URLComponents(string: text) ?? URLComponents(string: text.addingPercentEncoding(
                withAllowedCharacters: .urlFragmentAllowed) ?? ""),
              let scheme = components.scheme?.lowercased(), schemes.contains(scheme),
              let host = components.host, !host.isEmpty else { return nil }
        return components.url
    }

    /// Whether the address is a file server mounted as a disk; screen sharing (vnc) opens its own app.
    public static func mountsAsDisk(_ url: URL) -> Bool {
        url.scheme?.lowercased() != "vnc"
    }

    /// Whether a volume that just appeared, remounted from `remountURL`, is the server just connected to.
    public static func isSameServer(_ remountURL: URL, as address: URL) -> Bool {
        guard let one = remountURL.host?.lowercased(), let other = address.host?.lowercased() else { return false }
        return one == other
    }
}

/// The servers connected to lately, newest first, as Connect to Server offers them again.
public struct RecentServers {
    public static let limit = 10
    private static let key = "RecentServers"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = SuiteDefaults.explorer) {
        self.defaults = defaults
    }

    public var addresses: [String] { defaults.stringArray(forKey: Self.key) ?? [] }

    public func add(_ address: String) {
        defaults.set(Self.adding(address, to: addresses), forKey: Self.key)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    /// `address` first, once (case aside), the list cut to `limit`.
    public static func adding(_ address: String, to list: [String], limit: Int = limit) -> [String] {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return list }
        let rest = list.filter { $0.caseInsensitiveCompare(address) != .orderedSame }
        return Array(([address] + rest).prefix(limit))
    }
}

/// Disk images: opening one mounts it and shows what it holds, as Windows does with an ISO.
public enum DiskImage {
    public static let extensions: Set<String> = ["dmg", "iso", "img", "cdr", "sparseimage", "sparsebundle"]

    public static func isDiskImage(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// `hdiutil attach -plist` for the image, its output read by `mountPoints(fromAttachOutput:)`.
    public static func attachArguments(for url: URL) -> [String] {
        ["attach", "-plist", url.path]
    }

    /// The folders `hdiutil attach -plist` mounted the image's volumes on.
    public static func mountPoints(fromAttachOutput data: Data) -> [URL] {
        // hdiutil may print lines before the property list (a licence it was told to skip, warnings).
        let start = data.range(of: Data("<?xml".utf8))?.lowerBound ?? data.startIndex
        guard let plist = try? PropertyListSerialization.propertyList(from: data[start...], format: nil)
                as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else { return [] }
        return entities.compactMap { $0["mount-point"] as? String }.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}
