import AppKit

/// A folder's name beside the icons-only strip, shown at once under the mouse (a tooltip waits and
/// covers the strip).
final class HoverLabel {
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                            defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        let background = NSVisualEffectView()
        background.material = .toolTip
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.layer?.masksToBounds = true
        text.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 9),
            text.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -9),
            text.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        panel.contentView = background
        return panel
    }()
    private let text: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.maximumNumberOfLines = 0
        field.preferredMaxLayoutWidth = 280
        return field
    }()
    private weak var parent: NSWindow?

    func show(_ name: String, leftCenter: NSPoint, over window: NSWindow) {
        text.stringValue = name
        let width = ceil(text.intrinsicContentSize.width) + 18, height: CGFloat = 26
        panel.setFrame(NSRect(x: leftCenter.x, y: leftCenter.y - height / 2, width: width, height: height),
                       display: true)
        if parent !== window {
            parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
            parent = window
        }
        panel.orderFront(nil)
    }

    /// A button's name in bold and what it does under it, centred under `anchor` (in screen coordinates),
    /// at once (a tooltip waits).
    func show(title: String, detail: String, below anchor: NSRect, over window: NSWindow) {
        let attributed = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize + 1)])
        if !detail.isEmpty {
            attributed.append(NSAttributedString(string: "\n" + detail, attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize + 1),
                .foregroundColor: NSColor.secondaryLabelColor]))
        }
        text.attributedStringValue = attributed
        let size = text.sizeThatFits(NSSize(width: 280, height: 400))
        let width = ceil(size.width) + 18, height = ceil(size.height) + 12
        var x = anchor.midX - width / 2
        if let screen = window.screen?.visibleFrame { x = min(max(x, screen.minX + 4), screen.maxX - width - 4) }
        panel.setFrame(NSRect(x: x, y: anchor.minY - 6 - height, width: width, height: height), display: true)
        if parent !== window {
            parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
            parent = window
        }
        panel.orderFront(nil)
    }

    func hide() {
        guard let parent else { return }
        parent.removeChildWindow(panel)
        panel.orderOut(nil)
        self.parent = nil
    }
}
