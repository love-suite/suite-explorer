import ExplorerUI
import SuiteCore

extension SuiteUpdater {
    /// Explorer's: its settings in Explorer's defaults (Suite Settings shows them), installed without
    /// asking once no Explorer window is open.
    static let explorer = SuiteUpdater(appName: "Explorer", defaults: SuiteDefaults.explorer,
                                       isBusy: { ExplorerWindowController.hasOpenWindows })
}
