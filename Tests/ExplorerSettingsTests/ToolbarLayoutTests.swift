@testable import ExplorerSettings
import Foundation
import Testing

@Suite struct ToolbarLayoutTests {
    private func freshDefaults() -> UserDefaults {
        let name = "ToolbarLayoutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func everythingInTheToolbarByDefault() {
        let layout = ToolbarLayout.load(from: freshDefaults())
        #expect(ToolbarCommand.allCases.allSatisfy { layout.placement(of: $0) == .toolbar })
        #expect(layout.commands(.menu, inTrash: false, sideBySide: false).isEmpty)
    }

    @Test func choicesAreSavedAndFollowWhereTheWindowIs() {
        let defaults = freshDefaults()
        var layout = ToolbarLayout()
        layout.set(.properties, to: .menu)
        layout.set(.emptyTrash, to: .menu)
        layout.set(.rename, to: .hidden)
        layout.save(to: defaults)
        let loaded = ToolbarLayout.load(from: defaults)
        #expect(loaded == layout)
        // In a folder: Properties in the menu, not Empty Trash, which only applies in the Trash.
        #expect(loaded.commands(.menu, inTrash: false, sideBySide: false) == [.properties])
        #expect(loaded.commands(.menu, inTrash: true, sideBySide: false) == [.properties, .emptyTrash])
        #expect(!loaded.commands(.toolbar, inTrash: false, sideBySide: false).contains(.rename))
        // Swap Sides only Side by Side.
        #expect(!loaded.commands(.toolbar, inTrash: false, sideBySide: false).contains(.swapSides))
        #expect(loaded.commands(.toolbar, inTrash: false, sideBySide: true).contains(.swapSides))
    }

    @Test func plusIsAButtonButNotInItsOwnMenu() {
        var layout = ToolbarLayout()
        #expect(layout.toolbar.last == .more)
        layout.move(.more, to: .menu)
        #expect(layout.placement(of: .more) == .toolbar)
        layout.move(.properties, to: .menu)
        layout.move(.more, to: .hidden)
        // Hidden, Options takes its menu's commands with it.
        #expect(layout.hidden == [.more, .properties] && layout.menu.isEmpty)
        layout.move(.more, to: .toolbar, before: .newFolder)
        #expect(layout.toolbar.first == .more)
        #expect(ToolbarLayout(toolbar: [], menu: [.more], hidden: []).placement(of: .more) == .toolbar)
    }

    @Test func togglesAreMarked() {
        #expect(ToolbarCommand.hiddenFiles.isToggle && ToolbarCommand.sideBySide.isToggle)
        #expect(!ToolbarCommand.newFolder.isToggle)
    }
}

@Suite struct ToolbarOrderTests {
    @Test func dragsReorderAndMoveBetweenLists() {
        var layout = ToolbarLayout()
        // Dropped before New Folder: first in the toolbar.
        layout.move(.properties, to: .toolbar, before: .newFolder)
        #expect(layout.toolbar.prefix(2) == [.properties, .newFolder])
        // Dragged out of the bar: hidden; dragged back, at the end.
        layout.move(.rename, to: .hidden)
        #expect(layout.hidden == [.rename] && !layout.toolbar.contains(.rename))
        layout.move(.rename, to: .toolbar)
        #expect(layout.toolbar.last == .rename)
        // Into the + menu, in order.
        layout.move(.hiddenFiles, to: .menu)
        layout.move(.fileExtensions, to: .menu, before: .hiddenFiles)
        #expect(layout.menu == [.fileExtensions, .hiddenFiles])
        #expect(Set(layout.toolbar + layout.menu + layout.hidden).count == ToolbarCommand.allCases.count)
    }

    @Test func aMissingCommandComesBackInTheToolbar() {
        let layout = ToolbarLayout(toolbar: [.newFolder, .trash], menu: [], hidden: [])
        #expect(layout.toolbar.prefix(3) == [.newFolder, .rename, .trash])
        #expect(layout.toolbar.count == ToolbarCommand.allCases.count)
    }
}

@Suite struct ToolbarOverflowTests {
    @Test func theFirstButtonsThatFitStay() {
        let widths: [CGFloat] = [30, 30, 30, 30]
        // All of them: 4 × (30 + 6) + 30 for + = 174.
        #expect(ToolbarOverflow.visibleCount(widths: widths, spacing: 6, trailing: 30, available: 174) == 4)
        #expect(ToolbarOverflow.visibleCount(widths: widths, spacing: 6, trailing: 30, available: 173) == 3)
        #expect(ToolbarOverflow.visibleCount(widths: widths, spacing: 6, trailing: 30, available: 60) == 0)
        #expect(ToolbarOverflow.visibleCount(widths: [], spacing: 6, trailing: 30, available: 10) == 0)
    }
}
