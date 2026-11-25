import CryptoKit
import Foundation
import Security

/// Who may talk to Suite Trash: Explorer, signed with the very certificate the helper was signed
/// with ("Suite Local Signing" on this Mac, "Suite Release Signing" for releases; `scripts/make-app.sh`
/// signs both with the same one). Pinning the certificate's hash, read from the helper's own signature,
/// fits both without naming either; a certificate merely named the same doesn't pass.
public enum ClientRequirement {
    public static let explorerBundleID = "local.suite.explorer"

    /// The code requirement for `NSXPCConnection.setCodeSigningRequirement`.
    public static func requirement(bundleID: String = explorerBundleID, leafCertificateSHA1: String) -> String {
        "identifier \"\(bundleID)\" and certificate leaf = H\"\(leafCertificateSHA1)\""
    }

    /// The requirement for this process's own certificate, or nil when it has none (ad-hoc signed, or not
    /// signed): then no one is let in.
    public static func forOwnCertificate() -> String? {
        ownLeafCertificateSHA1().map { requirement(leafCertificateSHA1: $0) }
    }

    /// The SHA-1 of the leaf certificate this process is signed with, in hexadecimal.
    public static func ownLeafCertificateSHA1() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess,
              let dictionary = info as? [String: Any],
              let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first
        else { return nil }
        let data = SecCertificateCopyData(leaf) as Data
        return sha1Hex(data)
    }

    static func sha1Hex(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
