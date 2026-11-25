import AppKit
import Quartz

/// Quick Look preview of the selected file, like Explorer's preview pane.
final class PreviewViewController: NSViewController {
    private var preview: QLPreviewView?

    override func loadView() {
        let preview = QLPreviewView(frame: .zero, style: .normal)
        preview?.autostarts = true
        self.preview = preview
        // Below the toolbar, which the window's content runs under.
        let container = NSView()
        if let preview {
            preview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(preview)
            NSLayoutConstraint.activate([
                preview.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
                preview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                preview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                preview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }
        view = container
    }

    /// In shades of grey while the window isn't in front, as the folders beside it.
    private lazy var greyscale = InactiveGreyscale(view)

    override func viewDidAppear() {
        super.viewDidAppear()
        greyscale.follow()
    }

    func show(_ urls: [URL]) {
        preview?.previewItem = urls.count == 1 ? urls[0] as NSURL : nil
    }
}
