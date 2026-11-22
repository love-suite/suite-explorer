import Foundation
import Testing
@testable import ExplorerCore

@Suite struct VolumesTests {
    private func volume(_ path: String, inside: Bool = false, local: Bool = true, removable: Bool = false,
                        ejectable: Bool = false, root: Bool = false) -> VolumeInfo {
        VolumeInfo(url: URL(fileURLWithPath: path), name: "Disk", isInternal: inside, isLocal: local,
                   isRemovable: removable, isEjectable: ejectable, isRootFileSystem: root)
    }

    @Test func ejectableAsInFinder() {
        #expect(!volume("/", inside: true, root: true).canEject)
        #expect(!volume("/Volumes/Data", inside: true).canEject)
        #expect(volume("/Volumes/USB", removable: true, ejectable: true).canEject)
        #expect(volume("/Volumes/SSD").canEject, "an external disk, even one macOS doesn't call ejectable")
        #expect(volume("/Volumes/Installer", inside: true, ejectable: true).canEject, "a disk image")
        #expect(volume("/Volumes/share", local: false).canEject, "a network share")
    }

    @Test func kinds() {
        #expect(volume("/", inside: true, root: true).kind == .internalDisk)
        #expect(volume("/Volumes/USB", removable: true).kind == .externalDisk)
        #expect(volume("/Volumes/share", local: false).kind == .network)
    }

    @Test func pathsOnAVolume() {
        let usb = volume("/Volumes/USB")
        #expect(usb.contains(URL(fileURLWithPath: "/Volumes/USB")))
        #expect(usb.contains(URL(fileURLWithPath: "/Volumes/USB/Photos/a.jpg")))
        #expect(!usb.contains(URL(fileURLWithPath: "/Volumes/USB2")))
        #expect(!usb.contains(URL(fileURLWithPath: "/Users/me")))
        #expect(VolumeInfo.path("/Users/me", isOn: "/"))
    }

    @Test func serverAddresses() {
        #expect(ServerAddress.url(from: "smb://nas.local/Media")?.absoluteString == "smb://nas.local/Media")
        #expect(ServerAddress.url(from: "  nas.local/Media ")?.absoluteString == "smb://nas.local/Media")
        #expect(ServerAddress.url(from: #"\\NAS\Media\Films"#)?.absoluteString == "smb://NAS/Media/Films")
        #expect(ServerAddress.url(from: "afp://old-mac.local")?.scheme == "afp")
        #expect(ServerAddress.url(from: "smb://nas.local/My Share")?.path == "/My Share")
        #expect(ServerAddress.url(from: "") == nil)
        #expect(ServerAddress.url(from: "smb://") == nil)
        #expect(ServerAddress.url(from: "file:///Users") == nil)
        #expect(ServerAddress.url(from: "javascript://x") == nil)
    }

    @Test func screenSharingIsNotADisk() {
        #expect(ServerAddress.mountsAsDisk(URL(string: "smb://nas.local")!))
        #expect(ServerAddress.mountsAsDisk(URL(string: "https://dav.example.com")!))
        #expect(!ServerAddress.mountsAsDisk(URL(string: "VNC://mac.local")!))
    }

    @Test func sameServer() {
        let address = URL(string: "smb://NAS.local/Media")!
        #expect(ServerAddress.isSameServer(URL(string: "smb://me@nas.local/Media")!, as: address))
        #expect(!ServerAddress.isSameServer(URL(string: "smb://other.local/Media")!, as: address))
    }

    @Test func recentServersNewestFirstOnce() {
        var list: [String] = []
        list = RecentServers.adding("smb://a", to: list)
        list = RecentServers.adding("smb://b", to: list)
        list = RecentServers.adding("SMB://A", to: list)
        #expect(list == ["SMB://A", "smb://b"])
        #expect(RecentServers.adding("  ", to: list) == list)
        let many = (0..<20).reduce(into: [String]()) { list, index in list = RecentServers.adding("smb://\(index)", to: list) }
        #expect(many.count == RecentServers.limit)
        #expect(many.first == "smb://19")
    }

    @Test func recentServersStored() {
        let name = "VolumesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let recents = RecentServers(defaults: defaults)
        recents.add("smb://nas.local")
        recents.add("afp://old.local")
        #expect(recents.addresses == ["afp://old.local", "smb://nas.local"])
        recents.clear()
        #expect(recents.addresses.isEmpty)
    }

    @Test func diskImages() {
        #expect(DiskImage.isDiskImage(URL(fileURLWithPath: "/tmp/App.DMG")))
        #expect(DiskImage.isDiskImage(URL(fileURLWithPath: "/tmp/linux.iso")))
        #expect(!DiskImage.isDiskImage(URL(fileURLWithPath: "/tmp/Installer.pkg")))
        #expect(DiskImage.attachArguments(for: URL(fileURLWithPath: "/tmp/A B.dmg")) == ["attach", "-plist", "/tmp/A B.dmg"])
    }

    @Test func mountPointsReadFromHdiutil() {
        let output = """
        Expected checksum: verified
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>system-entities</key>
            <array>
                <dict><key>content-hint</key><string>GUID_partition_scheme</string>
                      <key>dev-entry</key><string>/dev/disk4</string></dict>
                <dict><key>content-hint</key><string>Apple_HFS</string>
                      <key>dev-entry</key><string>/dev/disk4s1</string>
                      <key>mount-point</key><string>/Volumes/My App</string></dict>
            </array>
        </dict>
        </plist>
        """
        #expect(DiskImage.mountPoints(fromAttachOutput: Data(output.utf8)).map(\.path) == ["/Volumes/My App"])
        #expect(DiskImage.mountPoints(fromAttachOutput: Data("hdiutil: attach failed".utf8)).isEmpty)
    }
}
