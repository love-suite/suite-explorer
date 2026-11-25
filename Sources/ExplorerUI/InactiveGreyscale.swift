import AppKit

extension NSWindow {
    /// The selected window: the one taking the keyboard, or the one under a panel that does (Quick Look).
    /// Any other, even on screen and even in Explorer (the desktop selected), shows as inactive.
    var showsAsActive: Bool {
        isKeyWindow || (isMainWindow && NSApp.keyWindow is NSPanel)
    }

    /// Calls `change` whenever this window may have become, or stopped being, the selected one.
    func observeActivity(_ change: @escaping () -> Void) -> [NSObjectProtocol] {
        let names: [(Notification.Name, AnyObject?)] = [
            (NSWindow.didBecomeKeyNotification, nil), (NSWindow.didResignKeyNotification, nil),
            (NSWindow.didBecomeMainNotification, self), (NSWindow.didResignMainNotification, self),
            (NSApplication.didBecomeActiveNotification, nil), (NSApplication.didResignActiveNotification, nil),
        ]
        return names.map { name, object in
            NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { _ in change() }
        }
    }
}

/// Turns a view to shades of grey, its icons and thumbnails included, while its window isn't the selected
/// one: one step further than Finder, which only greys its sidebar and toolbar.
final class InactiveGreyscale {
    private weak var view: NSView?
    private var observers: [NSObjectProtocol] = []
    private static let filter: CIFilter = {
        let filter = CIFilter(name: "CIColorControls")!
        filter.setDefaults()
        filter.setValue(0, forKey: kCIInputSaturationKey)
        return filter
    }()

    init(_ view: NSView) {
        self.view = view
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// Once the view is in its window (`viewDidAppear`), and again whenever it moves to another.
    func follow() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = view?.window?.observeActivity { [weak self] in self?.update() } ?? []
        update()
    }

    private func update() {
        guard let view else { return }
        view.wantsLayer = true
        view.layerUsesCoreImageFilters = true
        view.contentFilters = view.window?.showsAsActive == true ? [] : [Self.filter]
    }
}
