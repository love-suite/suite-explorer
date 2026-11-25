import AppKit
import ExplorerCore
import ExplorerSettings
import SuiteFilesCore

/// The menu bar, laid out like Finder's but limited to what Explorer actually does. Actions reach the
/// frontmost window, the desktop or the app delegate through the responder chain.
public enum AppMenu {
    public static func make(appName: String) -> NSMenu {
        let main = NSMenu()
        let shiftCmd: NSEvent.ModifierFlags = [.command, .shift]
        let optCmd: NSEvent.ModifierFlags = [.command, .option]
        let ctrlCmd: NSEvent.ModifierFlags = [.command, .control]

        let app = submenu(appName, in: main)
        add(app, String(format: UIL("About %@"), appName), Selector(("showAboutPanel:")))
        app.addItem(.separator())
        add(app, UIL("Settings"), Selector(("showSettings:")), ",")
        app.addItem(.separator())
        let services = NSMenu()
        app.addItem(withTitle: UIL("Services"), action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        app.addItem(.separator())
        add(app, String(format: UIL("Hide %@"), appName), #selector(NSApplication.hide(_:)), "h")
        add(app, UIL("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", optCmd)
        add(app, UIL("Show All"), #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, String(format: UIL("Quit %@"), appName), #selector(NSApplication.terminate(_:)), "q")

        let file = submenu(UIL("File"), in: main)
        add(file, UIL("New Explorer Window"), #selector(Actions.newWindow), "n", target: Actions.shared)
        add(file, UIL("New Folder"), Selector(("newFolder:")), "n", shiftCmd)
        add(file, UIL("New Tab"), #selector(NSResponder.newWindowForTab(_:)), "t")
        add(file, UIL("Open"), Selector(("openSelection:")), "o")
        add(file, UIL("Close Window"), #selector(NSWindow.performClose(_:)), "w")
        file.addItem(.separator())
        add(file, UIL("Properties"), Selector(("showProperties:")), "i")
        add(file, UIL("Change Icon"), Selector(("changeIcon:")))
        add(file, UIL("Rename"), Selector(("renameSelection:")))
        add(file, UIL("Quick Look"), Selector(("toggleQuickLook:")), "y")
        file.addItem(.separator())
        add(file, UIL("Move to Trash"), Selector(("moveToTrash:")), "\u{8}")
        add(file, UIL("Put Back"), #selector(ExplorerWindowController.putBack(_:)))
        add(file, UIL("Delete Permanently"), #selector(ExplorerWindowController.deletePermanently(_:)))
        add(file, UIL("Empty Trash"), #selector(ExplorerWindowController.emptyTrash(_:)), "\u{8}", [.command, .shift])
        file.delegate = TabItems.shared

        let edit = submenu(UIL("Edit"), in: main)
        add(edit, UIL("Undo"), Selector(("undo:")), "z")
        add(edit, UIL("Redo"), Selector(("redo:")), "z", shiftCmd)
        edit.addItem(.separator())
        add(edit, UIL("Cut"), #selector(NSText.cut(_:)), "x")
        add(edit, UIL("Copy"), #selector(NSText.copy(_:)), "c")
        add(edit, UIL("Paste"), #selector(NSText.paste(_:)), "v")
        add(edit, UIL("Move Item Here"), Selector(("pasteMoving:")), "v", optCmd)
        add(edit, UIL("Select All"), #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        add(edit, UIL("Find"), #selector(ExplorerWindowController.focusSearch(_:)), "f")
        edit.addItem(.separator())
        // Side by Side, as in two-panel file managers: F5 copies, F6 moves to the other folder.
        add(edit, UIL("Copy to Other Side"), #selector(ExplorerWindowController.copyToOtherSide(_:)), "\u{F708}", [])
        add(edit, UIL("Move to Other Side"), #selector(ExplorerWindowController.moveToOtherSide(_:)), "\u{F709}", [])
        edit.addItem(.separator())
        add(edit, UIL("Clipboard History"), #selector(ClipboardApp.open), target: ClipboardApp.shared)
        edit.delegate = ClipboardApp.shared
        add(edit, UIL("Emoji & Symbols"), #selector(NSApplication.orderFrontCharacterPalette(_:)), " ", ctrlCmd)

        let view = submenu(UIL("View"), in: main)
        add(view, UIL("as Icons"), #selector(ExplorerWindowController.showAsIcons(_:)), "1")
        add(view, UIL("as List"), #selector(ExplorerWindowController.showAsDetails(_:)), "2")
        add(view, UIL("as Columns"), #selector(ExplorerWindowController.showAsColumns(_:)), "3")
        view.addItem(.separator())
        add(view, UIL("Use Stacks"), Selector(("toggleStacks:")), "0", ctrlCmd)
        let sort = NSMenu()
        add(sort, UIL("Name"), #selector(ExplorerWindowController.sortByName(_:)))
        add(sort, UIL("Kind"), #selector(ExplorerWindowController.sortByKind(_:)))
        add(sort, UIL("Date Modified"), #selector(ExplorerWindowController.sortByDate(_:)))
        add(sort, UIL("Size"), #selector(ExplorerWindowController.sortBySize(_:)))
        view.addItem(withTitle: UIL("Sort By"), action: nil, keyEquivalent: "").submenu = sort
        add(view, UIL("Apply View to All Folders"), #selector(ExplorerWindowController.applyViewToAllFolders(_:)))
        view.addItem(.separator())
        add(view, UIL("Show Preview"), #selector(ExplorerWindowController.togglePreviewPane(_:)), "p", shiftCmd)
        add(view, UIL("Show Tab Bar"), #selector(NSWindow.toggleTabBar(_:)), "t", shiftCmd)
        add(view, UIL("Side by Side"), #selector(ExplorerWindowController.toggleSideBySide(_:)))
        add(view, UIL("Swap Sides"), #selector(ExplorerWindowController.swapSides(_:)))
        add(view, UIL("Hide Sidebar"), #selector(ExplorerWindowController.toggleFolderTree(_:)), "s", ctrlCmd)
        add(view, UIL("Show Hidden Files"), #selector(Actions.toggleHiddenFiles), ".", shiftCmd, target: Actions.shared)
        add(view, UIL("Show File Extensions"), #selector(Actions.toggleExtensions), target: Actions.shared)
        add(view, UIL("Show Full Name of Selected Items"), #selector(Actions.toggleFullNames), target: Actions.shared)
        view.addItem(.separator())
        add(view, UIL("Enter Full Screen"), #selector(NSWindow.toggleFullScreen(_:)), "f", ctrlCmd)
        view.delegate = TabItems.shared

        let go = submenu(UIL("Go"), in: main)
        add(go, UIL("Back"), #selector(ExplorerWindowController.goBack(_:)), "[")
        add(go, UIL("Forward"), #selector(ExplorerWindowController.goForward(_:)), "]")
        add(go, UIL("Enclosing Folder"), #selector(ExplorerWindowController.goUp(_:)), "\u{F700}")
        go.addItem(.separator())
        for place in Place.allCases {
            let item = add(go, UIL(place.title), #selector(Actions.goToPlace(_:)), place.key, place.modifiers,
                           target: Actions.shared)
            item.representedObject = place.url
        }
        go.addItem(.separator())
        add(go, UIL("Trash"), #selector(Actions.goToPlace(_:)), target: Actions.shared).representedObject = TrashFolder.url
        add(go, UIL("Go to Folder"), #selector(ExplorerWindowController.focusAddressBar(_:)), "g", shiftCmd)

        let window = submenu(UIL("Window"), in: main)
        add(window, UIL("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, UIL("Zoom"), #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        add(window, UIL("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = window

        return main
    }

    /// The Go menu's places, with Finder's shortcuts.
    private enum Place: CaseIterable {
        case desktop, documents, downloads, home, applications, utilities, computer

        var title: String {
            switch self {
            case .desktop: return "Desktop"
            case .documents: return "Documents"
            case .downloads: return "Downloads"
            case .home: return "Home"
            case .applications: return "Applications"
            case .utilities: return "Utilities"
            case .computer: return "Computer"
            }
        }

        var key: String {
            switch self {
            case .desktop: return "d"
            case .documents: return "o"
            case .downloads: return "l"
            case .home: return "h"
            case .applications: return "a"
            case .utilities: return "u"
            case .computer: return "c"
            }
        }

        var modifiers: NSEvent.ModifierFlags {
            self == .downloads ? [.command, .option] : [.command, .shift]
        }

        var url: URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            switch self {
            case .desktop: return home.appendingPathComponent("Desktop")
            case .documents: return home.appendingPathComponent("Documents")
            case .downloads: return home.appendingPathComponent("Downloads")
            case .home: return home
            case .applications: return URL(fileURLWithPath: "/Applications")
            case .utilities: return URL(fileURLWithPath: "/Applications/Utilities")
            case .computer: return URL(fileURLWithPath: "/")
            }
        }
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                            _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        menu.addItem(item)
        return item
    }

    private static func submenu(_ title: String, in main: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        main.addItem(item)
        return menu
    }

    /// Clipboard, the clipboard history app: opened from the Edit menu, which only lists it when it is
    /// installed and turned on (Settings › Clipboard).
    private final class ClipboardApp: NSObject, NSMenuDelegate {
        static let shared = ClipboardApp()
        private static let bundleID = "local.suite.clipboard"

        func menuNeedsUpdate(_ menu: NSMenu) {
            let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) != nil
            let enabled = UserDefaults(suiteName: Self.bundleID)?.object(forKey: "isEnabled") as? Bool ?? true
            for item in menu.items where item.action == #selector(open) { item.isHidden = !(installed && enabled) }
        }

        /// Starts it if needed and shows its list; Explorer stays in front, so the item pastes here.
        @objc func open() {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.arguments = ["--show"]
            NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        }
    }

    /// With tabs turned off in Settings, the tab commands leave the menus.
    private final class TabItems: NSObject, NSMenuDelegate {
        static let shared = TabItems()
        private static let actions: Set<Selector> = [#selector(NSResponder.newWindowForTab(_:)),
                                                     #selector(NSWindow.toggleTabBar(_:))]

        func menuNeedsUpdate(_ menu: NSMenu) {
            for item in menu.items where item.action.map(Self.actions.contains) == true {
                item.isHidden = !WindowSettings.usesTabs
            }
        }
    }

    private final class Actions: NSObject, NSMenuItemValidation {
        static let shared = Actions()

        @objc func newWindow() {
            ExplorerWindowController.open(FileManager.default.homeDirectoryForCurrentUser, newWindow: true)
        }

        @objc func goToPlace(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            ExplorerWindowController.go(to: url)
        }

        /// Finder's Cmd+Shift+.: hidden files everywhere, the desktop included.
        @objc func toggleHiddenFiles() {
            DisplaySettings.showsHiddenFiles.toggle()
        }

        @objc func toggleExtensions() {
            DisplaySettings.showsFileExtensions.toggle()
        }

        @objc func toggleFullNames() {
            DisplaySettings.showsFullNameOfSelection.toggle()
        }

        func validateMenuItem(_ item: NSMenuItem) -> Bool {
            if item.action == #selector(toggleFullNames) {
                item.state = DisplaySettings.showsFullNameOfSelection ? .on : .off
            }
            if item.action == #selector(toggleHiddenFiles) {
                item.state = DisplaySettings.showsHiddenFiles ? .on : .off
            }
            if item.action == #selector(toggleExtensions) {
                item.state = DisplaySettings.showsFileExtensions ? .on : .off
            }
            return true
        }
    }
}
