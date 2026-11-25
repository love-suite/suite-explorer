import AppKit
import ExplorerCore
import ExplorerSettings
import Quartz
import SuiteCore
import SuiteFilesCore
import SuiteFilesUI

/// Gets keys first, so the space bar previews instead of starting type-select.
private final class ExplorerOutlineView: NSOutlineView {
    var keyHandler: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }
}

private final class ExplorerBrowser: NSBrowser {
    var keyHandler: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let name = NSUserInterfaceItemIdentifier("Name")
    static let modified = NSUserInterfaceItemIdentifier("Modified")
    static let size = NSUserInterfaceItemIdentifier("Size")
    static let kind = NSUserInterfaceItemIdentifier("Kind")
    /// In the Trash only: the folder an item was deleted from, as Windows' Recycle Bin shows.
    static let origin = NSUserInterfaceItemIdentifier("Origin")
}

/// A file or folder in the details list or the columns, its subfolder contents loaded when opened.
final class FileNode {
    let item: FileItem
    private let sorting: FolderViewOptions
    private var loaded: [FileNode]?

    init(_ item: FileItem, sorting: FolderViewOptions) {
        self.item = item
        self.sorting = sorting
    }

    var url: URL { item.url }
    var isFolder: Bool { item.isFolder }

    var children: [FileNode] {
        if let loaded { return loaded }
        let items = item.isFolder
            ? ((try? DirectoryLoader.load(item.url, showHidden: DisplaySettings.showsHiddenFiles)) ?? []) : []
        let nodes = FileSorter.sorted(items, by: sorting.sortKey, ascending: sorting.ascending,
                                      foldersFirst: DisplaySettings.sortsFoldersFirst)
            .map { FileNode($0, sorting: sorting) }
        loaded = nodes
        return nodes
    }
}

/// The contents of a folder, as icons, as a details list whose folders unfold (Finder's list view), or
/// as columns, sorted and laid out according to the folder's view options. Answers the Windows keys
/// (Ctrl+C, Ctrl+V, Delete, F2, Enter, Backspace…), renames in place and shows search results.
final class FileListViewController: NSViewController, FileCommandHandling {
    var onOpenFolder: ((URL) -> Void)?
    var onSelectionChange: (([URL]) -> Void)?
    /// Called whenever the user changes how this folder is shown, so it can be remembered.
    var onOptionsChange: ((FolderViewOptions) -> Void)?
    /// Backspace and Alt+arrows, handled by the pane that owns the history.
    var onGoUp: (() -> Void)?
    var onGoBack: (() -> Void)?
    var onGoForward: (() -> Void)?

    private(set) var options = FolderViewOptions()
    /// The folder shown; while searching, the folder searched.
    private(set) var directory: URL?
    /// Search results replace the folder's contents until the search is cleared.
    private(set) var isShowingResults = false

    private let outline = ExplorerOutlineView()
    private let outlineScroll = NSScrollView()
    private let icons = IconCollectionView()
    private let iconScroll = NSScrollView()
    private let browser = ExplorerBrowser()
    private let nameOverlay = FullNameOverlay()
    /// No full name under the icon while it is being renamed.
    private var isRenaming = false
    private let quickLook = QuickLook()
    private let message = NSTextField(wrappingLabelWithString: "")
    /// Under the message, when there is something to do about it (Full Disk Access for the Trash).
    private let messageButton = NSButton(title: UIL("Open Full Disk Access Settings"), target: nil, action: nil)
    /// Under it: the setting only takes effect once Explorer starts again.
    private let restartButton = NSButton(title: UIL("Quit & Reopen Explorer"), target: nil, action: nil)
    private(set) var items: [FileItem] = []
    private var nodes: [FileNode] = []
    private var browserRoot: FileNode?
    private var watcher: DirectoryWatcher?
    /// Set while options are pushed into the views, whose change callbacks must not count as user changes.
    private var isApplyingOptions = false
    /// Rows currently drawn with their full name, so they can shrink back when deselected.
    private var expandedRows = IndexSet()
    private var typeSelect = TypeSelect()
    /// Set while an outgoing drag session is active; reloads are deferred until it ends.
    private var isDraggingOut = false
    private var pendingReload = false
    /// The items being dragged out, shown faded where they are.
    private var draggingURLs: Set<URL> = []
    /// The rows dragged out of the columns, drawn again when the drag ends.
    private var browserDrag: (rows: IndexSet, column: Int)?
    private var showsHidden = DisplaySettings.showsHiddenFiles
    private var showsICloudTrash = DisplaySettings.showsICloudTrash
    private var namesShown = (DisplaySettings.showsFileExtensions, DisplaySettings.showsSyncBadges,
                              DisplaySettings.syncBadgeStyle == .onIcon)

    private static let rowHeight: CGFloat = 22
    /// Name column width taken by the disclosure triangle, the icon and padding (see TableCells).
    private static let nameInset: CGFloat = 28
    private static let columns: [(id: NSUserInterfaceItemIdentifier, title: String, width: CGFloat, key: SortKey)] = [
        (.name, UIL("Name"), 300, .name), (.modified, UIL("Date Modified"), 150, .modified),
        (.size, UIL("Size"), 80, .size), (.kind, UIL("Type"), 160, .kind),
    ]

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    // MARK: Setup

    override func loadView() {
        setUpOutline()
        setUpIcons()
        setUpBrowser()

        message.alignment = .center
        message.textColor = .secondaryLabelColor
        message.isHidden = true
        messageButton.target = self
        messageButton.action = #selector(openAccessSettings)
        messageButton.isHidden = true
        messageButton.bezelStyle = .rounded
        messageButton.keyEquivalent = "\r"
        restartButton.target = self
        restartButton.action = #selector(restart)
        restartButton.bezelStyle = .rounded
        restartButton.isHidden = true

        let container = NSView()
        for subview in [outlineScroll, iconScroll, browser, message, messageButton, restartButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        var constraints = [
            message.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -40),
            messageButton.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 12),
            messageButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            restartButton.topAnchor.constraint(equalTo: messageButton.bottomAnchor, constant: 8),
            restartButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            restartButton.widthAnchor.constraint(equalTo: messageButton.widthAnchor),
        ]
        for view in [outlineScroll, iconScroll, browser] as [NSView] {
            constraints += [
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        view = container

        let center = NotificationCenter.default
        for name in [IconPickerWindow.didChange, FileUndo.didChange] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reload() }
        }
        center.addObserver(forName: DisplaySettings.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            // Hidden files shown or not: the folder is read again.
            if self.showsHidden != DisplaySettings.showsHiddenFiles {
                self.showsHidden = DisplaySettings.showsHiddenFiles
                self.reload()
            } else if self.showsICloudTrash != DisplaySettings.showsICloudTrash {
                // iCloud Drive's Trash added to the Trash or taken out of it.
                self.showsICloudTrash = DisplaySettings.showsICloudTrash
                self.reload()
            }
            // Names and badges drawn again.
            let shown = (DisplaySettings.showsFileExtensions, DisplaySettings.showsSyncBadges,
                         DisplaySettings.syncBadgeStyle == .onIcon)
            if self.namesShown != shown {
                self.namesShown = shown
                self.outline.reloadData()
                self.browser.loadColumnZero()
                self.updateExpandedRows()
            }
            self.updateExpandedRows()
            self.reloadIcons()
            self.updateNameOverlay()
        }
        showMode()
    }

    private func setUpOutline() {
        for column in Self.columns {
            let tableColumn = NSTableColumn(identifier: column.id)
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.key.rawValue, ascending: true)
            outline.addTableColumn(tableColumn)
        }
        let origin = NSTableColumn(identifier: .origin)
        origin.title = "Original Location"
        origin.width = 260
        origin.isHidden = true
        outline.addTableColumn(origin)
        outline.outlineTableColumn = outline.tableColumns.first
        outline.dataSource = self
        outline.delegate = self
        outline.allowsMultipleSelection = true
        outline.usesAlternatingRowBackgroundColors = true
        outline.rowHeight = Self.rowHeight
        outline.indentationPerLevel = 14
        outline.autoresizesOutlineColumn = false
        outline.target = self
        outline.doubleAction = #selector(outlineDoubleClicked)
        outline.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        outline.menu = contextMenu()
        outline.registerForDraggedTypes(FileDrop.draggedTypes)
        outline.setDraggingSourceOperationMask(.every, forLocal: false)
        outline.setDraggingSourceOperationMask([.move, .copy, .generic], forLocal: true)
        outlineScroll.documentView = outline
        outlineScroll.hasVerticalScroller = true
    }

    private func setUpIcons() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = IconItemView.size
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        icons.collectionViewLayout = layout
        icons.dataSource = self
        icons.delegate = self
        icons.isSelectable = true
        icons.allowsMultipleSelection = true
        icons.backgroundColors = [.textBackgroundColor]
        // Layer-backed so the full-name labels can sit above the items (zPosition).
        icons.wantsLayer = true
        icons.register(IconItemView.self, forItemWithIdentifier: IconItemView.reuseID)
        icons.onDoubleClick = { [weak self] indexPath in
            guard let self, indexPath.item < self.items.count else { return }
            self.open(self.items[indexPath.item])
        }
        icons.menuProvider = { [weak self] _ in
            // Right-click changes the selection without telling the delegate.
            self?.selectionChanged()
            return self?.contextMenu()
        }
        icons.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        icons.registerForDraggedTypes(FileDrop.draggedTypes)
        icons.setDraggingSourceOperationMask(.every, forLocal: false)
        icons.setDraggingSourceOperationMask([.move, .copy, .generic], forLocal: true)
        iconScroll.documentView = icons
        iconScroll.hasVerticalScroller = true
    }

    private func setUpBrowser() {
        browser.delegate = self
        browser.target = self
        browser.action = #selector(browserClicked)
        browser.doubleAction = #selector(browserDoubleClicked)
        browser.allowsMultipleSelection = true
        browser.hasHorizontalScroller = true
        browser.separatesColumns = true
        browser.columnResizingType = .userColumnResizing
        browser.minColumnWidth = 180
        browser.takesTitleFromPreviousColumn = false
        browser.isTitled = false
        browser.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        browser.menu = contextMenu()
        browser.setDraggingSourceOperationMask(.every, forLocal: false)
        browser.setDraggingSourceOperationMask([.move, .copy, .generic], forLocal: true)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // The icon grid wraps to the visible width; its height follows its content.
        let width = iconScroll.contentSize.width
        if icons.frame.width != width {
            icons.frame = NSRect(x: 0, y: 0, width: width, height: max(icons.frame.height, iconScroll.contentSize.height))
            icons.collectionViewLayout?.invalidateLayout()
        }
        updateNameOverlay()
    }

    // MARK: Loading

    func load(_ url: URL, options: FolderViewOptions) {
        directory = url
        isShowingResults = false
        // Where each item was deleted from, in the Trash only.
        outline.tableColumn(withIdentifier: .origin)?.isHidden =
            url.standardizedFileURL != TrashFolder.url.standardizedFileURL
        apply(options)
        watcher = DirectoryWatcher(url: url) { [weak self] in
            DispatchQueue.main.async { self?.reload() }
        }
        watcher?.start()
        reload()
        deselectAll()
        outline.scrollRowToVisible(0)
        icons.scroll(.zero)
    }

    /// Search results, shown in place of the folder's contents (which a reload brings back).
    func showResults(_ results: [FileItem]) {
        isShowingResults = true
        watcher = nil
        setItems(FileSorter.sorted(results, by: options.sortKey, ascending: options.ascending,
                                   foldersFirst: DisplaySettings.sortsFoldersFirst))
        message.isHidden = !results.isEmpty
        message.stringValue = UIL("No items match the search.")
        messageButton.isHidden = true
        restartButton.isHidden = messageButton.isHidden
        deselectAll()
    }

    /// A place that isn't a folder (Recents, Shared, this Mac): its items, shown as search results are.
    /// Nothing is made, pasted or dropped there. `emptyMessage` is empty while the items are on their way.
    func showPlace(_ items: [FileItem], options: FolderViewOptions, emptyMessage: String) {
        directory = nil
        apply(options)
        showResults(items)
        message.stringValue = emptyMessage
        message.isHidden = !items.isEmpty || emptyMessage.isEmpty
    }

    private func apply(_ options: FolderViewOptions) {
        self.options = options
        isApplyingOptions = true
        for column in Self.columns {
            outline.tableColumn(withIdentifier: column.id)?.width =
                options.columnWidths[column.id.rawValue].map { CGFloat($0) } ?? column.width
        }
        outline.sortDescriptors = [NSSortDescriptor(key: options.sortKey.rawValue, ascending: options.ascending)]
        isApplyingOptions = false
        showMode()
    }

    /// Reads the folder again, keeping the selection and the unfolded folders.
    func reload() {
        guard let directory, !isShowingResults else { return }
        if isDraggingOut { pendingReload = true; return }
        let selected = Set(selectedURLs)
        do {
            setItems(FileSorter.sorted(try DirectoryLoader.load(directory, showHidden: DisplaySettings.showsHiddenFiles),
                                       by: options.sortKey,
                                       ascending: options.ascending,
                                       foldersFirst: DisplaySettings.sortsFoldersFirst))
            message.isHidden = !items.isEmpty
            message.stringValue = UIL("This folder is empty.")
            messageButton.isHidden = true
            restartButton.isHidden = messageButton.isHidden
        } catch {
            setItems([])
            message.isHidden = false
            message.stringValue = Self.describe(error, folder: directory)
            messageButton.isHidden = !(TrashFolder.contains(directory) && TrashFolder.needsFullDiskAccess(error))
            restartButton.isHidden = messageButton.isHidden
        }
        restoreSelection(selected)
    }

    private func setItems(_ newItems: [FileItem]) {
        let unfolded = Set((0..<outline.numberOfRows).compactMap { row -> String? in
            guard let node = outline.item(atRow: row) as? FileNode, outline.isItemExpanded(node) else { return nil }
            return node.url.standardizedFileURL.path
        })
        items = newItems
        nodes = newItems.map { FileNode($0, sorting: options) }
        outline.reloadData()
        expand(nodes, keeping: unfolded)
        icons.reloadData()
        if let directory, !isShowingResults {
            browserRoot = FileNode(DirectoryLoader.item(at: directory), sorting: options)
        }
        browser.loadColumnZero()
    }

    private func expand(_ nodes: [FileNode], keeping unfolded: Set<String>) {
        for node in nodes where unfolded.contains(node.url.standardizedFileURL.path) {
            outline.expandItem(node)
            expand(node.children, keeping: unfolded)
        }
    }

    /// Draws the icons again (thumbnails turned on or off), keeping the selection.
    private func reloadIcons() {
        let selection = icons.selectionIndexPaths
        icons.reloadData()
        icons.selectionIndexPaths = selection
    }

    @objc private func openAccessSettings() {
        TrashFolder.openFullDiskAccessSettings()
    }

    @objc private func restart() {
        AppRelauncher.relaunch()
    }

    private static func describe(_ error: Error, folder: URL) -> String {
        if TrashFolder.contains(folder) { return TrashFolder.accessMessage(for: error) }
        let name = FileManager.default.displayName(atPath: folder.path)
        if (error as NSError).code == NSFileReadNoPermissionError {
            return String(format: UIL("macOS doesn't allow this app to see the contents of \u{201C}%@\u{201D}.\nGrant access in System Settings \u{203A} Privacy & Security \u{203A} Files and Folders."), name)
        }
        return String(format: UIL("Can't show \u{201C}%@\u{201D}: %@"), name, error.localizedDescription)
    }

    // MARK: View options

    func setMode(_ mode: ViewMode) {
        guard mode != options.mode else { return }
        let selected = Set(selectedURLs)
        options.mode = mode
        showMode()
        restoreSelection(selected)
        onOptionsChange?(options)
    }

    func sort(by key: SortKey) {
        options.sort(by: key)
        isApplyingOptions = true
        outline.sortDescriptors = [NSSortDescriptor(key: key.rawValue, ascending: options.ascending)]
        isApplyingOptions = false
        resort()
        onOptionsChange?(options)
    }

    private func resort() {
        if isShowingResults {
            showResults(items)
        } else {
            reload()
        }
    }

    private func showMode() {
        outlineScroll.isHidden = options.mode != .details
        iconScroll.isHidden = options.mode != .icons
        browser.isHidden = options.mode != .columns
        focus()
        updateNameOverlay()
    }

    private var activeView: NSView {
        switch options.mode {
        case .details: return outline
        case .icons: return icons
        case .columns: return browser
        }
    }

    // MARK: Selection

    /// The selected items, in every view.
    var selectedItems: [FileItem] {
        switch options.mode {
        case .details:
            return outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? FileNode)?.item }
        case .icons:
            return icons.selectionIndexPaths.map(\.item).sorted().filter { $0 < items.count }.map { items[$0] }
        case .columns:
            return browser.selectionIndexPaths.compactMap { (browser.item(at: $0) as? FileNode)?.item }
        }
    }

    var selectedURLs: [URL] { selectedItems.map(\.url) }

    /// Keyboard focus to the files, keeping the selection.
    func focus() {
        view.window?.makeFirstResponder(activeView)
    }

    func select(_ urls: [URL]) {
        restoreSelection(Set(urls.map(\.standardizedFileURL)))
        focus()
    }

    private func deselectAll() {
        outline.deselectAll(nil)
        icons.deselectAll(nil)
        selectionChanged()
    }

    private func restoreSelection(_ urls: Set<URL>) {
        let paths = Set(urls.map(\.standardizedFileURL.path))
        switch options.mode {
        case .details:
            let rows = (0..<outline.numberOfRows).filter {
                guard let node = outline.item(atRow: $0) as? FileNode else { return false }
                return paths.contains(node.url.standardizedFileURL.path)
            }
            outline.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
            if let first = rows.first { outline.scrollRowToVisible(first) }
        case .icons:
            let indexes = items.indices.filter { paths.contains(items[$0].url.standardizedFileURL.path) }
            let selection = Set(indexes.map { IndexPath(item: $0, section: 0) })
            icons.deselectAll(nil)
            icons.selectItems(at: selection, scrollPosition: selection.isEmpty ? [] : .nearestHorizontalEdge)
        case .columns:
            let rows = items.indices.filter { paths.contains(items[$0].url.standardizedFileURL.path) }
            if !rows.isEmpty { browser.selectRowIndexes(IndexSet(rows), inColumn: 0) }
        }
        selectionChanged()
    }

    private func selectionChanged() {
        quickLook.urls = selectedURLs
        updateNameOverlay()
        onSelectionChange?(selectedURLs)
    }

    private func updateNameOverlay() {
        guard options.mode == .icons, !isRenaming else { return }
        nameOverlay.update(in: icons) { [items] in
            $0.item < items.count ? DisplaySettings.name(of: items[$0.item]) : nil
        }
    }

    // MARK: Keys and commands

    private func handleKey(_ event: NSEvent) -> Bool {
        if handleFileKey(event) { return true }
        // Type-to-select for the icons; the list and the columns have their own.
        if options.mode == .icons, let text = FileKeys.typedText(event) {
            let typed = typeSelect.add(text)
            if let index = TypeSelect.match(typed, in: items.map(\.name)) { select([items[index].url]) }
            return true
        }
        return false
    }

    var commandSelection: [URL] { selectedURLs }

    var commandFolder: URL? {
        // Pasting while a single folder is selected in the columns goes into it, as in Finder.
        if options.mode == .columns, let only = selectedItems.first, selectedItems.count == 1, only.isFolder {
            return only.url
        }
        return isShowingResults ? nil : directory
    }

    func openCommandSelection() { openSelection(nil) }
    func goUpCommand() { onGoUp?() }
    func goBackCommand() { onGoBack?() }
    func goForwardCommand() { onGoForward?() }

    func selectAllCommand() {
        switch options.mode {
        case .details: outline.selectAll(nil)
        case .icons: icons.selectAll(nil)
        case .columns: browser.selectAll(nil)
        }
        selectionChanged()
    }

    func showChanges(selecting urls: [URL]) {
        reload()
        if !urls.isEmpty { select(urls) }
    }

    // The Edit menu, through the responder chain.
    @objc func copy(_ sender: Any?) { handle(.copy) }
    @objc func cut(_ sender: Any?) { handle(.cut) }
    @objc func paste(_ sender: Any?) { handle(.paste) }
    @objc func pasteMoving(_ sender: Any?) { handle(.pasteMoving) }
    @objc func undo(_ sender: Any?) { handle(.undo) }
    @objc func redo(_ sender: Any?) { handle(.redo) }
    @objc override func selectAll(_ sender: Any?) { selectAllCommand() }

    // MARK: Renaming in place

    /// F2, or Rename: a field over the item's name.
    func beginInlineRename() {
        guard let item = selectedItems.first, selectedItems.count == 1 else { return }
        let font = NSFont.systemFont(ofSize: options.mode == .icons ? 11 : NSFont.systemFontSize)
        let (host, rect): (NSView, NSRect)
        var hiding: [NSView] = []
        switch options.mode {
        case .details:
            let row = outline.row(forItem: outline.item(atRow: outline.selectedRow))
            guard row >= 0 else { return }
            outline.scrollRowToVisible(row)
            var cell = outline.frameOfCell(atColumn: 0, row: row)
            let indent = outline.level(forRow: row) * Int(outline.indentationPerLevel)
            cell.origin.x += CGFloat(indent) + Self.nameInset
            cell.size.width -= CGFloat(indent) + Self.nameInset
            if let name = (outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView)?.textField {
                hiding = [name]
                // From where the name starts (past the icon and the indentation) to the column's edge, the
                // row's whole height.
                let column = outline.frameOfCell(atColumn: 0, row: row)
                let start = name.convert(name.bounds, to: outline).minX - 3
                cell = NSRect(x: start, y: column.minY, width: column.maxX - start, height: column.height)
            }
            (host, rect) = (outline, cell)
        case .icons:
            guard let index = items.firstIndex(of: item) else { return }
            let indexPath = IndexPath(item: index, section: 0)
            icons.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
            guard let frame = icons.layoutAttributesForItem(at: indexPath)?.frame else { return }
            let top = frame.minY + IconItemView.nameTop(iconSide: IconSize.medium.iconSide)
            (host, rect) = (icons, NSRect(x: frame.minX, y: top, width: frame.width, height: 20))
            if let name = (icons.item(at: indexPath) as? IconItemView)?.nameView { hiding = [name] }
            // The full name shown under a selected icon would cover the field.
            isRenaming = true
            nameOverlay.update(in: icons, cells: [], iconSide: IconSize.medium.iconSide)
        case .columns:
            let column = browser.selectedColumn
            let row = browser.selectedRow(inColumn: column)
            guard column >= 0, row >= 0 else { return }
            (host, rect) = (browser, browser.frame(ofRow: row, inColumn: column).insetBy(dx: 18, dy: 0))
        }
        let showsExtension = DisplaySettings.showsFileExtensions
        InlineRenamer.begin(in: host, over: rect, name: item.displayName(showingExtension: showsExtension),
                            font: font, hiding: hiding, wraps: options.mode != .columns,
                            centered: options.mode == .icons) { [weak self] name in
            self?.isRenaming = false
            guard let self, let name,
                  let renamed = FileActions.rename(item.url, to: item.fullName(fromEdited: name,
                                                                              showingExtension: showsExtension))
            else {
                self?.updateNameOverlay()
                self?.focus()
                return
            }
            self.showChanges(selecting: [renamed])
        }
    }

    // MARK: Quick Look, Properties and the context menu

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        quickLook.urls = selectedURLs
        quickLook.take(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
    }

    /// Built when shown, for the items it is about: Explorer's commands, Finder's where Windows has none.
    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    /// In the details list a right-click on an unselected row acts on that row only, as in Finder.
    private var menuTargets: [FileItem] {
        let row = outline.clickedRow
        if options.mode == .details, row >= 0, !outline.isRowSelected(row),
           let node = outline.item(atRow: row) as? FileNode {
            return [node.item]
        }
        return selectedItems
    }

    @objc func changeIcon(_ sender: Any?) {
        IconPickerWindow.show(for: selectedURLs)
    }

    // File menu actions, reached through the responder chain.
    @objc func showProperties(_ sender: Any?) {
        PropertiesWindow.show(selectedURLs)
    }

    @objc func openSelection(_ sender: Any?) {
        selectedItems.forEach(open)
    }

    @objc func newFolder(_ sender: Any?) {
        handle(.newFolder)
    }

    @objc func renameSelection(_ sender: Any?) {
        beginInlineRename()
    }

    @objc func moveToTrash(_ sender: Any?) {
        handle(.moveToTrash)
    }

    @objc func toggleQuickLook(_ sender: Any?) {
        QuickLook.toggle()
    }

    // MARK: Opening

    @objc private func outlineDoubleClicked() {
        guard let node = outline.item(atRow: outline.clickedRow) as? FileNode else { return }
        open(node.item)
    }

    private func open(_ item: FileItem) {
        FileActions.open(item) { [weak self] in self?.onOpenFolder?($0) }
    }
}

extension FileListViewController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        validateFileCommand(item) ?? true
    }
}

// MARK: - Context menu

extension FileListViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let targets = menuTargets
        let urls = targets.map(\.url)
        func add(_ title: String, _ action: @escaping () -> Void, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
            item.target = MenuAction.shared
            item.representedObject = action
            item.isEnabled = enabled
            menu.addItem(item)
        }
        if let folder = commandFolder, TrashFolder.contains(folder) {
            trashMenu(in: menu, targets: targets, add: add)
            return
        }
        guard !targets.isEmpty else {
            // The background: what Explorer offers on an empty spot.
            add(UIL("New Folder")) { [weak self] in self?.handle(.newFolder) }
            add(UIL("Paste"), { [weak self] in self?.handle(.paste) }, enabled: commandFolder != nil && FileClipboard.canPaste)
            return
        }
        add(UIL("Open")) { [weak self] in targets.forEach { self?.open($0) } }
        if let first = targets.first, !first.isFolder {
            menu.addItem(openWithItem(for: first.url, all: urls))
        }
        menu.addItem(.separator())
        add(UIL("Cut")) { FileClipboard.cut(urls) }
        add(UIL("Copy")) { FileClipboard.copy(urls) }
        add(UIL("Copy as Path")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        }
        menu.addItem(.separator())
        add(UIL("Rename"), { [weak self] in self?.beginInlineRename() }, enabled: targets.count == 1)
        add(UIL("Move to Trash")) { [weak self] in self?.handle(.moveToTrash) }
        menu.addItem(.separator())
        if targets.count == 1, Archiver.isArchive(urls[0]) {
            add(UIL("Extract All")) { [weak self] in
                if let folder = FileActions.extract(urls[0]) { self?.showChanges(selecting: [folder]) }
            }
        }
        add(targets.count == 1
            ? String(format: UIL("Compress \u{201C}%@\u{201D}"), targets[0].name)
            : String(format: UIL("Compress %d Items"), targets.count)) { [weak self] in
            if let archive = FileActions.compress(urls) { self?.showChanges(selecting: [archive]) }
        }
        if targets.count == 1, targets[0].isFolder {
            let pinned = QuickAccessStore.shared.isPinned(urls[0])
            add(pinned ? UIL("Remove from Favorites") : UIL("Add to Favorites")) {
                if pinned { QuickAccessStore.shared.unpin(urls[0]) } else { QuickAccessStore.shared.pin(urls[0]) }
            }
        }
        menu.addItem(.separator())
        add(UIL("Quick Look")) { [weak self] in
            self?.quickLook.urls = urls
            if !QuickLook.isVisible { QuickLook.toggle() }
        }
        add(UIL("Change Icon")) { IconPickerWindow.show(for: urls) }
        add(UIL("Properties")) { PropertiesWindow.show(urls) }
    }

    /// In the Trash, Windows' Recycle Bin menu: restore or erase, nothing that would trash, rename or
    /// change what is already deleted. On an empty spot, Empty Trash.
    private func trashMenu(in menu: NSMenu, targets: [FileItem],
                           add: (String, @escaping () -> Void, Bool) -> Void) {
        let urls = targets.map(\.url)
        guard !targets.isEmpty else {
            add(UIL("Empty Trash"), { FileActions.emptyTrash() }, items.count > 0)
            return
        }
        add(UIL("Open"), { [weak self] in targets.forEach { self?.open($0) } }, true)
        add(UIL("Quick Look"), { [weak self] in
            self?.quickLook.urls = urls
            if !QuickLook.isVisible { QuickLook.toggle() }
        }, true)
        menu.addItem(.separator())
        add(UIL("Put Back"), { [weak self] in
            _ = FileActions.putBack(urls)
            self?.showChanges(selecting: [])
        }, true)
        add(UIL("Delete Permanently"), { [weak self] in
            FileActions.deletePermanently(urls)
            self?.showChanges(selecting: [])
        }, true)
        menu.addItem(.separator())
        add(UIL("Cut"), { FileClipboard.cut(urls) }, true)
        add(UIL("Copy"), { FileClipboard.copy(urls) }, true)
        menu.addItem(.separator())
        add(UIL("Properties"), { PropertiesWindow.show(urls) }, true)
    }

    /// Open With: the apps that can open the file, the default first, then Other… and Always Open With.
    private func openWithItem(for url: URL, all urls: [URL]) -> NSMenuItem {
        let submenu = NSMenu()
        let apps = FileActions.applications(toOpen: url)
        for (index, app) in apps.enumerated() {
            let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
            let item = NSMenuItem(title: index == 0 ? String(format: UIL("%@ (default)"), name) : name, action: #selector(MenuAction.run),
                                  keyEquivalent: "")
            item.image = NSWorkspace.shared.icon(forFile: app.path)
            item.image?.size = NSSize(width: 16, height: 16)
            item.target = MenuAction.shared
            item.representedObject = { FileActions.open(urls, with: app) } as () -> Void
            submenu.addItem(item)
            if index == 0 && apps.count > 1 { submenu.addItem(.separator()) }
        }
        submenu.addItem(.separator())
        let other = NSMenuItem(title: UIL("Other"), action: #selector(MenuAction.run), keyEquivalent: "")
        other.target = MenuAction.shared
        other.representedObject = { FileActions.chooseApplication(for: urls) } as () -> Void
        submenu.addItem(other)
        if apps.count > 1 {
            let always = NSMenuItem(title: UIL("Always Open With"), action: nil, keyEquivalent: "")
            let choices = NSMenu()
            for app in apps.dropFirst() {
                let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
                let item = NSMenuItem(title: name, action: #selector(MenuAction.run), keyEquivalent: "")
                item.target = MenuAction.shared
                item.representedObject = {
                    FileActions.makeDefault(app, for: url)
                    FileActions.open(urls, with: app)
                } as () -> Void
                choices.addItem(item)
            }
            always.submenu = choices
            submenu.addItem(always)
        }
        let item = NSMenuItem(title: UIL("Open With"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}

// MARK: - Details (an outline: folders unfold, as in Finder's list view)

extension FileListViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? FileNode)?.children.count ?? nodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? FileNode)?.children[index] ?? nodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isFolder ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let id = tableColumn?.identifier, let node = item as? FileNode else { return nil }
        let item = node.item
        let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView
            ?? TableCells.make(id, withIcon: id == .name, alignment: id == .size ? .right : .left,
                               withStatus: id == .name)
        cell.alphaValue = item.isHidden ? 0.5 : 1
        switch id {
        case .name:
            cell.textField?.stringValue = DisplaySettings.name(of: item)
            cell.imageView?.image = FileIcons.icon(for: item)
            (cell as? StatusCellView)?.setStatus(item.sync.flatMap { SyncBadge.symbol(for: $0, side: 13) },
                                                 tip: DisplaySettings.showsSyncBadges ? item.sync.map(SyncBadge.description) : nil)
            let expand = shouldExpand(outlineView.row(forItem: node))
            cell.textField?.maximumNumberOfLines = expand ? 0 : 1
            cell.textField?.lineBreakMode = expand ? .byWordWrapping : .byTruncatingMiddle
            cell.textField?.preferredMaxLayoutWidth = nameWidth
        case .modified:
            cell.textField?.stringValue = item.modified.map(dateFormatter.string(from:)) ?? ""
        case .size:
            cell.textField?.stringValue = item.isFolder ? ""
                : item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
        case .origin:
            let folder = TrashLedger.shared.originalLocation(of: item.url)?.deletingLastPathComponent()
            cell.textField?.stringValue = folder.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? ""
            cell.toolTip = folder?.path
        default:
            cell.textField?.stringValue = item.kind ?? ""
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        updateExpandedRows()
        selectionChanged()
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isApplyingOptions, let first = outlineView.sortDescriptors.first,
              let key = first.key.flatMap(SortKey.init(rawValue:)) else { return }
        options.sortKey = key
        options.ascending = first.ascending
        resort()
        onOptionsChange?(options)
    }

    func outlineViewColumnDidResize(_ notification: Notification) {
        guard let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn else { return }
        if column.identifier == .name { refresh(rows: expandedRows) }
        guard !isApplyingOptions else { return }
        options.columnWidths[column.identifier.rawValue] = Double(column.width)
        onOptionsChange?(options)
    }

    // Full name of the selection: the selected rows grow to show the whole name.

    private var nameWidth: CGFloat {
        (outline.tableColumn(withIdentifier: .name)?.width ?? 300) - Self.nameInset
    }

    private func shouldExpand(_ row: Int) -> Bool {
        row >= 0 && DisplaySettings.showsFullNameOfSelection && outline.isRowSelected(row)
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        let row = outlineView.row(forItem: item)
        guard shouldExpand(row), let node = item as? FileNode else { return Self.rowHeight }
        let bounds = (DisplaySettings.name(of: node.item) as NSString).boundingRect(
            with: NSSize(width: nameWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
        return max(Self.rowHeight, ceil(bounds.height) + 6)
    }

    private func updateExpandedRows() {
        let now = DisplaySettings.showsFullNameOfSelection ? outline.selectedRowIndexes : IndexSet()
        let changed = now.symmetricDifference(expandedRows)
        expandedRows = now
        refresh(rows: changed.union(now))
    }

    private func refresh(rows: IndexSet) {
        let rows = rows.filteredIndexSet { $0 < outline.numberOfRows }
        guard !rows.isEmpty else { return }
        outline.noteHeightOfRows(withIndexesChanged: rows)
        outline.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
    }
}

// MARK: - Icons

extension FileListViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: IconItemView.reuseID, for: indexPath)
        if let icon = cell as? IconItemView {
            icon.configure(with: items[indexPath.item])
            icon.setGhost(draggingURLs.contains(items[indexPath.item].url))
        }
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        selectionChanged()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        selectionChanged()
    }
}

// MARK: - Columns (Finder's column view)

extension FileListViewController: NSBrowserDelegate {
    func rootItem(for browser: NSBrowser) -> Any? { browserRoot }

    func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? FileNode)?.children.count ?? 0
    }

    /// A reload during a drag selection can leave the browser asking for a row the folder no longer
    /// has; it gets the parent until it reads the folder again.
    func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any {
        let parent = (item as? FileNode) ?? browserRoot
        let children = parent?.children ?? []
        return children.indices.contains(index) ? children[index] : parent as Any
    }

    func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool {
        !((item as? FileNode)?.isFolder ?? false)
    }

    /// The icon and the name, as one line of text.
    func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any? {
        guard let node = item as? FileNode else { return nil }
        let isDragged = draggingURLs.contains(node.url)
        let icon = NSTextAttachment()
        icon.image = isDragged ? DragGhost.faded(FileIcons.icon(for: node.item), alpha: DragGhost.alpha)
                               : FileIcons.icon(for: node.item)
        icon.bounds = NSRect(x: 0, y: -4, width: 16, height: 16)
        let line = NSMutableAttributedString(attachment: icon)
        var color = node.item.isHidden ? NSColor.secondaryLabelColor : NSColor.labelColor
        if isDragged { color = color.withAlphaComponent(DragGhost.alpha) }
        line.append(NSAttributedString(string: "  " + DisplaySettings.name(of: node.item),
                                       attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                                                    .foregroundColor: color]))
        // The cloud state after the name, as in the list view.
        if let state = node.item.sync, let symbol = SyncBadge.symbol(for: state, side: 12) {
            let status = NSTextAttachment()
            status.image = symbol
            status.bounds = NSRect(x: 0, y: -2, width: 12, height: 12)
            line.append(NSAttributedString(string: "  "))
            line.append(NSAttributedString(attachment: status))
        }
        return line
    }

    @available(macOS 27, *)
    func browser(_ browser: NSBrowser, pasteboardWriterForRow row: Int, column: Int) -> NSPasteboardWriting? {
        (browser.item(atRow: row, inColumn: column) as? FileNode)?.url as NSURL?
    }

    @available(macOS 27, *)
    func browser(_ browser: NSBrowser, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
                 forRowsWith rowIndexes: IndexSet, column: Int) {
        isDraggingOut = true
        let nodes = rowIndexes.compactMap { browser.item(atRow: $0, inColumn: column) as? FileNode }
        draggingURLs = Set(nodes.map(\.url))
        browserDrag = (rowIndexes, column)
        let icons = Dictionary(nodes.map { ($0.url.standardizedFileURL, FileIcons.icon(for: $0.item)) },
                               uniquingKeysWith: { first, _ in first })
        DragGhost.showIcons(in: session, at: screenPoint) { icons[$0.standardizedFileURL] }
        browser.reloadData(forRowIndexes: rowIndexes, inColumn: column)
    }

    @available(macOS 27, *)
    func browser(_ browser: NSBrowser, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint,
                 operation: NSDragOperation) {
        isDraggingOut = false
        draggingURLs = []
        if let drag = browserDrag, drag.column <= browser.lastColumn {
            browser.reloadData(forRowIndexes: drag.rows, inColumn: drag.column)
        }
        browserDrag = nil
        if pendingReload { pendingReload = false; reload() }
    }

    @objc private func browserClicked() {
        selectionChanged()
    }

    @objc private func browserDoubleClicked() {
        guard let node = browser.selectionIndexPaths.last.flatMap({ browser.item(at: $0) }) as? FileNode else { return }
        // Folders unfold as a new column; files open.
        if !node.isFolder { open(node.item) }
    }
}

// MARK: - Drag and drop

/// Items drag out to other apps, windows or the desktop. Drops land in the folder under the pointer
/// (a folder or an alias to one), or otherwise in the folder this view shows.
extension FileListViewController {
    private func dropFolder(for item: FileItem?, info: NSDraggingInfo) -> URL? {
        guard let item, let folder = FileDrop.folderTarget(of: item) else { return nil }
        // Dropping items onto one of themselves means nothing.
        return FileDrop.fileURLs(in: info).contains(item.url) ? nil : folder
    }

    private func accept(_ info: NSDraggingInfo, into folder: URL) -> Bool {
        let isHere = folder.standardizedFileURL.path == directory?.standardizedFileURL.path
        let moved = FileDrop.perform(info, into: folder) { [weak self] received in
            // Files made at the drop (a picture from a browser, an item from Clipboard).
            self?.reload()
            if isHere { self?.select(received) }
        }
        reload()
        if isHere { select(moved) }
        return !moved.isEmpty || !FileDrop.promises(in: info).isEmpty
    }

    // Details list

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        (item as? FileNode)?.url as NSURL?
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                     willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        isDraggingOut = true
        let nodes = draggedItems.compactMap { $0 as? FileNode }
        draggingURLs = Set(nodes.map(\.url))
        let icons = Dictionary(nodes.map { ($0.url.standardizedFileURL, FileIcons.icon(for: $0.item)) },
                               uniquingKeysWith: { first, _ in first })
        DragGhost.showIcons(in: session, at: screenPoint) { icons[$0.standardizedFileURL] }
        for node in nodes {
            let row = outlineView.row(forItem: node)
            if row >= 0 { outlineView.rowView(atRow: row, makeIfNecessary: false)?.alphaValue = DragGhost.alpha }
        }
    }

    /// Rows scrolled into view during a drag fade too; recycled ones come back.
    func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
        let url = (outlineView.item(atRow: row) as? FileNode)?.url
        rowView.alphaValue = url.map(draggingURLs.contains) == true ? DragGhost.alpha : 1
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                     endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDraggingOut = false
        draggingURLs = []
        outlineView.enumerateAvailableRowViews { rowView, _ in rowView.alphaValue = 1 }
        if pendingReload { pendingReload = false; reload() }
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        if index == NSOutlineViewDropOnItemIndex, let folder = dropFolder(for: (item as? FileNode)?.item, info: info) {
            return FileDrop.dragOperation(for: info, into: folder)
        }
        guard let directory, !isShowingResults else { return [] }
        // Anywhere else: the whole list, i.e. this folder.
        outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return FileDrop.dragOperation(for: info, into: directory)
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?,
                     childIndex index: Int) -> Bool {
        guard let folder = dropFolder(for: (item as? FileNode)?.item, info: info) ?? directory else { return false }
        return accept(info, into: folder)
    }

    // Icons

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>,
                        with event: NSEvent) -> Bool {
        true
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        isDraggingOut = true
        draggingURLs = Set(indexPaths.filter { $0.item < items.count }.map { items[$0.item].url })
        DragGhost.fadeImages(of: session)
        for indexPath in indexPaths {
            (collectionView.item(at: indexPath) as? IconItemView)?.setGhost(true)
        }
    }

    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem,
                        forRepresentedObjectAt indexPath: IndexPath) {
        guard indexPath.item < items.count else { return }
        (item as? IconItemView)?.setGhost(draggingURLs.contains(items[indexPath.item].url))
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
        isDraggingOut = false
        draggingURLs = []
        for item in collectionView.visibleItems() {
            (item as? IconItemView)?.setGhost(false)
        }
        if pendingReload { pendingReload = false; reload() }
    }

    func collectionView(_ collectionView: NSCollectionView,
                        pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        indexPath.item < items.count ? items[indexPath.item].url as NSURL : nil
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop info: NSDraggingInfo,
                        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        let index = proposedIndexPath.pointee.item
        if dropOperation.pointee == .on, index < items.count, let folder = dropFolder(for: items[index], info: info) {
            return FileDrop.dragOperation(for: info, into: folder)
        }
        guard let directory, !isShowingResults else { return [] }
        dropOperation.pointee = .before
        return FileDrop.dragOperation(for: info, into: directory)
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop info: NSDraggingInfo,
                        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        let item = indexPath.item < items.count ? items[indexPath.item] : nil
        let folder = dropOperation == .on ? dropFolder(for: item, info: info) : nil
        guard let target = folder ?? directory else { return false }
        return accept(info, into: target)
    }
}
