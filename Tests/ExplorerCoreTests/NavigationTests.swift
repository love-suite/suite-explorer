import Foundation
import Testing
@testable import ExplorerCore
import SuiteFilesCore

@Suite struct NavigationHistoryTests {
    let a = URL(fileURLWithPath: "/a")
    let b = URL(fileURLWithPath: "/a/b")
    let c = URL(fileURLWithPath: "/a/b/c")

    @Test func startsWithNoHistory() {
        let history = NavigationHistory(start: a)
        #expect(history.current.path == "/a")
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test func backAndForward() {
        var history = NavigationHistory(start: a)
        history.go(to: b)
        history.go(to: c)

        history.back()
        #expect(history.current.path == "/a/b")
        history.back()
        #expect(history.current.path == "/a")
        #expect(!history.canGoBack)

        history.forward()
        #expect(history.current.path == "/a/b")
        #expect(history.canGoForward)
    }

    @Test func goingSomewhereNewClearsForward() {
        var history = NavigationHistory(start: a)
        history.go(to: b)
        history.back()
        history.go(to: c)
        #expect(!history.canGoForward)
        history.back()
        #expect(history.current.path == "/a")
    }

    @Test func revisitingCurrentFolderAddsNoHistory() {
        var history = NavigationHistory(start: a)
        history.go(to: URL(fileURLWithPath: "/a/"))
        history.go(to: URL(fileURLWithPath: "/a/b/.."))
        #expect(!history.canGoBack)
    }

    @Test func upGoesToParentAndStopsAtRoot() {
        var history = NavigationHistory(start: c)
        history.up()
        #expect(history.current.path == "/a/b")
        #expect(history.canGoBack)

        var atRoot = NavigationHistory(start: URL(fileURLWithPath: "/"))
        #expect(!atRoot.canGoUp)
        atRoot.up()
        #expect(atRoot.current.path == "/")
    }

    @Test func placesThatAreNotFoldersKeepTheirAddressAndHaveNoParent() {
        var history = NavigationHistory(start: a)
        history.go(to: VirtualPlace.recents.url)
        #expect(VirtualPlace(url: history.current) == .recents)
        #expect(!history.canGoUp)
        history.go(to: VirtualPlace.recents.url)
        history.back()
        #expect(history.current.path == "/a")
        history.forward()
        #expect(VirtualPlace(url: history.current) == .recents)
    }
}

@Suite struct VirtualPlaceTests {
    @Test func eachPlaceComesBackFromItsAddress() {
        for place in VirtualPlace.allCases {
            #expect(VirtualPlace(url: place.url) == place)
        }
        #expect(VirtualPlace.recents.url.absoluteString == "explorer:recents")
    }

    @Test func foldersAndUnknownAddressesAreNotPlaces() {
        #expect(VirtualPlace(url: URL(fileURLWithPath: "/recents")) == nil)
        #expect(VirtualPlace(url: URL(string: "explorer:nowhere")!) == nil)
    }
}

@Suite struct PackageTests {
    @Test func appBundleIsNotAFolderAndSortsWithFiles() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.make("Zeta", directory: true)
        try sandbox.make("Alpha.app", directory: true)
        try sandbox.make("beta.txt")

        let items = try DirectoryLoader.load(sandbox.root)

        #expect(items.map(\.name) == ["Zeta", "Alpha.app", "beta.txt"])
        let app = try #require(items.first { $0.name == "Alpha.app" })
        #expect(app.isDirectory)
        #expect(app.isPackage)
        #expect(!app.isFolder)
    }
}
