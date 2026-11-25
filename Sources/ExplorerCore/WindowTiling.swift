import CoreGraphics

/// Two Explorer windows side by side, to copy or move files from one folder to the other.
public enum WindowTiling {
    /// The left and right halves of `area` (the screen without the menu bar and Dock), on whole points.
    public static func halves(of area: CGRect) -> (left: CGRect, right: CGRect) {
        let leftWidth = (area.width / 2).rounded(.down)
        let left = CGRect(x: area.minX, y: area.minY, width: leftWidth, height: area.height)
        let right = CGRect(x: area.minX + leftWidth, y: area.minY, width: area.width - leftWidth,
                           height: area.height)
        return (left, right)
    }

    /// The tab that goes beside tab `index` out of `count`: the next one, or the previous one for the
    /// last tab; none when there is a single tab.
    public static func neighbour(of index: Int, count: Int) -> Int? {
        guard count > 1, index >= 0, index < count else { return nil }
        return index + 1 < count ? index + 1 : index - 1
    }
}
