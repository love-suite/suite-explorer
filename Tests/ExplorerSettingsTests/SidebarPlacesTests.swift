@testable import ExplorerSettings
import Foundation
import Testing
import SuiteFilesCore

@Suite struct SidebarPlacesTests {
    private func freshDefaults() -> UserDefaults {
        let name = "SidebarPlacesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func everythingInFindersOrderByDefault() {
        let places = SidebarPlaces.load(from: freshDefaults())
        #expect(places.ordered() == SidebarPlace.allCases)
        #expect(places.ordered().first == .recents)
        #expect(places.ordered().last == .trash)
    }

    @Test func choicesAreSavedAndKeepTheirOrder() {
        let defaults = freshDefaults()
        var places = SidebarPlaces.load(from: defaults)
        places.set(.recents, shown: false)
        places.set(.airDrop, shown: false)
        places.save(to: defaults)

        let loaded = SidebarPlaces.load(from: defaults)
        #expect(loaded == places)
        let order = loaded.ordered()
        #expect(order.first == .shared)
        #expect(!order.contains(.airDrop))
        #expect(order.firstIndex(of: .favorites)! < order.firstIndex(of: .disks)!)
    }

    @Test func quickAccessTurnedOffBeforeStaysOffAsFavorites() {
        let defaults = freshDefaults()
        defaults.set(["quickAccess": false, "home": true, "music": false], forKey: "SidebarPlaces")
        let loaded = SidebarPlaces.load(from: defaults)
        #expect(!loaded.contains(.favorites))
        #expect(loaded.contains(.recents))
    }

    @Test func missingPlacesAreLeftOut() {
        let order = SidebarPlaces().ordered { $0 != .iCloudDrive }
        #expect(!order.contains(.iCloudDrive))
    }

    @Test func folderPlacesPointUnderHome() {
        let home = URL(fileURLWithPath: "/Users/me")
        #expect(SidebarPlace.iCloudDrive.url(home: home)?.path
            == "/Users/me/Library/Mobile Documents/com~apple~CloudDocs")
        #expect(SidebarPlace.trash.url(home: home)?.path == "/Users/me/.Trash")
        #expect(SidebarPlace.disks.url(home: home) == nil)
        #expect(SidebarPlace.cloudStorageFolder(home: home).path == "/Users/me/Library/CloudStorage")
    }
}
