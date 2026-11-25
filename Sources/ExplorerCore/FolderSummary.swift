import Foundation
import SuiteFilesCore

/// The status bar's text: Windows' item and selection counts, Finder's free space.
public enum FolderSummary {
    public static func text(itemCount: Int, selected: [FileItem], availableBytes: Int64?) -> String {
        var parts = [count(itemCount)]
        if !selected.isEmpty {
            var selection = count(selected.count) + " selected"
            // Windows adds the size of selected files; folders would need measuring, so they don't count.
            let files = selected.filter { !$0.isDirectory }
            if !files.isEmpty, files.count == selected.count {
                let bytes = files.compactMap(\.size).reduce(0, +)
                selection += "  " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            }
            parts.append(selection)
        }
        if let availableBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file) + " available")
        }
        return parts.joined(separator: "   |   ")
    }

    private static func count(_ n: Int) -> String { n == 1 ? "1 item" : "\(n) items" }
}
