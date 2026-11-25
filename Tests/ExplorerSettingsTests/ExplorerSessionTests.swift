@testable import ExplorerSettings
import Foundation
import Testing

@Suite struct ExplorerSessionTests {
    @Test func savedAndReadBack() {
        let name = "ExplorerSessionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(ExplorerSession.load(from: defaults).windows.isEmpty)
        let session = ExplorerSession(windows: [
            .init(frame: CGRect(x: 10, y: 20, width: 1100, height: 700), tabs: [
                .init(folders: ["/Users/me"]),
                .init(folders: ["/Users/me/Documents", "/Users/me/Desktop"], activePane: 1, showsPreview: true),
            ], selectedTab: 1),
        ])
        session.save(to: defaults)
        let loaded = ExplorerSession.load(from: defaults)
        #expect(loaded == session)
        #expect(loaded.windows[0].rect == CGRect(x: 10, y: 20, width: 1100, height: 700))
    }

    @Test func foldersThatAreGoneAreLeftOut() {
        let session = ExplorerSession(windows: [
            .init(frame: .zero, tabs: [
                .init(folders: ["/gone"]),
                .init(folders: ["/a", "/gone"], activePane: 1),
                .init(folders: ["/b"]),
            ], selectedTab: 2),
            .init(frame: .zero, tabs: [.init(folders: ["/gone"])]),
        ])
        let kept = session.existing { $0 != "/gone" }
        // The window with nothing left goes; Side by Side falls back to one folder.
        #expect(kept.windows.count == 1)
        #expect(kept.windows[0].tabs.map(\.folders) == [["/a"], ["/b"]])
        #expect(kept.windows[0].tabs[0].activePane == 0)
        // The tab that was in front stays in front.
        #expect(kept.windows[0].selectedTab == 1)
    }
}
