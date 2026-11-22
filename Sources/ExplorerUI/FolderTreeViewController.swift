import AppKit
import ExplorerCore
import ExplorerSettings
import SuiteFilesCore
import SuiteFilesUI

/// One row of the sidebar: a heading with its rows, a folder, a place that isn't a folder (Recents,
/// Shared, this Mac), or AirDrop.
final class SidebarRow {
    enum Kind { case heading, folder, place, airDrop }

    let kind: Kind
    let url: URL
    let name: String
    let glyph: SidebarGlyph
    /// Stored in iCloud (Desktop and Documents, synced): a cloud after the name, as in Finder.
    let isInICloud: Bool
    let children: [SidebarRow]
    /// A pinned folder, which can be moved, removed or pinned before.
    var isFavorite = false
    /// A disk: it doesn't drag out.
    var isVolume = false
    /// A disk that can be ejected: an eject button after its name, as in Finder.
    var canEject = false

    init(heading name: String, children: [SidebarRow]) {
        kind = .heading
        url = URL(fileURLWithPath: "/")
        self.name = name
        glyph = .symbol("")
        isInICloud = false
        self.children = children
    }

    init(_ kind: Kind, url: URL, name: String, glyph: SidebarGlyph, isInICloud: Bool = false) {
        self.kind = kind
        self.url = url
        self.name = name
        self.glyph = glyph
        self.isInICloud = isInICloud
        children = []
    }

    var isHeading: Bool { kind == .heading }
    /// What the row stands for, compared with what a pane shows.
    var address: String { url.isFileURL ? url.standardizedFileURL.path : url.absoluteString }
}

/// The sidebar of Explorer windows, as Finder's: Recents and Shared, the Favorites (the pinned folders,
/// Windows' Quick access), then the Locations: iCloud Drive, cloud storage, this Mac, its disks, AirDrop
/// and the Trash, as chosen in the settings. Monochrome icons in the accent colour, grey while the window
/// isn't in front. Files dropped on a folder go into it, on the Trash to the Trash, on AirDrop to nearby
/// devices; folders dropped among the Favorites are pinned there.
final class FolderTreeViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate,
    NSMenuDelegate {
    var onSelectFolder: ((URL) -> Void)?
    /// AirDrop chosen, or files dropped on it: send these, or the selection when there are none.
    var onAirDrop: (([URL]) -> Void)?
    /// The second folder's sidebar, on the right while Side by Side: its right-click styles are its own.
    var isRightSide = false

    private let outline = NSOutlineView()
    private var roots: [SidebarRow] = []
    private var favorites = SidebarRow(heading: UIL("Favorites"), children: [])
    private var places = WindowSettings.sidebarPlaces
    private var isRevealing = false
    /// What the pane shows, selected again after AirDrop (an action, not a place).
    private var shown: URL?
    /// The folders being dragged out, shown faded where they are.
    private var draggingPaths: Set<String> = []
    private let hoverLabel = HoverLabel()
    private var windowObservers: [NSObjectProtocol] = []
    private var volumeObservers: [NSObjectProtocol] = []
    private static let cellID = NSUserInterfaceItemIdentifier("SidebarCell")
    private static let iconCellID = NSUserInterfaceItemIdentifier("SidebarIconCell")

    /// Icons only: a narrow strip with the places, their names beside them under the mouse.
    var iconsOnly = false {
        didSet {
            guard iconsOnly != oldValue else { return }
            if !iconsOnly { hoverLabel.hide() }
            reloadOutline()
        }
    }

    /// The strip's width, icons only; the toolbar then runs the whole width of the window above it.
    static let iconsOnlyWidth: CGFloat = 48

    override func loadView() {
        let column = NSTableColumn(identifier: Self.cellID)
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.indentationPerLevel = 0
        outline.dataSource = self
        outline.delegate = self
        outline.registerForDraggedTypes([.fileURL])
        outline.setDraggingSourceOperationMask([.copy, .link], forLocal: false)
        outline.setDraggingSourceOperationMask([.copy, .link], forLocal: true)
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        view = scroll
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        outline.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited,
                                                                       .activeInActiveApp, .inVisibleRect],
                                               owner: self))
        rebuild()
        let center = NotificationCenter.default
        center.addObserver(forName: QuickAccessStore.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        }
        center.addObserver(forName: WindowSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.places != WindowSettings.sidebarPlaces else { return }
            self.places = WindowSettings.sidebarPlaces
            self.rebuild()
        }
        // Disks come and go, live.
        volumeObservers = VolumeMonitor.observe { [weak self] _, _ in self?.rebuild() }
        center.addObserver(forName: NSView.boundsDidChangeNotification,
                           object: (view as? NSScrollView)?.contentView, queue: .main) { [weak self] _ in
            self?.hoverLabel.hide()
        }
        (view as? NSScrollView)?.contentView.postsBoundsChangedNotifications = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = view.window?.observeActivity { [weak self] in self?.updateTint() } ?? []
        updateTint()
    }

    deinit {
        VolumeMonitor.stopObserving(volumeObservers)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        hoverLabel.hide()
    }

    // MARK: Rows

    private func rebuild() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let iCloudDrive = SidebarPlace.iCloudDrive.url(home: home)
        let hasICloudDrive = iCloudDrive.map { fm.fileExists(atPath: $0.path) } ?? false

        var top: [SidebarRow] = []
        var locations: [SidebarRow] = []
        for place in places.ordered() {
            switch place {
            case .recents:
                top.append(Self.row(for: .recents))
            case .shared where hasICloudDrive:
                top.append(Self.row(for: .shared))
            case .iCloudDrive where hasICloudDrive:
                locations.append(SidebarRow(.folder, url: iCloudDrive!, name: UIL("iCloud Drive"),
                                            glyph: .symbol("icloud")))
            case .cloudStorage:
                locations += CloudStorage.folders(in: SidebarPlace.cloudStorageFolder(home: home)).map {
                    SidebarRow(.folder, url: $0, name: CloudStorage.displayName(ofFolderNamed: $0.lastPathComponent),
                               glyph: .symbol("folder"))
                }
            case .computer:
                locations.append(Self.row(for: .computer))
            case .disks:
                locations += Self.volumes()
            case .airDrop:
                locations.append(SidebarRow(.airDrop, url: URL(string: "explorer:airdrop")!, name: "AirDrop",
                                            glyph: .finder("SidebarAirDrop", or: "dot.radiowaves.left.and.right")))
            case .trash:
                locations.append(SidebarRow(.folder, url: TrashFolder.url, name: UIL("Trash"), glyph: .symbol("trash")))
            case .favorites, .shared, .iCloudDrive:
                continue
            }
        }
        roots = top
        if places.contains(.favorites) {
            let pinned = QuickAccessStore.shared.folders.filter { fm.fileExists(atPath: $0.path) }.map { url in
                let row = SidebarRow(.folder, url: url, name: fm.displayName(atPath: url.path),
                                     glyph: Self.glyph(forFolder: url, home: home),
                                     isInICloud: (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?
                                         .isUbiquitousItem == true)
                row.isFavorite = true
                return row
            }
            favorites = SidebarRow(heading: UIL("Favorites"), children: pinned)
            roots.append(favorites)
        }
        if !locations.isEmpty { roots.append(SidebarRow(heading: UIL("Locations"), children: locations)) }
        reloadOutline()
    }

    /// Finder's glyphs for the usual folders; a plain folder for the rest.
    private static func glyph(forFolder url: URL, home: URL) -> SidebarGlyph {
        let folder = SidebarGlyph.symbol("folder")
        let path = url.standardizedFileURL.path
        if path == "/Applications" { return .finder("SidebarApplicationsFolder", or: "a.square") }
        if path == home.standardizedFileURL.path { return .symbol("house") }
        guard url.deletingLastPathComponent().standardizedFileURL.path == home.standardizedFileURL.path else {
            return folder
        }
        switch url.lastPathComponent {
        case "Desktop": return .symbol("menubar.dock.rectangle")
        case "Documents": return .symbol("doc")
        case "Downloads": return .symbol("arrow.down.circle")
        case "Pictures": return .symbol("photo")
        case "Music": return .symbol("music.note")
        case "Movies": return .symbol("film")
        default: return folder
        }
    }

    private static func volumes() -> [SidebarRow] {
        VolumeInfo.mounted().map { volume in
            let glyph: SidebarGlyph
            switch volume.kind {
            case .network: glyph = .symbol("externaldrive.connected.to.line.below")
            case .internalDisk: glyph = .symbol("internaldrive")
            case .externalDisk: glyph = .symbol("externaldrive")
            }
            let row = SidebarRow(.folder, url: volume.url, name: volume.name, glyph: glyph)
            row.isVolume = true
            row.canEject = volume.canEject
            return row
        }
    }

    private static func row(for place: VirtualPlace) -> SidebarRow {
        SidebarRow(.place, url: place.url, name: place.title, glyph: place.glyph)
    }

    // MARK: Showing the pane's place

    /// Icons only, the strip lies under a toolbar that runs the whole width: its rows start below the
    /// toolbar (and the tab bar), which the split view doesn't do by itself for a strip that isn't full height.
    var startsBelowToolbar = false {
        didSet {
            guard startsBelowToolbar != oldValue, let scroll = view as? NSScrollView else { return }
            scroll.automaticallyAdjustsContentInsets = !startsBelowToolbar
            if !startsBelowToolbar { scroll.contentInsets = NSEdgeInsets() }
            view.needsLayout = true
            scrollToTop()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard startsBelowToolbar, let scroll = view as? NSScrollView, let window = view.window,
              let content = window.contentView else { return }
        let top = content.bounds.height - window.contentLayoutRect.maxY
        if scroll.contentInsets.top != top {
            scroll.contentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
            scrollToTop()
        }
    }

    /// Back to the first row, once the sidebar's top edge has moved (under the toolbar or beside it).
    func scrollToTop() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.layoutSubtreeIfNeeded()
            if self.outline.numberOfRows > 0 { self.outline.scrollRowToVisible(0) }
        }
    }

    private func reloadOutline() {
        outline.reloadData()
        roots.filter(\.isHeading).forEach { outline.expandItem($0) }
        if let shown { reveal(shown) }
    }

    /// Selects the row standing for what the pane shows, as Finder does; nothing when it has none.
    func reveal(_ url: URL) {
        shown = url
        let address = url.isFileURL ? url.standardizedFileURL.path : url.absoluteString
        let rows = roots.flatMap { $0.isHeading ? $0.children : [$0] }
        isRevealing = true
        defer { isRevealing = false }
        guard let row = rows.first(where: { $0.address == address }), outline.row(forItem: row) >= 0 else {
            outline.deselectAll(nil)
            return
        }
        let index = outline.row(forItem: row)
        outline.selectRowIndexes([index], byExtendingSelection: false)
        outline.scrollRowToVisible(index)
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? SidebarRow)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? SidebarRow)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? SidebarRow)?.isHeading ?? false
    }

    // MARK: Delegate

    /// Icons only, a heading is just a line between groups: not a group row (no Show/Hide under the
    /// mouse), and it never folds.
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        !iconsOnly && ((item as? SidebarRow)?.isHeading ?? false)
    }

    func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
        !iconsOnly
    }

    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        !((item as? SidebarRow)?.isHeading ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let row = item as? SidebarRow else { return nil }
        if row.isHeading {
            if iconsOnly {
                let line = NSBox()
                line.boxType = .separator
                return line
            }
            let header = NSTableCellView()
            let text = NSTextField(labelWithString: row.name)
            text.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            text.textColor = .secondaryLabelColor
            text.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(text)
            header.textField = text
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 2),
                text.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            ])
            return header
        }
        let identifier = iconsOnly ? Self.iconCellID : Self.cellID
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? SidebarCell
            ?? SidebarCell(identifier: identifier, iconOnly: iconsOnly)
        cell.show(row, active: isActive)
        let volume = row.url
        cell.onEject = row.canEject ? { FileActions.eject([volume]) } : nil
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard iconsOnly else { return outlineView.rowHeight }
        return (item as? SidebarRow)?.isHeading == true ? 9 : 30
    }

    /// The selected window.
    private var isActive: Bool { view.window?.showsAsActive == true }

    private func updateTint() {
        let active = isActive
        outline.enumerateAvailableRowViews { rowView, _ in
            (rowView.view(atColumn: 0) as? SidebarCell)?.setActive(active)
        }
    }

    // MARK: Names under the mouse, icons only

    override func mouseMoved(with event: NSEvent) {
        guard iconsOnly, let window = view.window else { return hoverLabel.hide() }
        let point = outline.convert(event.locationInWindow, from: nil)
        let index = outline.row(at: point)
        guard index >= 0, let row = outline.item(atRow: index) as? SidebarRow, !row.isHeading else {
            return hoverLabel.hide()
        }
        // Beside the strip, level with the row.
        let rowRect = outline.convert(outline.rect(ofRow: index), to: nil)
        let edge = view.convert(view.bounds, to: nil)
        let anchor = window.convertPoint(toScreen: NSPoint(x: edge.maxX + 6, y: rowRect.midY))
        hoverLabel.show(row.name, leftCenter: anchor, over: window)
    }

    override func mouseExited(with event: NSEvent) {
        hoverLabel.hide()
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isRevealing, let row = outline.item(atRow: outline.selectedRow) as? SidebarRow,
              !row.isHeading else { return }
        if row.kind == .airDrop {
            // An action, not a place: the pane's place stays selected.
            if let shown { reveal(shown) }
            onAirDrop?([])
            return
        }
        onSelectFolder?(row.url)
    }

    // MARK: Drops

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        let urls = FileDrop.fileURLs(in: info)
        guard !urls.isEmpty, let row = item as? SidebarRow else { return [] }
        // Among the Favorites, or on their heading: pin the dropped folders there.
        if row === favorites {
            return urls.allSatisfy(isFolder) ? .link : []
        }
        guard index == NSOutlineViewDropOnItemIndex else { return [] }
        switch row.kind {
        case .heading, .place:
            return []
        case .airDrop:
            return .copy
        case .folder where row.url.standardizedFileURL == TrashFolder.url.standardizedFileURL:
            return info.draggingSourceOperationMask.isDisjoint(with: [.delete, .move, .generic]) ? [] : .delete
        case .folder:
            return FileDrop.dragOperation(for: info, into: row.url)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?,
                     childIndex index: Int) -> Bool {
        let urls = FileDrop.fileURLs(in: info)
        guard let row = item as? SidebarRow else { return false }
        if row === favorites {
            for (offset, url) in urls.enumerated() {
                QuickAccessStore.shared.pin(url, at: index == NSOutlineViewDropOnItemIndex ? nil : index + offset)
            }
            return true
        }
        switch row.kind {
        case .airDrop:
            onAirDrop?(urls)
            return true
        case .folder where row.url.standardizedFileURL == TrashFolder.url.standardizedFileURL:
            FileActions.moveToTrash(urls)
            return true
        case .folder:
            return !FileDrop.perform(info, into: row.url).isEmpty
        case .heading, .place:
            return false
        }
    }

    private func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    // MARK: Drags out

    /// Sidebar folders drag out as copies (or aliases), never moved: they include Documents and the like.
    /// Among the Favorites, dragging one moves it there. Headings, places, AirDrop, the Trash and disks
    /// don't drag.
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let row = item as? SidebarRow, row.kind == .folder, !row.isVolume,
              row.url.standardizedFileURL != TrashFolder.url.standardizedFileURL else { return nil }
        return row.url as NSURL
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                     willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        let rows = draggedItems.compactMap { $0 as? SidebarRow }
        draggingPaths = Set(rows.map(\.address))
        let icons = Dictionary(rows.map { ($0.address, NSWorkspace.shared.icon(forFile: $0.url.path)) },
                               uniquingKeysWith: { first, _ in first })
        DragGhost.showIcons(in: session, at: screenPoint) { icons[$0.standardizedFileURL.path] }
        for row in rows {
            let index = outlineView.row(forItem: row)
            if index >= 0 { outlineView.rowView(atRow: index, makeIfNecessary: false)?.alphaValue = DragGhost.alpha }
        }
    }

    /// Rows scrolled into view during a drag fade too; recycled ones come back.
    func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
        let address = (outlineView.item(atRow: row) as? SidebarRow)?.address
        rowView.alphaValue = address.map(draggingPaths.contains) == true ? DragGhost.alpha : 1
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                     endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggingPaths = []
        outlineView.enumerateAvailableRowViews { rowView, _ in rowView.alphaValue = 1 }
    }

    // MARK: Right-click: a favorite, how the sidebar shows, and its settings

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        hoverLabel.hide()
        func add(_ title: String, state: Bool = false, _ run: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
            item.target = MenuAction.shared
            item.representedObject = run
            item.state = state ? .on : .off
            menu.addItem(item)
        }
        if let row = outline.item(atRow: outline.clickedRow) as? SidebarRow, row.isFavorite {
            let url = row.url
            add(UIL("Remove from Favorites")) { QuickAccessStore.shared.unpin(url) }
            menu.addItem(.separator())
        }
        if let row = outline.item(atRow: outline.clickedRow) as? SidebarRow, row.canEject {
            let url = row.url
            add(String(format: UIL("Eject \u{201C}%@\u{201D}"), row.name)) { FileActions.eject([url]) }
            menu.addItem(.separator())
        }
        let current = isRightSide ? WindowSettings.rightSidebar : WindowSettings.leftSidebar
        let right = isRightSide
        func choose(_ style: WindowSettings.SidebarStyle) {
            if right { WindowSettings.rightSidebar = style } else { WindowSettings.leftSidebar = style }
        }
        add(UIL("Icons and Names"), state: current == .iconsAndNames) { choose(.iconsAndNames) }
        add(UIL("Icons Only"), state: current == .icons) { choose(.icons) }
        menu.addItem(.separator())
        add(UIL("Settings")) { WindowSettings.openSettings?("Explorer") }
    }
}

/// A sidebar row as Finder draws it: a monochrome glyph in the accent colour (grey while the window isn't
/// in front), the name, a cloud for folders kept in iCloud and an eject button for disks that can be
/// ejected. Icons only, the glyph alone (disks are ejected from the right-click menu).
private final class SidebarCell: NSTableCellView {
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let cloud = NSImageView()
    private let ejectButton = NSButton()
    /// Set for a disk that can be ejected; the button shows only then.
    var onEject: (() -> Void)? {
        didSet { ejectButton.isHidden = onEject == nil }
    }

    init(identifier: NSUserInterfaceItemIdentifier, iconOnly: Bool) {
        super.init(frame: .zero)
        self.identifier = identifier
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        imageView = icon
        if iconOnly {
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 22),
                icon.heightAnchor.constraint(equalToConstant: 22),
            ])
            return
        }
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(name)
        textField = name
        cloud.image = NSImage(systemSymbolName: "icloud", accessibilityDescription: "iCloud")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        cloud.contentTintColor = .tertiaryLabelColor
        cloud.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cloud)
        ejectButton.image = NSImage(systemSymbolName: "eject.fill", accessibilityDescription: UIL("Eject"))?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        ejectButton.isBordered = false
        ejectButton.contentTintColor = .secondaryLabelColor
        ejectButton.toolTip = UIL("Eject")
        ejectButton.target = self
        ejectButton.action = #selector(ejectClicked)
        ejectButton.isHidden = true
        ejectButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ejectButton)
        NSLayoutConstraint.activate([
            ejectButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            ejectButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            ejectButton.widthAnchor.constraint(equalToConstant: 16),
            ejectButton.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 4),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 18),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            cloud.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 4),
            cloud.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            cloud.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func ejectClicked() {
        onEject?()
    }

    func show(_ row: SidebarRow, active: Bool) {
        icon.image = row.glyph.image
        name.stringValue = row.name
        cloud.isHidden = !row.isInICloud
        setActive(active)
    }

    func setActive(_ active: Bool) {
        icon.contentTintColor = active ? .controlAccentColor : .secondaryLabelColor
    }
}
