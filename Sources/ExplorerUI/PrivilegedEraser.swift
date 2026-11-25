import AppKit
import ServiceManagement
import SuiteFilesUI

// XPC protocol — must match Trash/main.swift exactly.
@objc protocol TrashHelperXPC {
    func deleteFiles(_ paths: [String], withReply reply: @escaping (String?) -> Void)
}

/// Deletes files that require root privileges.
///
/// Flow:
/// 1. If the SMAppService helper is enabled → silent XPC call.
/// 2. If not registered yet → register (macOS sends a Login Items notification) →
///    show an alert offering to open System Settings or use the password this time.
/// 3. If the helper needs approval or is unavailable → same alert.
///
/// The helper (Suite Trash, local.suite.explorer.trash) is a LaunchDaemon that
/// runs as root; registered once via SMAppService, it needs no further authentication. It lets
/// in only Explorer signed with its own certificate, and erases only items in the Trash.
public enum PrivilegedEraser {

    private static let serviceID = "local.suite.explorer.trash"
    private static let plistName = "local.suite.explorer.trash.plist"

    public static func erase(_ urls: [URL]) {
        let service = SMAppService.daemon(plistName: plistName)
        switch service.status {
        case .enabled:
            eraseViaXPC(urls)
        case .notRegistered, .notFound:
            registerThenErase(service, urls)
        case .requiresApproval:
            promptApprovalOrFallback(urls)
        @unknown default:
            eraseViaOsascript(urls)
        }
    }

    // MARK: – Registration

    private static func registerThenErase(_ service: SMAppService, _ urls: [URL]) {
        // register() may throw if already registered; in that case we still check status.
        try? service.register()
        switch service.status {
        case .enabled:
            eraseViaXPC(urls)
        default:
            promptApprovalOrFallback(urls)
        }
    }

    // MARK: – Approval prompt

    private static func promptApprovalOrFallback(_ urls: [URL]) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Enable Suite Trash"
            alert.informativeText = "To erase protected items from the Trash without a password from now on, allow \u{201C}Explorer\u{201D} in System Settings \u{203A} General \u{203A} Login Items \u{203A} Allow in the Background."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Use Password This Time")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            } else {
                eraseViaOsascript(urls)
            }
        }
    }

    // MARK: – XPC

    private static func eraseViaXPC(_ urls: [URL]) {
        let paths = urls.map(\.path)
        let connection = NSXPCConnection(machServiceName: serviceID, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: TrashHelperXPC.self)
        connection.resume()
        // Refused or unreachable (a build signed ad hoc, which the helper can't tell from another
        // caller): the password this time instead. rm -rf skips what the helper already erased.
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            connection.invalidate()
            DispatchQueue.main.async { eraseViaOsascript(urls) }
        } as? TrashHelperXPC
        proxy?.deleteFiles(paths) { message in
            connection.invalidate()
            if let message {
                DispatchQueue.main.async { FileActions.showError(message) }
            }
        }
    }

    // MARK: – osascript fallback (Touch ID / password, one dialog per use)

    static func eraseViaOsascript(_ urls: [URL]) {
        let quoted = urls.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let shellCmd = "rm -rf " + quoted.joined(separator: " ")
        let escaped = shellCmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let err = error {
            if (err[NSAppleScript.errorNumber] as? Int) == -128 { return }
            let msg = err[NSAppleScript.errorMessage] as? String
                ?? "Couldn't delete with administrator privileges."
            DispatchQueue.main.async { FileActions.showError(msg) }
        }
    }
}
