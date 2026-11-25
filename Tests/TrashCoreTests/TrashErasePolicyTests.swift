import Foundation
import Security
@testable import TrashCore
import SuiteCore
import Testing
import SuiteFilesCore

/// A fake home folder with a Trash, a disk with its own, and a folder outside both, in a temporary folder
/// (resolved, as `/var` is a link to `/private/var`). Nothing is erased: only paths are checked.
private struct Fixture {
    let base: String
    let home: String
    let volume: String
    let uid: uid_t = 501
    var roots: [TrashErasePolicy.Root] { TrashErasePolicy.roots(home: home, volumes: ["/", volume], uid: uid) }

    init() throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("SecureTrash-\(UUID().uuidString)")
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        base = TrashErasePolicy.realPath(temporary.path)!
        home = base + "/Users/me"
        volume = base + "/Volumes/Disk"
        for folder in [home + "/.Trash/Folder", home + "/Library/Mobile Documents/.Trash", home + "/Documents",
                       volume + "/.Trashes/501", volume + "/.Trashes/502"] {
            try fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        for file in [home + "/.Trash/old.txt", home + "/Documents/keep.txt", volume + "/.Trashes/501/old.txt"] {
            fm.createFile(atPath: file, contents: Data("x".utf8))
        }
    }

    func remove() { try? FileManager.default.removeItem(atPath: base) }

    func check(_ path: String) -> Result<String, TrashErasePolicy.Refusal> {
        TrashErasePolicy.check(path, roots: roots)
    }
}

@Suite struct TrashErasePolicyTests {

    @Test func itemsInTheTrashAreAccepted() throws {
        let f = try Fixture()
        defer { f.remove() }
        #expect(f.check(f.home + "/.Trash/old.txt") == .success(f.home + "/.Trash/old.txt"))
        #expect(f.check(f.home + "/.Trash/Folder/") == .success(f.home + "/.Trash/Folder"))
        #expect(f.check(f.home + "/Library/Mobile Documents/.Trash/gone.txt")
                == .success(f.home + "/Library/Mobile Documents/.Trash/gone.txt"))
        #expect(f.check(f.volume + "/.Trashes/501/old.txt") == .success(f.volume + "/.Trashes/501/old.txt"))
    }

    @Test func aPathOutsideTheTrashIsRefused() throws {
        let f = try Fixture()
        defer { f.remove() }
        let path = f.home + "/Documents/keep.txt"
        #expect(f.check(path) == .failure(.outsideTrash(path)))
        #expect(f.check("/etc/hosts") == .failure(.outsideTrash("/etc/hosts")))
        // Another user's Trash on the disk.
        #expect(f.check(f.volume + "/.Trashes/502/x") == .failure(.outsideTrash(f.volume + "/.Trashes/502/x")))
        #expect(TrashErasePolicy.Refusal.outsideTrash(path).description
                == "\u{201C}keep.txt\u{201D} wasn't erased: it isn't in the Trash.")
    }

    @Test func aDotDotEscapeIsRefused() throws {
        let f = try Fixture()
        defer { f.remove() }
        let escape = f.home + "/.Trash/../Documents/keep.txt"
        #expect(f.check(escape) == .failure(.outsideTrash(escape)))
        let deeper = f.home + "/.Trash/Folder/../../Documents"
        #expect(f.check(deeper) == .failure(.outsideTrash(deeper)))
        // The Trash itself, or its parent, isn't an item in it.
        #expect(f.check(f.home + "/.Trash/..") == .failure(.notAnItem(f.home + "/.Trash/..")))
        #expect(f.check(f.home + "/.Trash/Folder/..") == .failure(.notAnItem(f.home + "/.Trash/Folder/..")))
        #expect(f.check(f.home + "/.Trash") == .failure(.outsideTrash(f.home + "/.Trash")))
        #expect(f.check(f.home + "/.Trash/.") == .failure(.notAnItem(f.home + "/.Trash/.")))
    }

    @Test func aFolderLinkOutOfTheTrashIsRefused() throws {
        let f = try Fixture()
        defer { f.remove() }
        try FileManager.default.createSymbolicLink(atPath: f.home + "/.Trash/Documents link",
                                                   withDestinationPath: f.home + "/Documents")
        let through = f.home + "/.Trash/Documents link/keep.txt"
        #expect(f.check(through) == .failure(.outsideTrash(through)))
        // The link itself is an item in the Trash: erasing it leaves what it points to alone.
        #expect(f.check(f.home + "/.Trash/Documents link") == .success(f.home + "/.Trash/Documents link"))
    }

    @Test func aTrashReplacedByALinkIsNoTrash() throws {
        let f = try Fixture()
        defer { f.remove() }
        let fm = FileManager.default
        try fm.removeItem(atPath: f.home + "/Library/Mobile Documents/.Trash")
        try fm.createSymbolicLink(atPath: f.home + "/Library/Mobile Documents/.Trash",
                                  withDestinationPath: f.home + "/Documents")
        let path = f.home + "/Library/Mobile Documents/.Trash/keep.txt"
        #expect(f.check(path) == .failure(.outsideTrash(path)))
        #expect(f.check(f.home + "/.Trash/old.txt") == .success(f.home + "/.Trash/old.txt"))
    }

    @Test func relativeAndMissingPathsAreRefused() throws {
        let f = try Fixture()
        defer { f.remove() }
        #expect(f.check(".Trash/old.txt") == .failure(.notAbsolute(".Trash/old.txt")))
        #expect(f.check("/") == .failure(.notAnItem("/")))
        let missing = f.home + "/.Trash/Gone/old.txt"
        #expect(f.check(missing) == .failure(.notFound(missing)))
    }

    @Test func theSameFoldersAsTheTrashGathers() {
        let home = URL(fileURLWithPath: "/Users/me")
        let volumes = [URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/Volumes/Disk")]
        let gathered = TrashLocations.locations(home: home, volumes: volumes, uid: 501) { _ in true }.map(\.path)
        let roots = TrashErasePolicy.roots(home: "/Users/me", volumes: volumes.map(\.path), uid: 501).map(\.path)
        #expect(roots == gathered)
    }
}

@Suite struct ClientRequirementTests {
    @Test func explorerSignedWithTheHelpersCertificate() {
        #expect(ClientRequirement.requirement(leafCertificateSHA1: "0a1b")
                == "identifier \"local.suite.explorer\" and certificate leaf = H\"0a1b\"")
    }

    @Test func requirementParses() throws {
        var requirement: SecRequirement?
        let text = ClientRequirement.requirement(leafCertificateSHA1: String(repeating: "ab", count: 20))
        #expect(SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess)
    }

    @Test func sha1IsHexadecimal() {
        #expect(ClientRequirement.sha1Hex(Data("abc".utf8)) == "a9993e364706816aba3e25717850c26c9cd0d89d")
    }
}
