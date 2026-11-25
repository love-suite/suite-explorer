import Foundation

/// The sidebar's places that aren't folders, as Finder has them: Recents, Shared, and this computer with
/// its disks. Each has an address of its own (`explorer:recents`), so a pane can go there and back like a
/// folder; what it shows is a list of items, as search results are.
public enum VirtualPlace: String, CaseIterable, Sendable {
    case recents, shared, computer

    public static let scheme = "explorer"

    public var url: URL { URL(string: "\(Self.scheme):\(rawValue)")! }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let name = (url as NSURL).resourceSpecifier,
              let place = VirtualPlace(rawValue: name) else { return nil }
        self = place
    }
}
