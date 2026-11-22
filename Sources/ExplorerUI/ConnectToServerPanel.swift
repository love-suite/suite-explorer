import AppKit
import ExplorerCore
import NetFS
import SuiteFilesUI

/// Finder's Connect to Server (Go menu, Cmd+K): a server's address typed or picked among the recent ones.
/// The share is mounted by the system (NetFS, which asks for a name and password when needed), then shown
/// in an Explorer window; it appears among the sidebar's disks with an eject button.
final class ConnectToServerPanel: NSWindowController, NSWindowDelegate {
    private static var current: ConnectToServerPanel?

    private let field = NSTextField()
    private let recentButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let recents = RecentServers()

    static func show() {
        let panel = current ?? ConnectToServerPanel()
        current = panel
        panel.reloadRecents()
        panel.window?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.showWindow(nil)
        panel.window?.makeFirstResponder(panel.field)
    }

    private init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 120),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = UIL("Connect to Server")
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.delegate = self

        let label = NSTextField(labelWithString: UIL("Server Address:"))
        field.placeholderString = "smb://server/share"
        field.stringValue = recents.addresses.first ?? ""

        recentButton.bezelStyle = .texturedRounded
        recentButton.toolTip = UIL("Recent Servers")

        let connectButton = NSButton(title: UIL("Connect"), target: self, action: #selector(connect))
        connectButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: UIL("Cancel"), target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1B}"

        let content = NSView()
        for view in [label, field, recentButton, connectButton, cancelButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        label.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            label.firstBaselineAnchor.constraint(equalTo: field.firstBaselineAnchor),
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            recentButton.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 6),
            recentButton.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            recentButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            recentButton.widthAnchor.constraint(equalToConstant: 44),
            connectButton.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 20),
            connectButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            connectButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            cancelButton.trailingAnchor.constraint(equalTo: connectButton.leadingAnchor, constant: -12),
            cancelButton.centerYAnchor.constraint(equalTo: connectButton.centerYAnchor),
        ])
        panel.contentView = content
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func windowWillClose(_ notification: Notification) {
        Self.current = nil
    }

    // MARK: Recent servers

    private func reloadRecents() {
        let menu = NSMenu()
        // A pull-down button shows its first item as its face.
        let face = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        face.image = NSImage(systemSymbolName: "clock", accessibilityDescription: UIL("Recent Servers"))
        menu.addItem(face)
        let addresses = recents.addresses
        if addresses.isEmpty {
            let none = NSMenuItem(title: UIL("No Recent Servers"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for address in addresses {
                let item = NSMenuItem(title: address, action: #selector(recentPicked), keyEquivalent: "")
                item.target = self
                item.representedObject = address
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let clear = NSMenuItem(title: UIL("Clear Recent Servers"), action: #selector(clearRecents),
                                   keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        }
        recentButton.menu = menu
    }

    @objc private func recentPicked(_ sender: NSMenuItem) {
        guard let address = sender.representedObject as? String else { return }
        field.stringValue = address
        window?.makeFirstResponder(field)
    }

    @objc private func clearRecents() {
        recents.clear()
        reloadRecents()
    }

    // MARK: Connecting

    @objc private func cancel() {
        window?.close()
    }

    @objc private func connect() {
        let typed = field.stringValue
        guard let url = ServerAddress.url(from: typed) else {
            NSSound.beep()
            FileActions.showError(String(format: UIL("\u{201C}%@\u{201D} isn't a server address."), typed)
                                  + "\n" + UIL("Type an address such as smb://server/share."))
            return
        }
        recents.add(url.absoluteString)
        window?.close()
        Self.connect(to: url)
    }

    /// Mounts the server's share and shows it; screen sharing goes to its own app.
    static func connect(to url: URL) {
        guard ServerAddress.mountsAsDisk(url) else {
            NSWorkspace.shared.open(url)
            return
        }
        let openOptions = NSMutableDictionary(dictionary: ["UIOption": "AllowUI"])   // kNAUIOptionKey, kNAUIOptionAllowUI
        var request: AsyncRequestID?
        let status = NetFSMountURLAsync(url as CFURL, nil, nil, nil, openOptions, nil, &request, .main) {
            status, _, mountPoints in
            let paths = (mountPoints as? [String]) ?? []
            if !paths.isEmpty {
                paths.forEach { ExplorerWindowController.open(URL(fileURLWithPath: $0, isDirectory: true)) }
            } else if status == EEXIST, let mounted = alreadyMounted(url) {
                ExplorerWindowController.open(mounted)
            } else if status != 0, status != ECANCELED, status != Int32(userCanceledErr) {
                failed(url, status)
            }
        }
        if status != 0 { failed(url, status) }
    }

    /// The disk already mounted from that server, when there is one.
    private static func alreadyMounted(_ url: URL) -> URL? {
        VolumeInfo.mounted().first { volume in
            guard let remount = (try? volume.url.resourceValues(forKeys: [.volumeURLForRemountingKey]))?
                .volumeURLForRemounting else { return false }
            return ServerAddress.isSameServer(remount, as: url)
        }?.url
    }

    private static func failed(_ url: URL, _ status: Int32) {
        let reason = NSError(domain: NSPOSIXErrorDomain, code: Int(status)).localizedDescription
        FileActions.showError(String(format: UIL("Couldn't connect to \u{201C}%@\u{201D}."), url.absoluteString)
                              + "\n" + reason)
    }
}
