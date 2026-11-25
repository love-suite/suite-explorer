import AppKit
import ExplorerCore
import ExplorerSettings
import SuiteFilesCore

/// A breadcrumb that turns into an editable path field, like Explorer's address bar.
final class AddressBar: NSView, NSTextFieldDelegate {
    var url: URL? {
        didSet {
            // A place that isn't a folder (Recents) shows as its name alone; typing goes to a folder.
            if let url, let place = VirtualPlace(url: url) {
                let item = NSPathControlItem()
                item.title = place.title
                item.image = place.glyph.image
                pathControl.pathItems = [item]
                field.stringValue = ""
                return
            }
            pathControl.url = url
            field.stringValue = url?.path ?? ""
        }
    }
    /// Outlined in the accent colour: the active folder of two, Side by Side.
    var isHighlighted = false {
        didSet { needsDisplay = true }
    }
    /// Called when a breadcrumb segment is clicked.
    var onNavigate: ((URL) -> Void)?
    /// Called with the typed text; returns false to keep editing (path not found).
    var onSubmit: ((String) -> Bool)?

    private let pathControl = NSPathControl()
    private let field = NSTextField()
    private let dropdown = CompletionDropdown()
    private var isCompletingInline = false
    private var deletingText = false
    /// Text in the field before the user started arrowing through the dropdown.
    private var typedBeforeArrow: String?

    init() {
        super.init(frame: .zero)
        pathControl.pathStyle = .standard
        pathControl.focusRingType = .none
        pathControl.target = self
        pathControl.action = #selector(pathClicked)

        field.delegate = self
        field.isHidden = true
        field.placeholderString = UIL("Type or paste a path")
        field.lineBreakMode = .byTruncatingHead

        for view in [pathControl, field] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                view.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        // A long path shortens its middle folders instead of widening the window.
        // It also takes all the room it is given: the path doesn't hold it to its own width.
        for view in [self, pathControl, field] {
            view.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
            view.setContentHuggingPriority(.init(1), for: .horizontal)
        }

        dropdown.onSelect = { [weak self] path in
            guard let self else { return }
            typedBeforeArrow = nil
            dropdown.hide()
            if onSubmit?(path) ?? false {
                window?.makeFirstResponder(nil)
            } else {
                // Shouldn't happen from the dropdown; complete the field instead.
                field.stringValue = path + "/"
                field.currentEditor()?.moveToEndOfDocument(nil)
                updateDropdown(typedPath: path + "/")
            }
        }

        dropdown.onHighlight = { [weak self] path in
            guard let self else { return }
            isCompletingInline = true
            guard let editor = field.currentEditor() as? NSTextView else { return }
            if let path {
                if typedBeforeArrow == nil { typedBeforeArrow = editor.string }
                editor.string = path
            } else {
                editor.string = typedBeforeArrow ?? ""
                typedBeforeArrow = nil
            }
            editor.moveToEndOfDocument(nil)
            isCompletingInline = false
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// A field across the whole bar, as in Explorer, so clicking anywhere past the path edits it.
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.quaternaryLabelColor.setFill()
        shape.fill()
        let outlined = isActive && (isHighlighted || !field.isHidden)
        (outlined ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        shape.lineWidth = outlined ? 2 : 1
        shape.stroke()
    }

    // MARK: In front or not

    /// The selected window; otherwise the path greys, as Finder's does.
    private var isActive: Bool { window?.showsAsActive == true }
    private var activityObservers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        activityObservers.forEach(NotificationCenter.default.removeObserver)
        activityObservers = window?.observeActivity { [weak self] in self?.showActivity() } ?? []
        showActivity()
    }

    private func showActivity() {
        pathControl.alphaValue = isActive ? 1 : 0.5
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        beginEditing()
    }

    func beginEditing() {
        field.stringValue = url?.isFileURL == true ? url!.path : ""
        pathControl.isHidden = true
        field.isHidden = false
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        needsDisplay = true
    }

    private func endEditing() {
        dropdown.hide()
        field.isHidden = true
        pathControl.isHidden = false
        needsDisplay = true
    }

    /// Clicking a parent segment goes there; clicking the current folder starts editing.
    @objc private func pathClicked() {
        guard let clicked = pathControl.clickedPathItem?.url,
              clicked.standardizedFileURL.path != url?.standardizedFileURL.path else {
            beginEditing()
            return
        }
        onNavigate?(clicked)
    }

    // MARK: NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            typedBeforeArrow = nil
            dropdown.hide()
            if onSubmit?(textView.string) ?? false {
                window?.makeFirstResponder(nil)
            } else {
                NSSound.beep()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if dropdown.isVisible {
                if let saved = typedBeforeArrow {
                    textView.string = saved
                    textView.moveToEndOfDocument(nil)
                    typedBeforeArrow = nil
                }
                dropdown.hide()
            } else {
                window?.makeFirstResponder(nil)
            }
            return true
        case #selector(NSResponder.insertTab(_:)):
            typedBeforeArrow = nil
            acceptInlineCompletion(editor: textView)
            return true
        case #selector(NSResponder.moveDown(_:)):
            if typedBeforeArrow == nil { typedBeforeArrow = textView.string }
            if !dropdown.isVisible { updateDropdown(typedPath: typedPath(in: textView)) }
            dropdown.selectNext()
            return true
        case #selector(NSResponder.moveUp(_:)):
            if typedBeforeArrow == nil { typedBeforeArrow = textView.string }
            dropdown.selectPrevious()
            return true
        case #selector(NSResponder.deleteBackward(_:)),
             #selector(NSResponder.deleteForward(_:)),
             #selector(NSResponder.deleteWordBackward(_:)),
             #selector(NSResponder.deleteWordForward(_:)),
             #selector(NSResponder.deleteToBeginningOfLine(_:)),
             #selector(NSResponder.deleteToEndOfLine(_:)):
            deletingText = true
            return false
        default:
            return false
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !isCompletingInline else { return }
        typedBeforeArrow = nil
        guard let editor = field.currentEditor() as? NSTextView else { return }
        let typed = typedPath(in: editor)

        let matches = completionMatches(for: typed)
        if !deletingText, let first = matches.first {
            inlineComplete(editor: editor, typed: typed, with: first)
        }
        deletingText = false
        updateDropdown(typedPath: typed, matches: matches)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        endEditing()
    }

    // MARK: Completion logic

    private func typedPath(in editor: NSTextView) -> String {
        let cursorPos = editor.selectedRange().location
        return (editor.string as NSString).substring(to: cursorPos)
    }

    private func splitPath(_ typed: String) -> (dir: String, prefix: String) {
        let expanded = (typed as NSString).expandingTildeInPath
        if typed.hasSuffix("/") { return (expanded, "") }
        return ((expanded as NSString).deletingLastPathComponent,
                (expanded as NSString).lastPathComponent)
    }

    private func completionMatches(for typed: String) -> [String] {
        let (dir, prefix) = splitPath(typed)
        guard !dir.isEmpty,
              let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        let matches = contents.filter { n in
            (prefix.isEmpty || n.lowercased().hasPrefix(prefix.lowercased())) &&
            isDirectory((dir as NSString).appendingPathComponent(n))
        }
        let visible = matches.filter { !$0.hasPrefix(".") }.sorted()
        guard DisplaySettings.addressBarCompletionShowsHiddenFolders else { return visible }
        let hidden = matches.filter { $0.hasPrefix(".") }.sorted()
        return visible + hidden
    }

    private func inlineComplete(editor: NSTextView, typed: String, with first: String) {
        let (_, prefix) = splitPath(typed)
        guard !prefix.isEmpty else { return }
        let tail = String(first.dropFirst(prefix.count))
        guard !tail.isEmpty else { return }
        isCompletingInline = true
        let cursorPos = editor.selectedRange().location
        let afterCursor = NSRange(location: cursorPos, length: editor.string.count - cursorPos)
        editor.textStorage?.replaceCharacters(in: afterCursor, with: tail)
        editor.setSelectedRange(NSRange(location: cursorPos, length: tail.count))
        isCompletingInline = false
    }

    private func acceptInlineCompletion(editor: NSTextView) {
        // Move cursor to end and append "/" if the path is a directory.
        let full = editor.string
        isCompletingInline = true
        editor.setSelectedRange(NSRange(location: full.count, length: 0))
        let expanded = (full as NSString).expandingTildeInPath
        if !full.hasSuffix("/"), isDirectory(expanded) {
            editor.textStorage?.append(NSAttributedString(string: "/"))
            editor.setSelectedRange(NSRange(location: full.count + 1, length: 0))
        }
        isCompletingInline = false
        updateDropdown(typedPath: editor.string)
    }

    private func updateDropdown(typedPath typed: String, matches: [String]? = nil) {
        let (dir, _) = splitPath(typed)
        let items = matches ?? completionMatches(for: typed)
        // Show full paths so the dropdown tells the user where each folder is.
        let paths = items.map { (dir as NSString).appendingPathComponent($0) }
        dropdown.items = paths
        if paths.isEmpty {
            dropdown.hide()
        } else if let win = window {
            let barFrame = convert(bounds, to: nil)
            dropdown.show(below: barFrame, in: win)
        }
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}

// MARK: - Completion dropdown

/// NSTableView whose selection tracks mouse hover.
private final class HoverTableView: NSTableView {
    var onHover: ((Int) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        onHover?(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(-1)
    }
}

/// A floating list of path suggestions anchored below the address bar, like Windows Explorer.
private final class CompletionDropdown: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
    var items: [String] = [] { didSet { table.reloadData(); updateSize() } }
    var onSelect: ((String) -> Void)?
    /// Called when the keyboard highlight moves; nil means back to no selection.
    var onHighlight: ((String?) -> Void)?

    private let table = HoverTableView()
    private let scroll = NSScrollView()
    private static let rowHeight: CGFloat = 20
    private static let maxRows = 10
    private static let topPad: CGFloat = 4
    private static let bottomPad: CGFloat = 4

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.nonactivatingPanel, .borderless, .resizable],
                   backing: .buffered,
                   defer: true)
        isFloatingPanel = true
        isMovable = false
        hasShadow = true
        backgroundColor = .clear
        acceptsMouseMovedEvents = true

        let column = NSTableColumn(identifier: .init("path"))
        column.isEditable = false
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .regular
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.focusRingType = .none
        table.target = self
        table.action = #selector(rowClicked)
        table.onHover = { [weak self] row in self?.hoverRow(row) }

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero

        let container = NSVisualEffectView()
        container.material = .menu
        container.state = .active
        container.blendingMode = .behindWindow
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true

        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.topPad),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.bottomPad),
        ])
        contentView = container
    }

    private func hoverRow(_ row: Int) {
        guard row >= 0, row < items.count else {
            guard table.selectedRow >= 0 else { return }
            table.deselectAll(nil)
            onHighlight?(nil)
            return
        }
        guard row != table.selectedRow else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        onHighlight?(items[row])
    }

    func show(below barFrame: NSRect, in parentWindow: NSWindow) {
        guard !items.isEmpty else { hide(); return }
        let h = CGFloat(min(items.count, Self.maxRows)) * Self.rowHeight + Self.topPad + Self.bottomPad
        let screenRect = parentWindow.convertToScreen(barFrame)
        setFrame(NSRect(x: screenRect.minX, y: screenRect.minY - h,
                        width: screenRect.width, height: h), display: false)
        if parent == nil { parentWindow.addChildWindow(self, ordered: .above) }
        orderFront(nil)
    }

    func hide() {
        if let p = parent { p.removeChildWindow(self) }
        orderOut(nil)
        table.deselectAll(nil)
    }

    func selectNext() {
        let next = table.selectedRow < items.count - 1 ? table.selectedRow + 1 : 0
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        table.scrollRowToVisible(next)
        onHighlight?(items[next])
    }

    func selectPrevious() {
        guard !items.isEmpty else { return }
        let prev = table.selectedRow > 0 ? table.selectedRow - 1 : items.count - 1
        table.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
        table.scrollRowToVisible(prev)
        onHighlight?(items[prev])
    }

    private func updateSize() {
        guard let parentWindow = parent else { return }
        let h = CGFloat(min(items.count, Self.maxRows)) * Self.rowHeight + Self.topPad + Self.bottomPad
        var frame = self.frame
        frame.origin.y = frame.maxY - h
        frame.size.height = h
        setFrame(frame, display: true)
        _ = parentWindow
    }

    @objc private func rowClicked() {
        guard table.clickedRow >= 0, table.clickedRow < items.count else { return }
        onSelect?(items[table.clickedRow])
        hide()
    }

    // MARK: NSTableViewDataSource / NSTableViewDelegate

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = id
            let img = NSImageView()
            img.translatesAutoresizingMaskIntoConstraints = false
            img.imageScaling = .scaleProportionallyDown
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingMiddle
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            cell.addSubview(img)
            cell.addSubview(label)
            cell.imageView = img
            cell.textField = label
            NSLayoutConstraint.activate([
                img.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                img.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                img.widthAnchor.constraint(equalToConstant: 16),
                img.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let url = URL(fileURLWithPath: items[row])
        cell.imageView?.image = NSWorkspace.shared.icon(forFile: items[row])
        cell.textField?.stringValue = url.lastPathComponent
        return cell
    }
}
