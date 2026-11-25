import Foundation
import Testing
@testable import ExplorerCore
import SuiteCore
import SuiteFilesCore

@Suite struct TrashTests {
    @Test func moveToTrashRemovesOriginal() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let file = try sandbox.make("deleteme.txt")

        let trashed = try FileTrash.moveToTrash(file)

        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: trashed.path))
        try? FileManager.default.removeItem(at: trashed)
    }
}

@Suite struct RenameTests {
    @Test func renameChangesName() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let file = try sandbox.make("old.txt")

        let renamed = try FileRenamer.rename(file, to: "new.txt")

        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(renamed.lastPathComponent == "new.txt")
        #expect(FileManager.default.fileExists(atPath: renamed.path))
    }

    @Test func renameThrowsOnConflict() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let file = try sandbox.make("a.txt")
        try sandbox.make("b.txt")

        #expect(throws: (any Error).self) {
            try FileRenamer.rename(file, to: "b.txt")
        }
    }
}

@Suite struct TemplateTests {
    @Test func createsFileWithDefaultName() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }

        let url = try FileTemplate.text.create(in: sandbox.root)

        #expect(url.lastPathComponent == "New Text File.txt")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func appendsNumberOnCollision() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.make("New Text File.txt")

        let url = try FileTemplate.text.create(in: sandbox.root)

        #expect(url.lastPathComponent == "New Text File (2).txt")
    }

    @Test func markdownUsesCorrectExtension() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }

        let url = try FileTemplate.markdown.create(in: sandbox.root)

        #expect(url.pathExtension == "md")
    }
}

@Suite struct PathParserTests {
    @Test func posixPath() {
        #expect(PathParser.parse("/Users/alice/Documents")?.path == "/Users/alice/Documents")
    }

    @Test func tildePath() {
        let result = PathParser.parse("~/Desktop")
        let expected = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop").standardized
        #expect(result == expected)
    }

    @Test func windowsAbsolutePath() {
        #expect(PathParser.parse(#"C:\Users\alice\Documents"#)?.path == "/Users/alice/Documents")
    }

    @Test func relativePathReturnsNil() {
        #expect(PathParser.parse(#"Documents\notes.txt"#) == nil)
    }

    @Test func emptyStringReturnsNil() {
        #expect(PathParser.parse("") == nil)
    }

    @Test func whitespaceOnlyReturnsNil() {
        #expect(PathParser.parse("   ") == nil)
    }
}

@Suite struct DirectoryWatcherTests {
    @Test func notifiesOnFileCreation() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }

        let semaphore = DispatchSemaphore(value: 0)
        let watcher = DirectoryWatcher(url: sandbox.root) { semaphore.signal() }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.3)
        try sandbox.make("trigger.txt")

        #expect(semaphore.wait(timeout: .now() + 5) == .success)
    }
}
