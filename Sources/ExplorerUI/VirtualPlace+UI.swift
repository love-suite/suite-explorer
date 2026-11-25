import AppKit
import ExplorerCore
import IOKit.ps
import SystemConfiguration

extension VirtualPlace {
    /// As Finder names it; this Mac by the name it has in System Settings.
    var title: String {
        switch self {
        case .recents: return UIL("Recents")
        case .shared: return UIL("Shared")
        case .computer: return ThisMac.name
        }
    }

    var glyph: SidebarGlyph {
        switch self {
        case .recents: return .symbol("clock")
        case .shared: return .symbol("person.2")
        case .computer: return ThisMac.isLaptop ? .symbol("laptopcomputer")
                                                : .symbol("desktopcomputer")
        }
    }

    /// The title of a pane showing `url`: the place's, or the folder's as Finder shows it.
    static func title(of url: URL) -> String {
        VirtualPlace(url: url)?.title ?? FileManager.default.displayName(atPath: url.path)
    }
}

/// A sidebar icon: Finder's own glyph, read from the system as file icons are (never shipped with the
/// app), else an SF Symbol. A template, tinted by whoever draws it.
struct SidebarGlyph {
    let file: String?
    let symbol: String

    static func finder(_ file: String, or symbol: String) -> SidebarGlyph { SidebarGlyph(file: file, symbol: symbol) }
    static func symbol(_ name: String) -> SidebarGlyph { SidebarGlyph(file: nil, symbol: name) }

    private static var cache: [String: NSImage] = [:]
    private static let folder = URL(fileURLWithPath: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources")

    var image: NSImage? {
        let key = file ?? symbol
        if let cached = Self.cache[key] { return cached }
        let image = file.flatMap { NSImage(contentsOf: Self.folder.appendingPathComponent($0 + ".icns")) }
            ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        image?.isTemplate = true
        Self.cache[key] = image
        return image
    }
}

enum ThisMac {
    static let name = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? UIL("This Mac")

    /// A laptop runs on an internal battery.
    static let isLaptop: Bool = {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        return sources.contains { source in
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }()
}
