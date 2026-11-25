import Foundation
import TrashCore

// Suite Trash: a launch daemon running as root (SMAppService, `PrivilegedEraser`) that erases items
// in the Trash which need root to erase. Only Explorer, signed with this helper's own certificate, may
// connect, and only items inside the caller's Trash folders are erased (`TrashErasePolicy`).

// XPC protocol exposed by the helper (must match PrivilegedEraser.swift exactly).
@objc protocol TrashHelperXPC {
    func deleteFiles(_ paths: [String], withReply reply: @escaping (String?) -> Void)
    func version(withReply reply: @escaping (String) -> Void)
}

/// One per connection: the caller's Trash folders are its user's.
final class Eraser: NSObject, TrashHelperXPC {
    let uid: uid_t

    init(uid: uid_t) { self.uid = uid }

    func deleteFiles(_ paths: [String], withReply reply: @escaping (String?) -> Void) {
        guard let home = homeFolder(of: uid) else {
            reply("Nothing was erased: the Trash of user \(uid) couldn't be found.")
            return
        }
        let volumes = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                              options: [.skipHiddenVolumes]) ?? []).map(\.path)
        let roots = TrashErasePolicy.roots(home: home, volumes: volumes, uid: uid)
        var failed: [String] = []
        for path in paths {
            switch TrashErasePolicy.check(path, roots: roots) {
            case .failure(let refusal):
                failed.append(refusal.description)
            case .success(let item):
                do {
                    try FileManager.default.removeItem(atPath: item)
                } catch {
                    failed.append("\((item as NSString).lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        reply(failed.isEmpty ? nil : failed.joined(separator: "\n"))
    }

    func version(withReply reply: @escaping (String) -> Void) {
        reply(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
    }
}

func homeFolder(of uid: uid_t) -> String? {
    guard let entry = getpwuid(uid), let dir = entry.pointee.pw_dir else { return nil }
    return TrashErasePolicy.realPath(String(cString: dir))
}

final class Listener: NSObject, NSXPCListenerDelegate {
    /// Read once: without a certificate (ad-hoc signing) no caller can be told from another.
    let requirement = ClientRequirement.forOwnCertificate()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let requirement else {
            NSLog("Suite Trash: refused a connection, the helper has no signing certificate to compare.")
            return false
        }
        // Checked by the system on every message; a caller that doesn't meet it is cut off.
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: TrashHelperXPC.self)
        connection.exportedObject = Eraser(uid: connection.effectiveUserIdentifier)
        connection.resume()
        return true
    }
}

let delegate = Listener()
let listener = NSXPCListener(machServiceName: "local.suite.explorer.trash")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
