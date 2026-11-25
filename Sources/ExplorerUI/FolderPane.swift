import AppKit
import ExplorerCore
import ExplorerSettings
import SuiteCore
import SuiteFilesCore
import SuiteFilesUI

/// One folder shown in an Explorer window: back, forward and up, its address bar and view options on
/// top, its files below, with its own history. Side by Side, the window shows two panes; the active one
/// (outlined address bar) is the one the command bar and the menus act on.
final class FolderPane: NSViewController {
    private(set) var history: NavigationHistory
    let list = FileListViewController()
    let addressBar = AddressBar()
    /// The user clicked into this pane.
    var onActivate: (() -> Void)?
    /// The pane now shows another folder.
    var onFolderChange: (() -> Void)?
    var onSelectionChange: (([URL]) -> Void)?
    /// The scope bar's choice changed while searching.
    var onScopeChange: ((SearchScope) -> Void)?
    /// The search ended (the pane went to another folder): the window clears its search box.
    var onSearchEnd: (() -> Void)?

    /// Outlines the address bar: this is the active pane of two.
    var marksActive = false {
        didSet { addressBar.isHighlighted = marksActive }
    }

    private lazy var backButton = button("chevron.left", UIL("Back"), #selector(back))
    private lazy var forwardButton = button("chevron.right", UIL("Forward"), #selector(forward))
    private lazy var upButton = button("arrow.up", UIL("Up"), #selector(up))
    private static let modes: [(ViewMode, String, String)] = [
        (.icons, "square.grid.2x2", UIL("Icons")), (.details, "list.bullet.indent", UIL("Details")),
        (.columns, "rectangle.split.3x1", UIL("Columns")),
    ]
    private lazy var modeControl: NSSegmentedControl = {
        let images = Self.modes.map { NSImage(systemSymbolName: $0.1, accessibilityDescription: $0.2) ?? NSImage() }
        let control = NSSegmentedControl(images: images, trackingMode: .selectOne,
                                         target: self, action: #selector(modeChanged))
        for (index, mode) in Self.modes.enumerated() { control.setToolTip(mode.2, forSegment: index) }
        return control
    }()

    /// What Recents, Shared or this Mac holds, on its way.
    private var placeContents: PlaceContents?
    /// The search typed in the window's toolbar, shown here in place of the folder's contents.
    private var search: FolderSearch?
    private(set) var searchText = ""
    /// The walk through the folders is still adding results.
    private var stillLooking = false
    private(set) var searchScope: SearchScope?
    private var scopeChoices: [SearchScope] = []
    var isSearching: Bool { !searchText.isEmpty }

    /// While searching, where the search looks, as in Finder: "Search: This Mac | "Folder" | …".
    private lazy var scopeControl: NSSegmentedControl = {
        let control = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: self,
                                         action: #selector(scopeChanged))
        control.segmentStyle = .rounded
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return control
    }()
    private lazy var scopeBar: NSStackView = {
        let label = NSTextField(labelWithString: UIL("Search:"))
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let bar = NSStackView(views: [label, scopeControl])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.isHidden = true
        return bar
    }()
    private var listBelowBar: NSLayoutConstraint?
    private var listBelowScope: NSLayoutConstraint?

    /// Item count, selection and free space, under the files.
    private let statusBar: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.lineBreakMode = .byTruncatingTail
        return field
    }()

    init(url: URL) {
        history = NavigationHistory(start: url)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        // The address bar takes all the room; the view options sit at the far right (search is in the
        // window's toolbar).
        let bar = NSStackView(views: [backButton, forwardButton, upButton, addressBar, modeControl])
        bar.distribution = .fill
        bar.detachesHiddenViews = true
        bar.orientation = .horizontal
        bar.spacing = 4
        bar.setCustomSpacing(8, after: addressBar)
        for view in [backButton, forwardButton, upButton, modeControl] as [NSView] {
            view.setContentHuggingPriority(.required, for: .horizontal)
        }
        addressBar.setContentHuggingPriority(.init(1), for: .horizontal)

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        let line = NSBox()
        line.boxType = .separator
        for view in [bar, scopeBar, list.view, line, statusBar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            // Below the toolbar and the tab bar, which the window's content runs under.
            bar.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 6),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scopeBar.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            scopeBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            scopeBar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -10),
            list.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            list.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            line.topAnchor.constraint(equalTo: list.view.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 3),
            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            statusBar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -10),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4),
        ])
        listBelowBar = list.view.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 6)
        listBelowScope = list.view.topAnchor.constraint(equalTo: scopeBar.bottomAnchor, constant: 6)
        listBelowBar?.isActive = true
        view = root

        list.onOpenFolder = { [weak self] in self?.navigate(to: $0) }
        list.onSelectionChange = { [weak self] urls in
            self?.updateStatus()
            self?.onSelectionChange?(urls)
        }
        list.onGoUp = { [weak self] in self?.up() }
        list.onGoBack = { [weak self] in self?.back() }
        list.onGoForward = { [weak self] in self?.forward() }
        list.onOptionsChange = { [weak self] options in
            guard let self else { return }
            FolderViewStore.shared.save(options, for: self.url)
            self.updateModeControl()
        }
        addressBar.onNavigate = { [weak self] url in
            self?.onActivate?()
            self?.navigate(to: url)
        }
        addressBar.onSubmit = { [weak self] text in self?.submitAddress(text) ?? false }
        show()
    }

    /// In shades of grey while the window isn't in front.
    private lazy var greyscale = InactiveGreyscale(view)

    override func viewDidAppear() {
        super.viewDidAppear()
        greyscale.follow()
    }

    private func button(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.toolTip = label
        return button
    }

    var url: URL { history.current }

    func navigate(to url: URL) {
        history.go(to: url)
        show()
    }

    @objc func back() { onActivate?(); history.back(); show() }
    @objc func forward() { onActivate?(); history.forward(); show() }
    @objc func up() { onActivate?(); history.up(); show() }

    private func show() {
        _ = view
        endSearch()
        showContents(options: FolderViewStore.shared.options(for: url))
        addressBar.url = url
        updateStatus()
        backButton.isEnabled = history.canGoBack
        forwardButton.isEnabled = history.canGoForward
        upButton.isEnabled = history.canGoUp
        updateModeControl()
        onFolderChange?()
    }

    /// The folder's contents, or what a place that isn't a folder (Recents) holds, once read.
    private func showContents(options: FolderViewOptions) {
        placeContents?.stop()
        placeContents = nil
        guard let place = VirtualPlace(url: url) else {
            list.load(url, options: options)
            return
        }
        list.showPlace([], options: options, emptyMessage: "")
        placeContents = PlaceContents(place) { [weak self] items in
            guard let self else { return }
            self.list.showPlace(items, options: self.list.options, emptyMessage: Self.emptyMessage(for: place))
            self.updateStatus()
        }
    }

    private static func emptyMessage(for place: VirtualPlace) -> String {
        switch place {
        case .recents: return UIL("No files opened in the last 30 days.")
        case .shared: return UIL("Nothing in iCloud Drive is shared.")
        case .computer: return UIL("No disks.")
        }
    }

    private func updateModeControl() {
        modeControl.selectedSegment = Self.modes.firstIndex { $0.0 == list.options.mode } ?? 1
    }

    @objc private func modeChanged() {
        onActivate?()
        list.setMode(Self.modes[max(modeControl.selectedSegment, 0)].0)
    }

    func updateStatus() {
        let available = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        var text = FolderSummary.text(itemCount: list.items.count, selected: list.selectedItems,
                                      availableBytes: available)
        if isSearching {
            let count = list.items.count
            let what = count >= FolderSearch.limit ? "First \(count) results" : "Search results"
            text = what + (stillLooking ? " (still looking in subfolders)" : "") + "   |   " + text
        }
        statusBar.stringValue = text
    }

    // MARK: Search

    /// Shows the items matching `text` in `scope`, with the scope bar offering `choices`.
    func search(_ text: String, scope: SearchScope, choices: [SearchScope]) {
        _ = view
        search?.stop()
        searchText = text
        searchScope = scope
        scopeChoices = choices
        scopeControl.segmentCount = choices.count
        for (index, choice) in choices.enumerated() {
            scopeControl.setLabel(choice.title, forSegment: index)
            scopeControl.setWidth(0, forSegment: index)
        }
        scopeControl.selectedSegment = choices.firstIndex(of: scope) ?? 0
        showScopeBar(true)
        let place = scope.kind == .thisMac ? "This Mac" : scope.title
        statusBar.stringValue = "Searching \u{201C}\(text)\u{201D} in \(place)"
        search = FolderSearch(text: text, in: scope.folders, showHidden: DisplaySettings.showsHiddenFiles) {
            [weak self] results, stillLooking in
            guard let self else { return }
            self.stillLooking = stillLooking
            self.list.showResults(results)
            self.updateStatus()
        }
    }

    /// Back to the folder's contents.
    func clearSearch() {
        guard isSearching else { return }
        endSearch()
        showContents(options: list.options)
        updateStatus()
    }

    private func endSearch() {
        search?.stop()
        search = nil
        let wasSearching = isSearching
        searchText = ""
        searchScope = nil
        showScopeBar(false)
        if wasSearching { onSearchEnd?() }
    }

    private func showScopeBar(_ shown: Bool) {
        guard scopeBar.isHidden == shown else { return }
        scopeBar.isHidden = !shown
        listBelowBar?.isActive = !shown
        listBelowScope?.isActive = shown
    }

    @objc private func scopeChanged() {
        onActivate?()
        let index = scopeControl.selectedSegment
        guard scopeChoices.indices.contains(index) else { return }
        onScopeChange?(scopeChoices[index])
    }

    /// Typed paths accept POSIX, "~" and pasted Windows paths. A file opens instead of navigating.
    private func submitAddress(_ text: String) -> Bool {
        guard let url = PathParser.parse(text),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else { return false }
        if values.isDirectory == true && values.isPackage != true {
            navigate(to: url)
        } else {
            FileActions.openFile(url)
        }
        return true
    }
}
