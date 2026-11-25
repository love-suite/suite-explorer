import Foundation
import Testing
@testable import ExplorerCore
import SuiteFilesCore

@Suite struct NameSearchTests {
    @Test func everyWordInAnyOrderIgnoringCaseAndAccents() {
        #expect(NameSearch.matches("Rapport Été 2026.pdf", "ete rapport"))
        #expect(NameSearch.matches("photo.JPG", "jpg"))
        #expect(!NameSearch.matches("photo.jpg", "photo png"))
        #expect(!NameSearch.matches("photo.jpg", "   "))
    }

    @Test func walksFoldersButNotPackagesNorHiddenItems() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NameSearch-\(UUID().uuidString)")
        let fm = FileManager.default
        for path in ["A/report one.txt", "A/B/Report two.md", "A/.report hidden", "Tool.app/Contents/report.txt",
                     "C/other.txt"] {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "x".write(to: url, atomically: true, encoding: .utf8)
        }
        defer { try? fm.removeItem(at: root) }

        var found: [String] = []
        NameSearch.search("report", in: [root, root.appendingPathComponent("A")], batchSize: 1) { batch in
            found += batch.map(\.lastPathComponent)
        }
        #expect(found.sorted() == ["Report two.md", "report one.txt"])

        found = []
        NameSearch.search("report", in: [root], showHidden: true) { found += $0.map(\.lastPathComponent) }
        #expect(found.contains(".report hidden"))

        found = []
        NameSearch.search("report", in: [root], limit: 1) { found += $0.map(\.lastPathComponent) }
        #expect(found.count == 1)
    }
}

@Suite struct SearchScopeTests {
    private let a = URL(fileURLWithPath: "/Users/me/A"), b = URL(fileURLWithPath: "/Users/me/B")

    @Test func thisMacEachOpenFolderThenAll() {
        let choices = SearchScope.choices(current: a, open: [b, a], name: { $0.lastPathComponent })
        #expect(choices.map(\.title) == ["This Mac", "“A”", "“B”", "All Open Folders"])
        #expect(choices.map(\.kind) == [.thisMac, .currentFolder, .otherFolder, .openFolders])
        #expect(choices.last?.folders == [a, b])
        let alone = SearchScope.choices(current: a, open: [], name: { $0.lastPathComponent })
        #expect(alone.map(\.kind) == [.thisMac, .currentFolder])
    }

    @Test func startsWhereTheLastSearchLooked() {
        let choices = SearchScope.choices(current: a, open: [b], name: { $0.lastPathComponent })
        #expect(SearchScope.initial(in: choices, remembered: nil)?.kind == .currentFolder)
        #expect(SearchScope.initial(in: choices, remembered: .thisMac)?.kind == .thisMac)
        #expect(SearchScope.initial(in: choices, remembered: .otherFolder)?.kind == .currentFolder)
        let alone = SearchScope.choices(current: a, open: [], name: { $0.lastPathComponent })
        #expect(SearchScope.initial(in: alone, remembered: .openFolders)?.kind == .currentFolder)
    }

    @Test func fromAPlaceThatIsNotAFolderTheSearchIsOverThisMacOrTheOpenFolders() {
        let choices = SearchScope.choices(current: VirtualPlace.recents.url, open: [a, VirtualPlace.shared.url],
                                          name: { $0.lastPathComponent })
        #expect(choices.map(\.kind) == [.thisMac, .otherFolder])
        #expect(SearchScope.initial(in: choices, remembered: nil)?.kind == .thisMac)
    }
}
