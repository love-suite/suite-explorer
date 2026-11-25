@testable import ExplorerCore
import ExplorerSettings
import Foundation
import Testing
import SuiteFilesCore

@Suite struct FileShortcutsTests {
    private func key(_ code: UInt16, _ chars: String = "", cmd: Bool = false, ctrl: Bool = false,
                     opt: Bool = false, shift: Bool = false) -> FileCommand? {
        FileShortcuts.command(for: KeyChord(keyCode: code, characters: chars, command: cmd, control: ctrl,
                                            option: opt, shift: shift))
    }

    @Test func windowsCtrlAndMacCmdBothWork() {
        #expect(key(8, "c", ctrl: true) == .copy)
        #expect(key(8, "c", cmd: true) == .copy)
        #expect(key(7, "x", ctrl: true) == .cut)
        #expect(key(9, "v", cmd: true) == .paste)
        #expect(key(9, "v", cmd: true, opt: true) == .pasteMoving)
        #expect(key(0, "a", ctrl: true) == .selectAll)
        #expect(key(6, "z", ctrl: true) == .undo)
        #expect(key(16, "y", ctrl: true) == .redo)
        #expect(key(6, "z", cmd: true, shift: true) == .redo)
        #expect(key(45, "n", ctrl: true, shift: true) == .newFolder)
        // Both Ctrl and Cmd at once is something else.
        #expect(key(8, "c", cmd: true, ctrl: true) == nil)
    }

    @Test func windowsKeysWithoutCharacters() {
        #expect(key(36) == .open)
        #expect(key(120) == .rename)
        #expect(key(51) == .goUp)
        #expect(key(117) == .moveToTrash)
        // No Shift+Delete: nothing is erased without going through the Trash.
        #expect(key(117, shift: true) == nil)
        #expect(key(126, opt: true) == .goUp)
        #expect(key(123, opt: true) == .goBack)
        #expect(key(124, opt: true) == .goForward)
    }

    @Test func returnRenamesOrOpens() {
        let chord = KeyChord(keyCode: 36, characters: "\r")
        #expect(FileShortcuts.command(for: chord, returnRenames: true) == .rename)
        #expect(FileShortcuts.command(for: chord, returnRenames: false) == .open)
        // The keypad's Enter and Cmd+Return always open.
        #expect(FileShortcuts.command(for: KeyChord(keyCode: 76, characters: ""), returnRenames: true) == .open)
        #expect(FileShortcuts.command(for: KeyChord(keyCode: 36, characters: "", command: true),
                                      returnRenames: true) == .open)
    }

    @Test func macKeys() {
        #expect(key(51, cmd: true) == .moveToTrash)
        #expect(key(125, cmd: true) == .open)
        #expect(key(126, cmd: true) == .goUp)
        #expect(key(0, "a") == nil)
        #expect(key(125) == nil)
    }
}

@Suite struct FileOperationTests {
    private func sandbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileOperation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A pretend Trash inside the sandbox.
    private func trash(in root: URL) -> (URL) throws -> URL {
        { url in
            let bin = root.appendingPathComponent("bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let target = bin.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    @Test func undoAndRedoAMove() throws {
        let root = try sandbox()
        let a = root.appendingPathComponent("a.txt"), b = root.appendingPathComponent("sub/a.txt")
        try "x".write(to: a, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: b.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: a, to: b)
        let redo = try FileOperation.moved(from: [a], to: [b]).undo()
        #expect(exists(a) && !exists(b))
        _ = try redo.undo()
        #expect(!exists(a) && exists(b))
    }

    @Test func undoARename() throws {
        let root = try sandbox()
        let old = root.appendingPathComponent("old.txt"), new = root.appendingPathComponent("new.txt")
        try "x".write(to: new, atomically: true, encoding: .utf8)
        let redo = try FileOperation.renamed(from: old, to: new).undo()
        #expect(exists(old) && !exists(new))
        #expect(redo == .renamed(from: new, to: old))
    }

    @Test func undoingACopySendsItToTheTrashAndRedoBringsItBack() throws {
        let root = try sandbox()
        let copy = root.appendingPathComponent("copy.txt")
        try "x".write(to: copy, atomically: true, encoding: .utf8)
        let redo = try FileOperation.copied(sources: [root.appendingPathComponent("orig.txt")], copies: [copy])
            .undo(trash: trash(in: root))
        #expect(!exists(copy))
        guard case .trashed(let originals, let trashed) = redo else {
            Issue.record("expected .trashed")
            return
        }
        #expect(originals == [copy])
        #expect(exists(trashed[0]))
        _ = try redo.undo()
        #expect(exists(copy))
    }
}

@Suite struct TransferConflictTests {
    private func sandbox() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Conflicts-\(UUID().uuidString)")
        let from = root.appendingPathComponent("from"), to = root.appendingPathComponent("to")
        for folder in [from, to] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try "new".write(to: from.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "old".write(to: to.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        return (root, from, to)
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    @Test func skipLeavesBothAlone() throws {
        let (_, from, to) = try sandbox()
        let result = try FileTransfer.run([from.appendingPathComponent("a.txt")], into: to, operation: .copy,
                                          onConflict: { _, _ in .skip })
        #expect(result.created.isEmpty)
        #expect(read(to.appendingPathComponent("a.txt")) == "old")
    }

    @Test func replaceTrashesTheOldOne() throws {
        let (root, from, to) = try sandbox()
        var trashed: [URL] = []
        let result = try FileTransfer.run([from.appendingPathComponent("a.txt")], into: to, operation: .move,
                                          onConflict: { _, _ in .replace },
                                          trash: { url in
                                              let target = root.appendingPathComponent("trashed.txt")
                                              try FileManager.default.moveItem(at: url, to: target)
                                              trashed.append(target)
                                              return target
                                          })
        #expect(result.created == [to.appendingPathComponent("a.txt")])
        #expect(read(to.appendingPathComponent("a.txt")) == "new")
        #expect(read(trashed[0]) == "old")
        #expect(result.operation(.move) == .moved(from: [from.appendingPathComponent("a.txt")],
                                                  to: [to.appendingPathComponent("a.txt")]))
    }

    @Test func keepBothNumbersTheNewOne() throws {
        let (_, from, to) = try sandbox()
        let result = try FileTransfer.run([from.appendingPathComponent("a.txt")], into: to, operation: .copy,
                                          onConflict: { _, _ in .keepBoth })
        #expect(result.created.map(\.lastPathComponent) == ["a (2).txt"])
    }

    @Test func progressCanStop() throws {
        let (_, from, to) = try sandbox()
        try "b".write(to: from.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let result = try FileTransfer.run([from.appendingPathComponent("b.txt"), from.appendingPathComponent("a.txt")],
                                          into: to, operation: .copy, progress: { done, _ in done < 1 })
        #expect(result.cancelled)
        #expect(result.created.map(\.lastPathComponent) == ["b.txt"])
    }
}

@Suite struct ArchiverTests {
    @Test func compressesAndExtractsAgain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zip-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("Photos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "x".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let other = root.appendingPathComponent("b.txt")
        try "y".write(to: other, atomically: true, encoding: .utf8)

        let single = try Archiver.compress([folder])
        #expect(single.lastPathComponent == "Photos.zip")
        let several = try Archiver.compress([folder, other])
        #expect(several.lastPathComponent == "Archive.zip")

        let extracted = try Archiver.extract(several)
        #expect(extracted.lastPathComponent == "Archive")
        #expect(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("Photos/a.txt").path))
        #expect(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("b.txt").path))
        #expect(Archiver.isArchive(single))
    }
}

@Suite struct QuickAccessTests {
    private func store() -> QuickAccessStore {
        let defaults = UserDefaults(suiteName: "QuickAccessTests-\(UUID().uuidString)")!
        return QuickAccessStore(defaults: defaults, home: URL(fileURLWithPath: "/Users/me"))
    }

    @Test func startsWithFindersFavorites() {
        #expect(store().folders.map(\.path)
            == ["/Applications", "/Users/me/Desktop", "/Users/me/Documents", "/Users/me/Downloads"])
    }

    @Test func pinsUnpinsAndMoves() {
        let quick = store()
        let projects = URL(fileURLWithPath: "/Users/me/Projects")
        quick.pin(projects)
        #expect(quick.isPinned(projects))
        #expect(quick.folders.last?.lastPathComponent == "Projects")
        quick.pin(projects, at: 0)
        #expect(quick.folders.first?.lastPathComponent == "Projects")
        #expect(quick.folders.count == 5)
        quick.unpin(URL(fileURLWithPath: "/Users/me/Desktop/"))
        #expect(!quick.folders.map(\.lastPathComponent).contains("Desktop"))
    }
}

@Suite struct FolderSummaryTests {
    private func file(_ size: Int64?, folder: Bool = false) -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/x"), name: "x", isDirectory: folder, isPackage: false, size: size,
                 modified: nil, isHidden: false, kind: nil)
    }

    @Test func countsSelectionAndSpace() {
        #expect(FolderSummary.text(itemCount: 1, selected: [], availableBytes: nil) == "1 item")
        let text = FolderSummary.text(itemCount: 12, selected: [file(1000), file(2000)], availableBytes: 5_000_000_000)
        #expect(text.hasPrefix("12 items   |   2 items selected  3"))
        #expect(text.hasSuffix("available"))
        // Folders have no size of their own.
        #expect(FolderSummary.text(itemCount: 3, selected: [file(nil, folder: true)], availableBytes: nil)
                == "3 items   |   1 item selected")
    }
}

@Suite struct TypeSelectTests {
    @Test func lettersTypedQuicklyAddUp() {
        var select = TypeSelect()
        let start = Date()
        #expect(select.add("p", at: start) == "p")
        #expect(select.add("h", at: start.addingTimeInterval(0.3)) == "ph")
        #expect(select.add("d", at: start.addingTimeInterval(2)) == "d")
    }

    @Test func matchesTheFirstNameStartingWithIt() {
        let names = ["Applications", "Été", "photo.jpg", "Photos"]
        #expect(TypeSelect.match("ph", in: names) == 2)
        #expect(TypeSelect.match("ete", in: names) == 1)
        #expect(TypeSelect.match("z", in: names) == nil)
    }
}
