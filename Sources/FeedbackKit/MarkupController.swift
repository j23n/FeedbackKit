#if canImport(UIKit)
import QuickLook
import UIKit

/// Opens the screenshot in Quick Look with the system's Markup tools (pen, highlighter, text,
/// shapes, magnifier) and hands back the edited image.
@MainActor
final class MarkupController: NSObject {
    /// The open one, kept alive while Quick Look shows its file.
    private static var current: MarkupController?

    private let fileURL: URL
    private let onChange: @MainActor (Data) -> Void

    private init(fileURL: URL, onChange: @escaping @MainActor (Data) -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
    }

    static func present(_ png: Data, onChange: @escaping @MainActor (Data) -> Void) {
        guard let top = FeedbackPresenter.topViewController() else { return }
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "Feedback-\(UUID().uuidString).png")
        do {
            try png.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
        let controller = MarkupController(fileURL: fileURL, onChange: onChange)
        current = controller
        let preview = QLPreviewController()
        preview.dataSource = controller
        preview.delegate = controller
        top.present(preview, animated: true)
    }

    private func reload() {
        if let data = try? Data(contentsOf: fileURL) {
            onChange(data)
        }
    }

    private func finish() {
        reload()
        try? FileManager.default.removeItem(at: fileURL)
        if Self.current === self { Self.current = nil }
    }
}

extension MarkupController: QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    nonisolated func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    nonisolated func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        fileURL as NSURL
    }

    nonisolated func previewController(
        _ controller: QLPreviewController,
        editingModeFor previewItem: any QLPreviewItem
    ) -> QLPreviewItemEditingMode {
        .updateContents
    }

    nonisolated func previewController(_ controller: QLPreviewController, didUpdateContentsOf previewItem: any QLPreviewItem) {
        Task { @MainActor in self.reload() }
    }

    nonisolated func previewControllerDidDismiss(_ controller: QLPreviewController) {
        Task { @MainActor in self.finish() }
    }
}
#endif
