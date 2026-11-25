import Foundation
import SuiteCore

/// The commands of an Explorer window's toolbar, in their order.
public enum ToolbarCommand: String, CaseIterable, Codable, Sendable {
    case newFolder, rename, trash, properties, previewPane, hiddenFiles, fileExtensions
    case putBack, deletePermanently, emptyTrash, sideBySide, swapSides
    /// The + button, which opens the commands put in its menu: placed and hidden like the others.
    case more

    public var title: String {
        switch self {
        case .newFolder: return "New Folder"
        case .rename: return "Rename"
        case .trash: return "Move to Trash"
        case .properties: return "Properties"
        case .previewPane: return "Preview Pane"
        case .hiddenFiles: return "Show Hidden Files"
        case .fileExtensions: return "Show File Extensions"
        case .putBack: return "Restore"
        case .deletePermanently: return "Delete Permanently"
        case .emptyTrash: return "Empty Trash"
        case .sideBySide: return "Side by Side"
        case .swapSides: return "Swap Sides"
        case .more: return "More"
        }
    }

    /// The SF Symbol drawn for it.
    public var symbol: String {
        switch self {
        case .newFolder: return "folder.badge.plus"
        case .rename: return "pencil"
        case .trash: return "trash"
        case .properties: return "info.circle"
        case .previewPane: return "doc.text.magnifyingglass"
        case .hiddenFiles: return "eye"
        case .fileExtensions: return "textformat"
        case .putBack: return "arrow.uturn.backward"
        case .deletePermanently: return "xmark.bin"
        case .emptyTrash: return "trash.slash"
        case .sideBySide: return "rectangle.split.2x1"
        case .swapSides: return "arrow.left.arrow.right"
        case .more: return "plus"
        }
    }

    /// What it does, shown under the mouse with its name.
    public var help: String {
        switch self {
        case .newFolder: return "Makes a new folder here and names it."
        case .rename: return "Renames the selected item in place."
        case .trash: return "Moves the selection to the Trash, where it can be restored."
        case .properties: return "Shows the size, dates and details of the selection."
        case .previewPane: return "Shows a preview of the selected file beside the folder."
        case .hiddenFiles: return "Shows or hides hidden files and folders, dimmed."
        case .fileExtensions: return "Shows or hides the end of file names, like .pdf."
        case .putBack: return "Puts the selection back in the folder it was deleted from."
        case .deletePermanently: return "Erases the selection for good. It can't be undone."
        case .emptyTrash: return "Erases everything in the Trash for good. It can't be undone."
        case .sideBySide: return "Shows two folders side by side, to copy or move between them."
        case .swapSides: return "Swaps the two folders, left and right."
        case .more: return "Opens the commands put in its menu. Hidden, it takes them with it into Hidden."
        }
    }

    /// The name and what it does, for a tooltip.
    public var tooltip: String { title + "\n" + help }

    /// On or off, shown with a check mark in the + menu.
    public var isToggle: Bool {
        [.previewPane, .hiddenFiles, .fileExtensions, .sideBySide].contains(self)
    }

    /// Where it applies: some only in the Trash, some everywhere but there.
    public enum Context: Sendable { case everywhere, outsideTrash, inTrash, sideBySide }

    public var context: Context {
        switch self {
        case .newFolder, .rename, .trash: return .outsideTrash
        case .putBack, .deletePermanently, .emptyTrash: return .inTrash
        case .swapSides: return .sideBySide
        default: return .everywhere
        }
    }

    public func applies(inTrash: Bool, sideBySide: Bool) -> Bool {
        switch context {
        case .everywhere: return true
        case .outsideTrash: return !inTrash
        case .inTrash: return inTrash
        case .sideBySide: return sideBySide
        }
    }
}

/// Where a command shows: as a button in the toolbar, in the toolbar's + menu, or nowhere.
public enum ToolbarPlacement: String, CaseIterable, Codable, Sendable {
    case toolbar, menu, hidden

    public var title: String {
        switch self {
        case .toolbar: return "Toolbar"
        case .menu: return "+ Menu"
        case .hidden: return "Hidden"
        }
    }
}

/// Which commands show where, and in what order, chosen in the settings and saved in the defaults: the
/// toolbar's buttons, the + menu's items, and the hidden ones. Every command is in exactly one list.
public struct ToolbarLayout: Equatable, Sendable {
    public private(set) var toolbar: [ToolbarCommand]
    public private(set) var menu: [ToolbarCommand]
    public private(set) var hidden: [ToolbarCommand]

    /// Every command in the toolbar, in its usual order, as before the setting existed.
    public init(toolbar: [ToolbarCommand] = ToolbarCommand.allCases, menu: [ToolbarCommand] = [],
                hidden: [ToolbarCommand] = []) {
        self.toolbar = toolbar
        self.menu = menu
        self.hidden = hidden
        normalize()
    }

    public func list(_ placement: ToolbarPlacement) -> [ToolbarCommand] {
        switch placement {
        case .toolbar: return toolbar
        case .menu: return menu
        case .hidden: return hidden
        }
    }

    public func placement(of command: ToolbarCommand) -> ToolbarPlacement {
        if menu.contains(command) { return .menu }
        if hidden.contains(command) { return .hidden }
        return .toolbar
    }

    /// Moves `command` into `placement`'s list, before `target` (another command of that list), or at its end.
    public mutating func move(_ command: ToolbarCommand, to placement: ToolbarPlacement,
                              before target: ToolbarCommand? = nil) {
        // + can't go into its own menu.
        guard command != target, !(command == .more && placement == .menu) else { return }
        toolbar.removeAll { $0 == command }
        menu.removeAll { $0 == command }
        hidden.removeAll { $0 == command }
        func insert(into list: inout [ToolbarCommand]) {
            if let target, let index = list.firstIndex(of: target) {
                list.insert(command, at: index)
            } else {
                list.append(command)
            }
        }
        switch placement {
        case .toolbar: insert(into: &toolbar)
        case .menu: insert(into: &menu)
        case .hidden: insert(into: &hidden)
        }
        // Options hidden: what its menu held is hidden too, after it.
        if command == .more && placement == .hidden {
            if let index = hidden.firstIndex(of: .more) { hidden.insert(contentsOf: menu, at: index + 1) }
            menu = []
        }
    }

    /// Moves `command` to `placement`, keeping it where it is if it is there already.
    public mutating func set(_ command: ToolbarCommand, to placement: ToolbarPlacement) {
        guard self.placement(of: command) != placement else { return }
        move(command, to: placement)
    }

    /// The commands in `placement`'s list, in order, those that apply where the window is.
    public func commands(_ placement: ToolbarPlacement, inTrash: Bool, sideBySide: Bool) -> [ToolbarCommand] {
        list(placement).filter { $0.applies(inTrash: inTrash, sideBySide: sideBySide) }
    }

    /// Each command once; one missing (added in a later version) goes to the toolbar after the one that
    /// comes before it in the usual order.
    private mutating func normalize() {
        var seen = Set<ToolbarCommand>()
        menu.removeAll { $0 == .more }
        toolbar = toolbar.filter { seen.insert($0).inserted }
        menu = menu.filter { seen.insert($0).inserted }
        hidden = hidden.filter { seen.insert($0).inserted }
        for command in ToolbarCommand.allCases where !seen.contains(command) {
            let earlier = ToolbarCommand.allCases.prefix { $0 != command }.reversed()
            if let previous = earlier.first(where: toolbar.contains), let index = toolbar.firstIndex(of: previous) {
                toolbar.insert(command, at: index + 1)
            } else {
                toolbar.insert(command, at: 0)
            }
        }
    }

    // MARK: Defaults

    private static let key = "ToolbarLayout"

    /// Saved as the three lists.
    public static func load(from defaults: UserDefaults = SuiteDefaults.explorer) -> ToolbarLayout {
        func commands(_ names: [String]?) -> [ToolbarCommand] { (names ?? []).compactMap(ToolbarCommand.init) }
        guard let lists = defaults.dictionary(forKey: key) as? [String: [String]] else { return ToolbarLayout() }
        return ToolbarLayout(toolbar: commands(lists["toolbar"]), menu: commands(lists["menu"]),
                             hidden: commands(lists["hidden"]))
    }

    public func save(to defaults: UserDefaults = SuiteDefaults.explorer) {
        defaults.set(["toolbar": toolbar.map(\.rawValue), "menu": menu.map(\.rawValue),
                      "hidden": hidden.map(\.rawValue)], forKey: Self.key)
    }
}

/// How many toolbar buttons fit in a width, as the window's toolbar lays them out: the first ones that fit,
/// the others in the » menu at the end, as macOS does with toolbar items that don't fit.
public enum ToolbarOverflow {
    /// The space between two toolbar buttons.
    public static let buttonSpacing: CGFloat = 6

    /// `widths` of the buttons in order, `spacing` between them, `trailing` the width of what always ends
    /// the row (+, or » once something overflows; both the same size).
    public static func visibleCount(widths: [CGFloat], spacing: CGFloat, trailing: CGFloat,
                                    available: CGFloat) -> Int {
        var used = trailing
        for (index, width) in widths.enumerated() {
            used += width + spacing
            if used > available { return index }
        }
        return widths.count
    }
}
