import AppKit
import ExplorerCore
import SuiteFilesUI

/// Disks appearing, leaving and renamed, live: the sidebar, This Mac and the panes showing a disk follow.
enum VolumeMonitor {
    /// Calls `handler` on the main thread with the volume's folder each time a disk is mounted, unmounted
    /// or renamed; keep the tokens for as long as it should be called.
    static func observe(_ handler: @escaping (_ change: Change, _ volume: URL) -> Void) -> [NSObjectProtocol] {
        let center = NSWorkspace.shared.notificationCenter
        return [(NSWorkspace.didMountNotification, Change.mounted),
                (NSWorkspace.didUnmountNotification, .unmounted),
                (NSWorkspace.didRenameVolumeNotification, .renamed)].map { name, change in
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
                handler(change, url)
            }
        }
    }

    static func stopObserving(_ tokens: [NSObjectProtocol]) {
        tokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    enum Change { case mounted, unmounted, renamed }
}

extension FileActions {
    /// Unmounts and ejects disks, as Finder's Eject: off the main thread, which it can hold for seconds;
    /// says why when a disk is in use.
    public static func eject(_ volumes: [URL]) {
        for volume in volumes {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
                } catch {
                    let name = (try? volume.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName
                        ?? volume.lastPathComponent
                    DispatchQueue.main.async {
                        showError(String(format: UIL("The disk \u{201C}%@\u{201D} couldn't be ejected."), name)
                                  + "\n" + error.localizedDescription)
                    }
                }
            }
        }
    }

    /// The disks among `urls` that can be ejected, when all of them are such disks (Eject in menus).
    static func ejectableVolumes(_ urls: [URL]) -> [URL]? {
        guard !urls.isEmpty else { return nil }
        let volumes = VolumeInfo.mounted().filter(\.canEject)
        let found = urls.compactMap { url in
            volumes.first { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }?.url
        }
        return found.count == urls.count ? found : nil
    }

    /// Mounts a disk image and shows what it holds in an Explorer window, as Windows does with an ISO.
    /// Images hdiutil can't mount alone (a password, a licence to agree to) go to the system's
    /// DiskImageMounter, which asks; the disk then shows in the sidebar.
    static func openDiskImage(_ url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = DiskImage.attachArguments(for: url)
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            var mountPoints: [URL] = []
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 { mountPoints = DiskImage.mountPoints(fromAttachOutput: data) }
            } catch {}
            DispatchQueue.main.async {
                guard !mountPoints.isEmpty else {
                    NSWorkspace.shared.open(url)
                    return
                }
                mountPoints.forEach { ExplorerWindowController.open($0) }
            }
        }
    }
}
