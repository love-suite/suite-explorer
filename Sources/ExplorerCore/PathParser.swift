import Foundation

public enum PathParser {
    /// Parses a path string into a file URL.
    ///
    /// Accepts:
    /// - POSIX paths: `/Users/alice/Documents`
    /// - Tilde paths: `~/Desktop`
    /// - Windows absolute paths: `C:\Users\alice\Docs` → `/Users/alice/Docs`
    ///
    /// Returns `nil` for relative paths or empty strings.
    public static func parse(_ string: String) -> URL? {
        var path = string.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }

        // Normalise backslashes to forward slashes
        path = path.replacingOccurrences(of: "\\", with: "/")

        // Strip Windows drive letter: "C:/…" → "/…"
        if path.count >= 3 {
            let i1 = path.index(path.startIndex, offsetBy: 1)
            let i2 = path.index(path.startIndex, offsetBy: 2)
            if path[i1] == ":" && path[i2] == "/" {
                path = String(path[i2...])
            }
        }

        // Expand tilde
        if path == "~" || path.hasPrefix("~/") {
            path = (path as NSString).expandingTildeInPath
        }

        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path).standardized
    }
}
