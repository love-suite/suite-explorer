import AppKit
import SuiteCore

/// Clipboard, the clipboard history app, seen from Explorer: its settings are a tab of Suite Settings, which
/// writes them to Clipboard's own defaults; both apps tell each other about changes with `ClipboardMessage`.
/// Clipboard starts by itself at login (its own login item): Explorer never starts it.
enum ClipboardCompanion {
    static let tabLabel = "Clipboard"

    /// At Explorer's launch: answers Clipboard's gear button.
    static func start() {
        ClipboardMessage.showSettings.observe { _ in SettingsApp.show(tab: tabLabel) }
        if CommandLine.arguments.contains("--clipboard-settings") {
            DispatchQueue.main.async { SettingsApp.show(tab: tabLabel) }
        }
    }
}
