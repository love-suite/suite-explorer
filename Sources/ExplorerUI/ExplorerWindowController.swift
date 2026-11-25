import AppKit
import ExplorerCore
import ExplorerSettings
import SuiteCore
import SuiteFilesCore
import SuiteFilesUI

final class ExplorerWindow: NSWindow {
    var onFocusAddressBar: (() -> Void)?
    /// Ctrl+F, Windows' Find (Cmd+F comes through the Edit menu).
    var onFocusSearch: (() -> Void)?
    /// Keyboard focus moved, for instance to the other pane of a Side by Side window.
    var onFirstResponderChange: (() -> Void)?

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let done = super.makeFirstResponder(responder)
        onFirstResponderChange?()
        return done
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isAddressBarShortcut(event) {
            onFocusAddressBar?()
            return true
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .control, event.charactersIgnoringModifiers?.lowercased() == "f" {
            onFocusSearch?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if Self.isAddressBarShortcut(event) {
            onFocusAddressBar?()
        } else {
            super.keyDown(with: event)
        }
    }

    /// Ctrl+L as in Explorer, Cmd+L as in Finder and browsers.
    private static func isAddressBarShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.charactersIgnoringModifiers?.lowercased() == "l" && (flags == .control || flags == .command)
    }
}

private extension NSToolbarItem.Identifier {
    // The folder trees' buttons: show or hide.
    static let leftSidebar = NSToolbarItem.Identifier("LeftSidebar")
    static let rightSidebar = NSToolbarItem.Identifier("RightSidebar")
    static let sidebarSeparator = NSToolbarItem.Identifier("SidebarSeparator")
    static let fileCommands = NSToolbarItem.Identifier("FileCommands")
    static let search = NSToolbarItem.Identifier("Search")
}

/// One Explorer window, laid out like Finder's: the folder tree runs the whole height on the left, the
/// toolbar holds the file commands, and below it one folder, or two Side by Side, each with its own
/// address bar. Side by Side, the second folder has its own tree on the right. Windows hold tabs unless
/// tabs are turned off.
public final class ExplorerWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation,
    NSToolbarDelegate {
    private static var openControllers: [ExplorerWindowController] = []
    private static let viewStore = FolderViewStore.shared
    private static let tabbingIdentifier = "ExplorerWindow"
    /// Called after the last Explorer window has closed.
    public static var onLastWindowClosed: (() -> Void)?

    public static var hasOpenWindows: Bool { !openControllers.isEmpty }

    /// The Go menu: shows `url` in the frontmost Explorer window, or opens it from the desktop.
    public static func go(to url: URL) {
        if let controller = NSApp.keyWindow?.windowController as? ExplorerWindowController {
            controller.active.navigate(to: url)
        } else {
            open(url)
        }
    }

    /// Opens each item's folder with the item selected, as "Show in Finder" does.
    public static func reveal(_ urls: [URL]) {
        let byFolder = Dictionary(grouping: urls.map(\.standardizedFileURL)) { $0.deletingLastPathComponent() }
        for (folder, items) in byFolder {
            open(folder, selecting: items)
        }
    }

    /// Opens a folder in a new tab of the frontmost Explorer window or in a window of its own, as set in
    /// Settings; `newWindow` always gives it its own window ("New Explorer Window").
    public static func open(_ url: URL, selecting selection: [URL] = [], newWindow: Bool = false) {
        let controller = ExplorerWindowController(url: url)
        openControllers.append(controller)
        NSApp.setActivationPolicy(.regular)
        if !newWindow, WindowSettings.opensFoldersInNewTab, let host = frontmost?.window, let tab = controller.window {
            host.addTabbedWindow(tab, ordered: .above)
            tab.makeKeyAndOrderFront(nil)
        } else {
            if let last = frontmost?.window {
                controller.window?.setFrameTopLeftPoint(NSPoint(x: last.frame.minX + 24, y: last.frame.maxY - 24))
            } else {
                controller.window?.center()
            }
            controller.showInOwnWindow()
        }
        controller.active.list.select(selection)
        NSApp.activate(ignoringOtherApps: true)
        sessionChanged()
    }

    // MARK: Windows kept across launches

    /// Set while the app quits: windows closing then are not closed by you, so they stay in the session.
    private static var isTerminating = false
    private static var pendingSave: DispatchWorkItem?
    private static let terminationObserver: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { _ in
        ExplorerWindowController.saveSessionNow()
        isTerminating = true
    }

    /// Writes the open windows down shortly after a change (a folder, a tab, a move, Side by Side).
    static func sessionChanged() {
        _ = terminationObserver
        guard !isTerminating else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { saveSessionNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private static func saveSessionNow() {
        guard !isTerminating else { return }
        var windows: [ExplorerSession.Window] = []
        var seen = Set<ObjectIdentifier>()
        // Front to back, each tab group once, its tabs in their order.
        for window in NSApp.orderedWindows where window.windowController is ExplorerWindowController {
            let group = window.tabbedWindows ?? [window]
            guard let first = group.first, seen.insert(ObjectIdentifier(first)).inserted else { continue }
            let tabs = group.compactMap { ($0.windowController as? ExplorerWindowController)?.sessionTab }
            guard !tabs.isEmpty else { continue }
            let selected = window.tabGroup?.selectedWindow.flatMap { group.firstIndex(of: $0) } ?? 0
            windows.append(ExplorerSession.Window(frame: window.frame, tabs: tabs, selectedTab: selected))
        }
        ExplorerSession(windows: windows).save()
    }

    /// A folder's path, or the address of a place that isn't a folder (`explorer:recents`).
    private static func sessionURL(_ saved: String) -> URL {
        saved.hasPrefix(VirtualPlace.scheme + ":") ? URL(string: saved) ?? URL(fileURLWithPath: saved)
            : URL(fileURLWithPath: saved)
    }

    private var sessionTab: ExplorerSession.Tab {
        ExplorerSession.Tab(folders: panes.map { $0.url.isFileURL ? $0.url.path : $0.url.absoluteString },
                            activePane: panes.firstIndex { $0 === active } ?? 0,
                            showsPreview: previewItem?.isCollapsed == false)
    }

    /// Reopens the windows of last time, as they were (Settings › Explorer); returns whether any came back.
    @discardableResult
    public static func restoreSession() -> Bool {
        _ = terminationObserver
        let session = ExplorerSession.load().existing {
            VirtualPlace(url: sessionURL($0)) != nil || FileManager.default.fileExists(atPath: $0)
        }
        for saved in session.windows.reversed() {
            var host: NSWindow?
            var selected: NSWindow?
            for (index, tab) in saved.tabs.enumerated() {
                let controller = ExplorerWindowController(url: sessionURL(tab.folders[0]))
                openControllers.append(controller)
                if tab.folders.count > 1 { controller.beginSplit(at: sessionURL(tab.folders[1])) }
                if tab.activePane < controller.panes.count { controller.activate(controller.panes[tab.activePane]) }
                if tab.showsPreview { controller.previewItem?.isCollapsed = false }
                guard let window = controller.window else { continue }
                if let host {
                    host.addTabbedWindow(window, ordered: .above)
                } else {
                    let frame = saved.rect
                    if frame.width > 0, let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })
                        ?? NSScreen.main {
                        window.setFrame(window.constrainFrameRect(frame, to: screen), display: false)
                    }
                    controller.showInOwnWindow()
                    host = window
                }
                if index == saved.selectedTab { selected = window }
            }
            selected?.makeKeyAndOrderFront(nil)
        }
        guard hasOpenWindows else { return false }
        NSApp.setActivationPolicy(.regular)
        return true
    }

    /// The Explorer window in front, if one is on screen.
    private static var frontmost: ExplorerWindowController? {
        NSApp.orderedWindows.lazy
            .filter { $0.isVisible && !$0.isMiniaturized }
            .compactMap { $0.windowController as? ExplorerWindowController }
            .first
    }

    private static var tabbingMode: NSWindow.TabbingMode {
        WindowSettings.usesTabs ? .automatic : .disallowed
    }

    /// Turning tabs off splits every tabbed window into windows of their own.
    private static let settingsObserver: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: WindowSettings.didChange, object: nil, queue: .main
    ) { _ in
        let windows = openControllers.compactMap(\.window)
        windows.forEach { $0.tabbingMode = tabbingMode }
        openControllers.forEach { $0.applySidebarStyles(); $0.applyToolbarLabels(); $0.updateCommands() }
        if !WindowSettings.usesTabs {
            let extraTabs = windows.filter { window in
                guard let group = window.tabbedWindows, group.count > 1 else { return false }
                return window !== group.first
            }
            extraTabs.forEach { $0.moveTabToNewWindow(nil) }
        }
        openControllers.forEach { $0.updateCommands() }
    }

    /// One folder, or two side by side, each with its folder tree; `active` is the one the toolbar and
    /// the menus act on.
    private var panes: [FolderPane] = []
    private var trees: [FolderTreeViewController] = []
    private var active: FolderPane
    private let split = NSSplitViewController()
    private let preview = PreviewViewController()
    private var previewItem: NSSplitViewItem?
    private var rightTreeItem: NSSplitViewItem?

    // The toolbar: file commands on the left, Side by Side on the right.
    private lazy var newFolderButton = command("folder.badge.plus", UIL("New Folder"), #selector(newFolderClicked))
    private lazy var renameButton = command("pencil", UIL("Rename"), #selector(renameClicked))
    private lazy var trashButton = command("trash", UIL("Move to Trash"), #selector(trashClicked), title: UIL("Trash"))
    private lazy var propertiesButton = command("info.circle", UIL("Properties"), #selector(propertiesClicked))
    private lazy var previewButton = command("doc.text.magnifyingglass", UIL("Preview Pane"),
                                             #selector(togglePreviewPane(_:)), toggle: true)
    private lazy var hiddenButton = command("eye", UIL("Show Hidden Files"), #selector(toggleHiddenFiles(_:)),
                                            toggle: true)
    private lazy var extensionsButton: NSButton = {
        let button = NSButton(title: ".ext", target: self, action: #selector(toggleExtensions(_:)))
        button.bezelStyle = .texturedRounded
        button.setButtonType(.pushOnPushOff)
        button.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        button.toolTip = UIL("Show File Extensions")
        return button
    }()
    // In the Trash, the commands are Windows' Recycle Bin ones.
    private lazy var putBackButton = command("arrow.uturn.backward", UIL("Put Back"), #selector(putBack(_:)))
    private lazy var deleteButton = command("xmark.bin", UIL("Delete Permanently"), #selector(deletePermanently(_:)))
    private lazy var emptyTrashButton = command("trash.slash", UIL("Empty Trash"), #selector(emptyTrash(_:)))
    private lazy var sideBySideButton = command("rectangle.split.2x1", UIL("Side by Side"),
                                                #selector(toggleSideBySide(_:)), toggle: true)
    private lazy var swapButton = command("arrow.left.arrow.right", UIL("Swap Sides"), #selector(swapSides(_:)), title: UIL("Swap"))
    /// The commands put in the + menu (Settings › Explorer › Toolbar), with their state.
    private lazy var moreButton = command("plus", UIL("More"), #selector(showMoreMenu(_:)))
    /// The commands' row in the toolbar, in the settings' order; what doesn't fit goes into ».
    private lazy var commandsBar: CommandsBar = {
        let bar = CommandsBar()
        bar.overflow.target = self
        bar.overflow.action = #selector(showOverflowMenu(_:))
        return bar
    }()
    private weak var commandsItem: NSToolbarItem?

    private var commandButtons: [ToolbarCommand: NSButton] {
        [.newFolder: newFolderButton, .rename: renameButton, .trash: trashButton, .properties: propertiesButton,
         .previewPane: previewButton, .hiddenFiles: hiddenButton, .fileExtensions: extensionsButton,
         .putBack: putBackButton, .deletePermanently: deleteButton, .emptyTrash: emptyTrashButton,
         .sideBySide: sideBySideButton, .swapSides: swapButton, .more: moreButton]
    }

    /// One search box for the window, as in Finder: it searches as you type, in the scope the active
    /// pane's scope bar shows (this Mac, a folder open in the window, or all of them). Side by Side, each
    /// pane has its own box instead, under the toolbar.
    private lazy var searchItem: NSSearchToolbarItem = {
        let item = NSSearchToolbarItem(itemIdentifier: .search)
        item.preferredWidthForSearchField = 240
        item.searchField.placeholderString = UIL("Search")
        item.searchField.sendsSearchStringImmediately = true
        item.searchField.target = self
        item.searchField.action = #selector(searchTextChanged(_:))
        item.label = UIL("Search")
        return item
    }()
    private static let scopeKey = "SearchScope"
    /// Side by Side, the toolbar has no room for the search box: it moves to a bar of its own under the
    /// toolbar, still one for the window, searching in the active folder.
    private lazy var searchBar: NSTitlebarAccessoryViewController = {
        let field = NSSearchField()
        field.placeholderString = UIL("Search")
        field.sendsSearchStringImmediately = true
        field.target = self
        field.action = #selector(searchTextChanged(_:))
        field.translatesAutoresizingMaskIntoConstraints = false
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 34))
        bar.addSubview(field)
        let preferred = field.widthAnchor.constraint(equalToConstant: 420)
        preferred.priority = .defaultHigh
        NSLayoutConstraint.activate([
            preferred,
            field.widthAnchor.constraint(lessThanOrEqualTo: bar.widthAnchor, constant: -32),
            field.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            field.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        let controller = NSTitlebarAccessoryViewController()
        controller.view = bar
        controller.layoutAttribute = .bottom
        return controller
    }()
    private var searchBarField: NSSearchField? { searchBar.view.subviews.first as? NSSearchField }
    /// The search box in use: the toolbar's, or the bar's Side by Side.
    private var searchField: NSSearchField { isSplit ? (searchBarField ?? searchItem.searchField) : searchItem.searchField }
    /// Searching waits for a short pause in the typing, not for Return.
    private var pendingSearch: DispatchWorkItem?

    /// The window beside this one while Side by Side uses two windows.
    private weak var partner: ExplorerWindowController?
    /// Where the window was before going side by side, to put it back.
    private var frameBeforeSideBySide: NSRect?

    private var isSplit: Bool { panes.count == 2 }

    private init(url: URL) {
        _ = Self.settingsObserver
        active = FolderPane(url: url)
        let window = ExplorerWindow(
            contentRect: NSRect(x: 0, y: 0, width: WindowSettings.newWindowWidth, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 320)
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.tabbingMode = Self.tabbingMode
        super.init(window: window)
        window.delegate = self
        window.onFocusAddressBar = { [weak self] in self?.active.addressBar.beginEditing() }
        window.onFocusSearch = { [weak self] in self?.focusSearch(nil) }
        window.onFirstResponderChange = { [weak self] in self?.activatePaneWithFocus() }
        buildLayout(in: window)
        applySidebarStyles()
        applyToolbarLabels()
        showActive()
        NotificationCenter.default.addObserver(forName: DisplaySettings.didChange, object: nil, queue: .main) {
            [weak self] _ in self?.updateCommands()
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows the window on its own even when macOS is set to always prefer tabs.
    private func showInOwnWindow() {
        window?.tabbingMode = .disallowed
        showWindow(nil)
        window?.tabbingMode = Self.tabbingMode
    }

    private func buildLayout(in window: NSWindow) {
        let tree = makeTree(for: active)
        let sidebar = NSSplitViewItem(sidebarWithViewController: tree)
        sidebar.minimumThickness = 180
        split.addSplitViewItem(sidebar)
        wire(active)
        panes = [active]
        split.addSplitViewItem(paneItem(active))
        let previewItem = NSSplitViewItem(viewController: preview)
        previewItem.minimumThickness = 240
        previewItem.canCollapse = true
        previewItem.isCollapsed = true
        split.addSplitViewItem(previewItem)
        self.previewItem = previewItem
        // The window takes the content view's size when it is assigned, so size the view first.
        split.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 600)
        window.contentViewController = split

        let toolbar = NSToolbar(identifier: "ExplorerWindow")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    private func makeTree(for pane: FolderPane) -> FolderTreeViewController {
        let tree = FolderTreeViewController()
        tree.onSelectFolder = { [weak self, weak pane] url in
            guard let self, let pane else { return }
            self.activate(pane)
            pane.navigate(to: url)
        }
        tree.onAirDrop = { [weak self, weak pane] dropped in
            guard let self, let pane else { return }
            self.sendWithAirDrop(dropped.isEmpty ? pane.list.selectedURLs : dropped)
        }
        trees.append(tree)
        return tree
    }

    /// AirDrop's own panel, with the devices nearby. Nothing chosen: says how to choose.
    private func sendWithAirDrop(_ urls: [URL]) {
        if let service = NSSharingService(named: .sendViaAirDrop), !urls.isEmpty, service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
            return
        }
        let alert = NSAlert()
        alert.messageText = "AirDrop"
        alert.informativeText = UIL("Select the files to send, then click AirDrop, or drop them on it.")
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    private func paneItem(_ pane: FolderPane) -> NSSplitViewItem {
        let item = NSSplitViewItem(viewController: pane)
        item.minimumThickness = 300
        return item
    }

    private func wire(_ pane: FolderPane) {
        pane.onScopeChange = { [weak self, weak pane] scope in
            guard let self, let pane else { return }
            UserDefaults.standard.set(scope.kind.rawValue, forKey: Self.scopeKey)
            pane.search(pane.searchText, scope: scope, choices: self.searchScopes(for: pane))
        }
        pane.onSearchEnd = { [weak self, weak pane] in
            guard let self, pane === self.active, !self.searchField.stringValue.isEmpty else { return }
            self.searchField.stringValue = ""
        }
        pane.onActivate = { [weak self, weak pane] in
            guard let self, let pane else { return }
            self.activate(pane)
        }
        pane.onFolderChange = { [weak self, weak pane] in
            guard let self, let pane else { return }
            self.tree(of: pane)?.reveal(pane.url)
            if pane === self.active { self.showActive() }
            Self.sessionChanged()
        }
        pane.onSelectionChange = { [weak self, weak pane] urls in
            guard let self, pane === self.active else { return }
            self.updateCommands()
            if self.previewItem?.isCollapsed == false { self.preview.show(urls) }
        }
    }

    private func tree(of pane: FolderPane) -> FolderTreeViewController? {
        guard let index = panes.firstIndex(where: { $0 === pane }), index < trees.count else { return nil }
        return trees[index]
    }

    /// A toolbar button: its icon, and its name beside it when labels are on (`title`, shorter than the
    /// tooltip's `label` where that one is long).
    private func command(_ symbol: String, _ label: String, _ action: Selector, title: String? = nil,
                         toggle: Bool = false) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(title: "", image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.setButtonType(toggle ? .pushOnPushOff : .momentaryPushIn)
        button.setAccessibilityLabel(label)
        labelledButtons.append((button, title ?? label))
        // Buttons are made when the toolbar first asks for them: they start as the setting says.
        if WindowSettings.showsToolbarLabels {
            button.title = title ?? label
            button.imagePosition = .imageLeading
        }
        return button
    }

    /// The buttons that can show their name, with it.
    private var labelledButtons: [(button: NSButton, title: String)] = []

    /// A name that follows what the button acts on: in the tooltip, and beside the icon when labels show.
    private func setTitle(_ title: String, of button: NSButton) {
        guard let index = labelledButtons.firstIndex(where: { $0.button === button }) else { return }
        labelledButtons[index].title = title
        if WindowSettings.showsToolbarLabels { button.title = title }
    }

    /// Names beside the icons, or icons only (Settings › Explorer › Toolbar).
    private func applyToolbarLabels() {
        let shown = WindowSettings.showsToolbarLabels
        for (button, title) in labelledButtons {
            button.title = shown ? title : ""
            button.imagePosition = shown ? .imageLeading : .imageOnly
        }
    }

    private func group(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.detachesHiddenViews = true
        return stack
    }

    // MARK: Toolbar

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarSeparator, .leftSidebar, .fileCommands, .flexibleSpace, .search]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.rightSidebar]
    }

    /// Side by Side in one window, the search box moves to its own bar under the toolbar, and the right
    /// tree's button takes its place.
    private func showSplitItems(_ shown: Bool) {
        guard let toolbar = window?.toolbar else { return }
        let search = toolbar.items.firstIndex { $0.itemIdentifier == .search }
        let right = toolbar.items.firstIndex { $0.itemIdentifier == .rightSidebar }
        if shown {
            if let search { toolbar.removeItem(at: search) }
            if right == nil { toolbar.insertItem(withItemIdentifier: .rightSidebar, at: toolbar.items.count) }
        } else {
            if let right { toolbar.removeItem(at: right) }
            if search == nil { toolbar.insertItem(withItemIdentifier: .search, at: toolbar.items.count) }
        }
        if shown, let window, !window.titlebarAccessoryViewControllers.contains(searchBar) {
            searchBarField?.stringValue = active.searchText
            window.addTitlebarAccessoryViewController(searchBar)
        } else if !shown, let index = window?.titlebarAccessoryViewControllers.firstIndex(of: searchBar) {
            window?.removeTitlebarAccessoryViewController(at: index)
            searchItem.searchField.stringValue = active.searchText
        }
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                        willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case .leftSidebar, .rightSidebar:
            return sidebarItem(identifier, left: identifier == .leftSidebar)
        case .sidebarSeparator:
            // Keeps the commands to the right of the folder tree, which runs up to the top of the window.
            return NSTrackingSeparatorToolbarItem(identifier: identifier, splitView: split.splitView, dividerIndex: 0)
        case .search:
            searchItem.visibilityPriority = .high
            return searchItem
        case .fileCommands:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = commandsBar
            // Shrinks with the window down to its last button, the rest going into » (the toolbar reads
            // these sizes, not the view's constraints); kept in the toolbar rather than sent whole into ».
            item.visibilityPriority = .high
            commandsItem = item
            updateCommands()
            item.label = UIL("Commands")
            return item
        default:
            return nil
        }
    }

    // MARK: Folder trees

    /// Shows or hides the tree. It sits first among the commands, just past the tree, in every style, so it
    /// doesn't jump when the tree comes and goes. How the tree shows is in its right-click menu and in
    /// the settings.
    private func sidebarItem(_ identifier: NSToolbarItem.Identifier, left: Bool) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        let label = left ? UIL("Sidebar") : UIL("Right Sidebar")
        item.image = NSImage(systemSymbolName: left ? "sidebar.left" : "sidebar.right", accessibilityDescription: label)
        item.label = label
        item.toolTip = UIL("Show or hide the sidebar")
        item.isBordered = true
        item.target = self
        item.action = left ? #selector(toggleFolderTree(_:)) : #selector(toggleRightFolderTree(_:))
        return item
    }

    /// The trees as set in the settings, in every window.
    fileprivate func applySidebarStyles() {
        if let item = split.splitViewItems.first, let tree = trees.first {
            apply(WindowSettings.leftSidebar, to: item, tree: tree)
        }
        if let item = rightTreeItem, trees.count > 1 {
            apply(WindowSettings.rightSidebar, to: item, tree: trees[1])
        }
        placeSidebarSeparator()
    }

    /// Icons and names, the tree runs the whole height of the window, beside the toolbar; icons only, the
    /// strip starts under the toolbar, which runs the whole width.
    private func placeSidebarSeparator() {
        // Hidden, the toolbar stays as it was for the style the tree comes back in.
        let style = WindowSettings.leftSidebar == .hidden ? WindowSettings.shownStyle(left: true) : WindowSettings.leftSidebar
        let fullHeight = style != .icons
        if let item = split.splitViewItems.first, item.allowsFullHeightLayout != fullHeight {
            item.allowsFullHeightLayout = fullHeight
        }
        trees.first?.startsBelowToolbar = !fullHeight
        guard let toolbar = window?.toolbar else { return }
        let index = toolbar.items.firstIndex { $0.itemIdentifier == .sidebarSeparator }
        if fullHeight, index == nil {
            toolbar.insertItem(withItemIdentifier: .sidebarSeparator, at: 0)
        } else if !fullHeight, let index {
            toolbar.removeItem(at: index)
        }
    }

    private func apply(_ style: WindowSettings.SidebarStyle, to item: NSSplitViewItem, tree: FolderTreeViewController) {
        // Hiding only folds the tree away: it keeps its style (and width) while it goes, so an icons-only
        // strip doesn't flash its names on the way out.
        if style == .hidden {
            item.canCollapse = true
            if !item.isCollapsed {
                if window?.isVisible == true { item.animator().isCollapsed = true } else { item.isCollapsed = true }
            }
            return
        }
        let iconsOnly = style == .icons
        tree.iconsOnly = iconsOnly
        item.canCollapse = true
        if iconsOnly {
            item.minimumThickness = FolderTreeViewController.iconsOnlyWidth
            item.maximumThickness = FolderTreeViewController.iconsOnlyWidth
        } else {
            item.maximumThickness = NSSplitViewItem.unspecifiedDimension
            item.minimumThickness = 180
        }
        let hidden = style == .hidden
        if item.isCollapsed != hidden {
            if window?.isVisible == true { item.animator().isCollapsed = hidden } else { item.isCollapsed = hidden }
        }
        guard !hidden else { return }
        // The split view keeps the old width until told: move the tree's divider to the new one.
        let width: CGFloat = iconsOnly ? FolderTreeViewController.iconsOnlyWidth
            : max(item.viewController.view.frame.width, 200)
        guard iconsOnly || item.viewController.view.frame.width < 180,
              let index = split.splitViewItems.firstIndex(of: item) else { return }
        split.view.layoutSubtreeIfNeeded()
        let splitView = split.splitView
        if index == 0 {
            splitView.setPosition(width, ofDividerAt: 0)
        } else {
            splitView.setPosition(splitView.bounds.width - width - splitView.dividerThickness, ofDividerAt: index - 1)
        }
    }

    @objc func toggleFolderTree(_ sender: Any?) {
        WindowSettings.leftSidebar = WindowSettings.leftSidebar == .hidden
            ? WindowSettings.shownStyle(left: true) : .hidden
    }

    @objc func toggleRightFolderTree(_ sender: Any?) {
        WindowSettings.rightSidebar = WindowSettings.rightSidebar == .hidden
            ? WindowSettings.shownStyle(left: false) : .hidden
    }

    @objc func toggleHiddenFiles(_ sender: Any?) {
        DisplaySettings.showsHiddenFiles.toggle()
    }

    @objc func toggleExtensions(_ sender: Any?) {
        DisplaySettings.showsFileExtensions.toggle()
    }

    // MARK: Active pane

    /// Clicking into the other pane makes it the active one.
    private func activatePaneWithFocus() {
        guard isSplit, let view = window?.firstResponder as? NSView,
              let pane = panes.first(where: { view.isDescendant(of: $0.view) }), pane !== active else { return }
        activate(pane)
    }

    private func activate(_ pane: FolderPane) {
        guard pane !== active else { return }
        active = pane
        // The search box shows the active pane's search.
        if searchField.stringValue != pane.searchText { searchField.stringValue = pane.searchText }
        showActive()
    }

    /// The title, the toolbar and the preview follow the active pane.
    private func showActive() {
        let url = active.url
        panes.forEach { $0.marksActive = $0 === active && isSplit }
        window?.title = isSplit
            ? panes.map { VirtualPlace.title(of: $0.url) }.joined(separator: " — ")
            : VirtualPlace.title(of: url)
        window?.representedURL = url.isFileURL ? url : nil
        preview.show(previewItem?.isCollapsed == false ? active.list.selectedURLs : [])
        updateCommands()
    }

    // MARK: Navigation (menus)

    @objc func goBack(_ sender: Any?) { active.back() }
    @objc func goForward(_ sender: Any?) { active.forward() }
    @objc func goUp(_ sender: Any?) { active.up() }

    // MARK: Commands

    private var isInTrash: Bool { TrashFolder.contains(active.url) }

    private func updateCommands() {
        let count = active.list.selectedURLs.count
        let paired = isSplit || partner != nil
        let inTrash = isInTrash
        // Each command where the settings put it, if it applies here (the Trash's own commands only there).
        let layout = WindowSettings.toolbarLayout
        let buttons = commandButtons
        // Under the mouse, the bar shows the name and what it does at once; no tooltip, which waits.
        for (command, button) in buttons {
            button.toolTip = nil
            button.setAccessibilityHelp(command.help)
        }
        commandsBar.title = { [weak self] command in
            guard let self else { return command.title }
            switch command {
            case .deletePermanently:
                return self.labelledButtons.first { $0.button === self.deleteButton }?.title ?? command.title
            case .fileExtensions:
                return DisplaySettings.showsFileExtensions ? "Hide File Extensions" : "Show File Extensions"
            default: return command.title
            }
        }
        // + only when its menu has something.
        let menuEmpty = layout.commands(.menu, inTrash: inTrash, sideBySide: paired).isEmpty
        let shown = layout.commands(.toolbar, inTrash: inTrash, sideBySide: paired).filter { !(menuEmpty && $0 == .more) }
        commandsBar.show(shown, buttons: shown.compactMap { buttons[$0] })
        commandsItem?.minSize = NSSize(width: 34, height: 28)
        commandsItem?.maxSize = NSSize(width: commandsBar.intrinsicContentSize.width, height: 28)
        renameButton.isEnabled = count == 1
        trashButton.isEnabled = count > 0
        propertiesButton.isEnabled = count > 0
        putBackButton.isEnabled = !active.list.selectedURLs.filter(TrashLedger.shared.canPutBack).isEmpty
        deleteButton.isEnabled = count > 0
        // Says what it erases, unlike Empty Trash beside it, which erases everything.
        let selected = active.list.selectedItems
        let what: String
        switch selected.count {
        case 0: what = "Delete Permanently"
        case 1: what = selected[0].isFolder ? "Delete This Folder Permanently" : "Delete This File Permanently"
        default: what = "Delete These \(selected.count) Items Permanently"
        }
        setTitle(what, of: deleteButton)
        previewButton.state = previewItem?.isCollapsed == false ? .on : .off
        hiddenButton.state = DisplaySettings.showsHiddenFiles ? .on : .off
        extensionsButton.state = DisplaySettings.showsFileExtensions ? .on : .off
        extensionsButton.toolTip = DisplaySettings.showsFileExtensions ? UIL("Hide File Extensions") : UIL("Show File Extensions")
        hiddenButton.image = NSImage(systemSymbolName: DisplaySettings.showsHiddenFiles ? "eye" : "eye.slash",
                                     accessibilityDescription: hiddenButton.toolTip)
        sideBySideButton.state = paired ? .on : .off
    }

    /// The + menu: the commands put there, each with its icon, its name and, for those that are on or off,
    /// a check mark; dimmed when they can't act on the selection.
    @objc private func showMoreMenu(_ sender: NSButton) {
        updateCommands()
        popUp(WindowSettings.toolbarLayout.commands(.menu, inTrash: isInTrash, sideBySide: isSplit || partner != nil),
              under: sender)
    }

    /// »: the buttons the window is too narrow for; + among them brings its menu's commands after a line.
    @objc private func showOverflowMenu(_ sender: NSButton) {
        updateCommands()
        var commands = commandsBar.overflowed.filter { $0 != .more }
        if commandsBar.overflowed.contains(.more) {
            let inMenu = WindowSettings.toolbarLayout.commands(.menu, inTrash: isInTrash, sideBySide: isSplit || partner != nil)
            if !commands.isEmpty && !inMenu.isEmpty { commands.append(.more) }
            commands += inMenu
        }
        popUp(commands, under: sender)
    }

    /// A menu of commands (`.more` stands for a line between groups).
    private func popUp(_ commands: [ToolbarCommand], under sender: NSButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let buttons = commandButtons
        for command in commands {
            if command == .more {
                menu.addItem(.separator())
                continue
            }
            guard let button = buttons[command] else { continue }
            let title = commandsBar.title(command)
            let item = NSMenuItem(title: title, action: button.action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: command.symbol, accessibilityDescription: title)
            item.state = command.isToggle && button.state == .on ? .on : .off
            item.isEnabled = button.isEnabled
            item.toolTip = command.help
            menu.addItem(item)
        }
        let below = NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.height + 4 : -4)
        menu.popUp(positioning: nil, at: below, in: sender)
    }

    @objc private func newFolderClicked() { active.list.newFolder(nil) }
    @objc private func renameClicked() { active.list.renameSelection(nil) }
    @objc private func trashClicked() { active.list.moveToTrash(nil) }
    @objc private func propertiesClicked() { active.list.showProperties(nil) }

    // MARK: Trash

    /// Puts the selected items back where they were deleted from, and stays in the Trash.
    @objc func putBack(_ sender: Any?) {
        FileActions.putBack(active.list.selectedURLs)
        active.list.reload()
    }

    @objc func deletePermanently(_ sender: Any?) {
        FileActions.deletePermanently(active.list.selectedURLs)
        active.list.reload()
    }

    @objc func emptyTrash(_ sender: Any?) {
        FileActions.emptyTrash()
        active.list.reload()
    }

    // MARK: Side by side

    /// Shows two folders next to each other, to copy or move files between them: in two panes of this
    /// window, or in two windows on half of the screen each (Settings). The other folder starts on the next
    /// tab's folder, or else this same one; tabs stay as they are. Again, it closes the other side.
    @objc func toggleSideBySide(_ sender: Any?) {
        if isSplit {
            endSplit()
        } else if let partner {
            endSideBySide(with: partner)
        } else if WindowSettings.sideBySideInOneWindow {
            beginSplit()
        } else {
            beginSideBySide()
        }
    }

    /// The folder of the tab beside this one, where the other side starts.
    private var neighbourFolder: URL? {
        guard let window, let tabs = window.tabbedWindows, let index = tabs.firstIndex(of: window),
              let next = WindowTiling.neighbour(of: index, count: tabs.count),
              let neighbour = tabs[next].windowController as? ExplorerWindowController else { return nil }
        return neighbour.active.url
    }

    private func beginSplit(at chosen: URL? = nil) {
        guard let window else { return }
        defer { Self.sessionChanged() }
        let url = chosen ?? neighbourFolder ?? active.url
        let left = active
        let pane = FolderPane(url: url)
        wire(pane)
        panes.append(pane)
        // The second folder's tree mirrors the first one, on the right edge.
        let tree = makeTree(for: pane)
        tree.isRightSide = true
        let treeItem: NSSplitViewItem
        if #available(macOS 14.0, *) {
            treeItem = NSSplitViewItem(inspectorWithViewController: tree)
        } else {
            treeItem = NSSplitViewItem(viewController: tree)
        }
        treeItem.minimumThickness = 180
        treeItem.canCollapse = false
        split.insertSplitViewItem(paneItem(pane), at: 2)
        split.addSplitViewItem(treeItem)
        rightTreeItem = treeItem
        tree.reveal(pane.url)
        showSplitItems(true)
        applySidebarStyles()
        // Two folders need room: a small window grows to the whole screen, and shrinks back afterwards.
        if let screen = window.screen ?? NSScreen.main, window.frame.width < 1200,
           !window.styleMask.contains(.fullScreen) {
            frameBeforeSideBySide = window.frame
            window.setFrame(screen.visibleFrame, display: true, animate: true)
        }
        equalizePanes()
        active = pane
        activate(left)
        left.list.focus()
        showActive()
    }

    /// Two folders of the same width, once the split view has laid out the new pane.
    private func equalizePanes() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isSplit else { return }
            self.split.view.layoutSubtreeIfNeeded()
            // Arranged subviews follow the items: tree, left pane, right pane, preview, right tree.
            let views = self.split.splitView.arrangedSubviews
            guard views.count > 2 else { return }
            let start = views[1].frame.minX
            let end = views[2].frame.maxX
            let divider = self.split.splitView.dividerThickness
            self.split.splitView.setPosition(((start + end - divider) / 2).rounded(), ofDividerAt: 1)
        }
    }

    private func endSplit() {
        defer { Self.sessionChanged() }
        guard let window else { return }
        let right = panes.removeLast()
        trees.removeLast()
        if let item = split.splitViewItem(for: right) { split.removeSplitViewItem(item) }
        if let item = rightTreeItem { split.removeSplitViewItem(item) }
        rightTreeItem = nil
        active = panes[0]
        showSplitItems(false)
        if let frame = frameBeforeSideBySide {
            window.setFrame(frame, display: true, animate: true)
            frameBeforeSideBySide = nil
        }
        active.list.focus()
        showActive()
    }

    private func beginSideBySide() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let other = ExplorerWindowController(url: neighbourFolder ?? active.url)
        Self.openControllers.append(other)
        frameBeforeSideBySide = window.frame
        partner = other
        other.partner = self
        let (left, right) = WindowTiling.halves(of: screen.visibleFrame)
        other.window?.setFrame(right, display: false)
        other.showInOwnWindow()
        window.animator().setFrame(left, display: true)
        window.makeKeyAndOrderFront(nil)
        updateCommands()
        other.updateCommands()
    }

    private func endSideBySide(with other: ExplorerWindowController) {
        partner = nil
        other.partner = nil
        guard let window else { return }
        other.close()
        if let frame = frameBeforeSideBySide ?? other.frameBeforeSideBySide {
            window.animator().setFrame(frame, display: true)
        }
        frameBeforeSideBySide = nil
        other.frameBeforeSideBySide = nil
        window.makeKeyAndOrderFront(nil)
        updateCommands()
        other.updateCommands()
    }

    /// The two folders change sides.
    @objc func swapSides(_ sender: Any?) {
        guard let other = otherSide else { return }
        let mine = active.url, theirs = other.url
        active.navigate(to: theirs)
        other.navigate(to: mine)
        updateCommands()
    }

    @objc func copyToOtherSide(_ sender: Any?) { transferToOtherSide(.copy) }
    @objc func moveToOtherSide(_ sender: Any?) { transferToOtherSide(.move) }

    /// The folder on the other side: the other pane, or the other window.
    private var otherSide: FolderPane? {
        isSplit ? panes.first { $0 !== active } : partner?.active
    }

    private func transferToOtherSide(_ operation: TransferOperation) {
        guard let other = otherSide else { return }
        let urls = active.list.selectedURLs
        guard !urls.isEmpty else { return }
        guard other.url.isFileURL else { return }
        let arrived = FileDrop.transfer(urls, into: other.url, operation: operation)
        active.list.reload()
        other.list.reload()
        other.list.select(arrived)
        // Selecting in the other pane must not make it the active one.
        if isSplit { active.list.focus() }
        updateCommands()
    }

    // MARK: Search

    /// Typing in the search box searches after a short pause; clearing it shows the folder again.
    @objc func searchTextChanged(_ sender: NSSearchField) {
        scheduleSearch(sender.stringValue, in: active)
    }

    private func scheduleSearch(_ typed: String, in pane: FolderPane) {
        pendingSearch?.cancel()
        let text = typed.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            pane.clearSearch()
            return
        }
        let work = DispatchWorkItem { [weak self, weak pane] in
            guard let self, let pane else { return }
            self.search(text, in: pane)
        }
        pendingSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func search(_ text: String, in pane: FolderPane) {
        let choices = searchScopes(for: pane)
        // A search already under way keeps its scope; a new one starts where the last one looked.
        let scope = pane.searchScope.flatMap { current in choices.first { $0 == current } }
            ?? SearchScope.initial(in: choices, remembered: UserDefaults.standard.string(forKey: Self.scopeKey)
                .flatMap(SearchScope.Kind.init(rawValue:)))
        guard let scope else { return }
        pane.search(text, scope: scope, choices: choices)
    }

    /// This Mac, the pane's folder, the other folders open in the window (the other side, the other
    /// tabs), and all of them.
    private func searchScopes(for pane: FolderPane) -> [SearchScope] {
        var open = panes.filter { $0 !== pane }.map(\.url)
        if let partner { open += partner.panes.map(\.url) }
        for tab in window?.tabbedWindows ?? [] where tab !== window {
            if let other = tab.windowController as? ExplorerWindowController { open += other.panes.map(\.url) }
        }
        return SearchScope.choices(current: pane.url, open: open) { FileManager.default.displayName(atPath: $0.path) }
    }

    // MARK: Menu actions (reached through the responder chain)

    @objc func togglePreviewPane(_ sender: Any?) {
        guard let previewItem else { return }
        defer { Self.sessionChanged() }
        previewItem.animator().isCollapsed.toggle()
        preview.show(previewItem.isCollapsed ? [] : active.list.selectedURLs)
        updateCommands()
    }

    @objc func focusAddressBar(_ sender: Any?) {
        active.addressBar.beginEditing()
    }

    @objc func showAsIcons(_ sender: Any?) { active.list.setMode(.icons) }
    @objc func showAsDetails(_ sender: Any?) { active.list.setMode(.details) }
    @objc func showAsColumns(_ sender: Any?) { active.list.setMode(.columns) }
    /// Cmd+F, Ctrl+F.
    @objc func focusSearch(_ sender: Any?) {
        if isSplit { window?.makeFirstResponder(searchBarField) } else { searchItem.beginSearchInteraction() }
    }
    @objc func sortByName(_ sender: Any?) { active.list.sort(by: .name) }
    @objc func sortByDate(_ sender: Any?) { active.list.sort(by: .modified) }
    @objc func sortBySize(_ sender: Any?) { active.list.sort(by: .size) }
    @objc func sortByKind(_ sender: Any?) { active.list.sort(by: .kind) }

    /// Like Windows' "Apply to Folders": this folder's view becomes the one every folder uses.
    @objc func applyViewToAllFolders(_ sender: Any?) {
        Self.viewStore.applyToAll(active.list.options)
    }

    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let options = active.list.options
        let sorts: [Selector: SortKey] = [
            #selector(sortByName(_:)): .name, #selector(sortByDate(_:)): .modified,
            #selector(sortBySize(_:)): .size, #selector(sortByKind(_:)): .kind,
        ]
        switch item.action {
        case #selector(goBack(_:)): return active.history.canGoBack
        case #selector(goForward(_:)): return active.history.canGoForward
        case #selector(goUp(_:)): return active.history.canGoUp
        case #selector(newWindowForTab(_:)): return WindowSettings.usesTabs
        case #selector(toggleSideBySide(_:)):
            item.state = isSplit || partner != nil ? .on : .off
        case #selector(swapSides(_:)):
            return otherSide != nil
        case #selector(toggleFolderTree(_:)):
            item.title = WindowSettings.leftSidebar == .hidden ? UIL("Show Sidebar") : UIL("Hide Sidebar")
        case #selector(toggleHiddenFiles(_:)):
            item.state = DisplaySettings.showsHiddenFiles ? .on : .off
        case #selector(copyToOtherSide(_:)), #selector(moveToOtherSide(_:)):
            return otherSide?.url.isFileURL == true && !active.list.selectedURLs.isEmpty
        case #selector(putBack(_:)):
            return isInTrash && putBackButton.isEnabled
        case #selector(deletePermanently(_:)):
            return isInTrash && !active.list.selectedURLs.isEmpty
        case #selector(togglePreviewPane(_:)):
            item.state = previewItem?.isCollapsed == false ? .on : .off
        case #selector(showAsIcons(_:)):
            item.state = options.mode == .icons ? .on : .off
        case #selector(showAsDetails(_:)):
            item.state = options.mode == .details ? .on : .off
        case #selector(showAsColumns(_:)):
            item.state = options.mode == .columns ? .on : .off
        case let action? where sorts[action] != nil:
            let current = sorts[action] == options.sortKey
            item.state = current ? .on : .off
            // Choosing the current key again reverses it, so say which way it goes now.
            item.title = item.title.replacingOccurrences(of: " ↑", with: "").replacingOccurrences(of: " ↓", with: "")
                + (current ? (options.ascending ? " ↑" : " ↓") : "")
        default:
            break
        }
        return true
    }

    public override func newWindowForTab(_ sender: Any?) {
        guard WindowSettings.usesTabs, let window else { return }
        let controller = ExplorerWindowController(url: active.url)
        Self.openControllers.append(controller)
        if let tab = controller.window {
            window.addTabbedWindow(tab, ordered: .above)
            tab.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: Window

    public func windowDidResize(_ notification: Notification) {
        Self.sessionChanged()
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        // A tab brought to the front, a window raised.
        Self.sessionChanged()
    }

    public func windowDidMove(_ notification: Notification) {
        Self.sessionChanged()
        guard partner != nil else { return }
        updateCommands()
        partner?.updateCommands()
    }

    public func windowWillClose(_ notification: Notification) {
        if let partner {
            partner.partner = nil
            partner.updateCommands()
        }
        Self.openControllers.removeAll { $0 === self }
        // Closed by you: gone from the windows that come back (not when the app quits).
        Self.sessionChanged()
        if Self.openControllers.isEmpty {
            DispatchQueue.main.async { Self.onLastWindowClosed?() }
        }
    }
}
