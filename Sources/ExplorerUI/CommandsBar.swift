import AppKit
import ExplorerCore
import ExplorerSettings

/// The toolbar's commands, one toolbar item that shrinks with the window: the first buttons that fit stay,
/// the others go into the » button at the end, as macOS does with toolbar items that don't fit
/// (`ToolbarOverflow`). + is one of the buttons, wherever it was put. The settings' mock lays them out the
/// same way.
public final class CommandsBar: NSView {
    public static let spacing = ToolbarOverflow.buttonSpacing

    /// », shown only when some buttons don't fit; its menu lists them.
    public let overflow: NSButton = {
        let button = NSButton(title: "", image: NSImage(systemSymbolName: "chevron.right.2",
                                                         accessibilityDescription: "More Buttons") ?? NSImage(),
                              target: nil, action: nil)
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        return button
    }()
    private var buttons: [NSButton] = []
    private var commands: [ToolbarCommand] = []
    /// How many of the buttons show, after the last layout.
    public private(set) var visibleCount = 0

    /// A command's name as it reads now (Delete Permanently names the selection); its default title else.
    public var title: (ToolbarCommand) -> String = { $0.title }
    private let hoverLabel = HoverLabel()
    private var hovered: NSButton?

    /// The commands that didn't fit, for the » menu.
    public var overflowed: [ToolbarCommand] { Array(commands.dropFirst(visibleCount)) }
    public var isOverflowing: Bool { visibleCount < commands.count }

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        addSubview(overflow)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways,
                                                               .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The buttons to show, in order, with their commands.
    public func show(_ commands: [ToolbarCommand], buttons: [NSButton]) {
        guard commands != self.commands || buttons != self.buttons else {
            needsLayout = true
            return
        }
        for button in self.buttons where !buttons.contains(button) { button.removeFromSuperview() }
        for button in buttons where button.superview !== self { addSubview(button) }
        self.commands = commands
        self.buttons = buttons
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private var buttonWidths: [CGFloat] { buttons.map { ceil($0.fittingSize.width) } }
    private var overflowWidth: CGFloat { ceil(overflow.fittingSize.width) }

    /// Everything shown, no ».
    public var fullWidth: CGFloat { max(buttonWidths.reduce(0) { $0 + $1 + Self.spacing } - Self.spacing, 34) }

    public override var intrinsicContentSize: NSSize { NSSize(width: fullWidth, height: 28) }

    public override func layout() {
        super.layout()
        let widths = buttonWidths
        visibleCount = fullWidth <= bounds.width + 0.5 ? buttons.count
            : ToolbarOverflow.visibleCount(widths: widths, spacing: Self.spacing, trailing: overflowWidth,
                                           available: bounds.width)
        var x: CGFloat = 0
        for (index, button) in buttons.enumerated() {
            button.isHidden = index >= visibleCount
            guard index < visibleCount else { continue }
            let size = button.fittingSize
            button.frame = NSRect(x: x, y: (bounds.height - size.height) / 2, width: widths[index], height: size.height)
            x += widths[index] + Self.spacing
        }
        overflow.isHidden = !isOverflowing
        let size = overflow.fittingSize
        overflow.frame = NSRect(x: x, y: (bounds.height - size.height) / 2, width: overflowWidth, height: size.height)
    }

    // MARK: Name and help under the mouse, at once

    public override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let button = (buttons + [overflow]).first { !$0.isHidden && $0.frame.contains(point) }
        guard button !== hovered else { return }
        hovered = button
        guard let button, let window else { return hoverLabel.hide() }
        let title: String, detail: String
        if button === overflow {
            title = "More Buttons"
            detail = "The buttons the window is too narrow for."
        } else if let index = buttons.firstIndex(of: button) {
            title = self.title(commands[index])
            detail = commands[index].help
        } else {
            return
        }
        hoverLabel.show(title: title, detail: detail, below: window.convertToScreen(convert(button.frame, to: nil)),
                        over: window)
    }

    public override func mouseExited(with event: NSEvent) {
        hovered = nil
        hoverLabel.hide()
    }

    public override func mouseDown(with event: NSEvent) {
        hoverLabel.hide()
        super.mouseDown(with: event)
    }
}
