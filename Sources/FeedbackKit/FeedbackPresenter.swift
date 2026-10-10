#if canImport(UIKit) || canImport(AppKit)
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Presents FeedbackKit's views over whatever the app shows, sheets included: from the topmost
/// view controller on iOS, as a sheet of the key window on the Mac. A SwiftUI `.sheet` on the
/// root view couldn't open while the app has a sheet of its own up.
@MainActor
enum FeedbackPresenter {
    static func present<Content: View>(
        title: String,
        onDismiss: @escaping @MainActor () -> Void,
        @ViewBuilder content: (_ close: @escaping @MainActor () -> Void) -> Content
    ) {
        let presentation = Presentation(onDismiss: onDismiss)
        #if canImport(UIKit)
        guard let top = topViewController() else {
            presentation.close()
            return
        }
        let host = UIHostingController(rootView: content { presentation.close() })
        host.title = title
        host.modalPresentationStyle = .formSheet
        // Swiping the form away would lose what was typed; it has a Cancel button.
        host.isModalInPresentation = true
        presentation.controller = host
        top.present(host, animated: true)
        #elseif canImport(AppKit)
        let host = NSHostingController(rootView: content { presentation.close() })
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = presentation
        presentation.window = window
        if let parent = ScreenCapture.appWindow() {
            parent.beginSheet(window)
        } else {
            // A menu bar app with no window open: a window of its own, brought to the front.
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        #endif
    }

    #if canImport(UIKit)
    static func topViewController() -> UIViewController? {
        var top = ScreenCapture.appWindow()?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
    #endif
}

/// One presented view; `close()` takes it down and tells the center.
@MainActor
final class Presentation: NSObject {
    private var onDismiss: (@MainActor () -> Void)?

    init(onDismiss: @escaping @MainActor () -> Void) {
        self.onDismiss = onDismiss
    }

    #if canImport(UIKit)
    weak var controller: UIViewController?
    #elseif canImport(AppKit)
    // Held until closed; it holds the view, which holds this presentation's `close`.
    var window: NSWindow?
    #endif

    func close() {
        #if canImport(UIKit)
        controller?.dismiss(animated: true)
        controller = nil
        #elseif canImport(AppKit)
        if let window {
            self.window = nil
            if let parent = window.sheetParent {
                parent.endSheet(window)
            } else {
                window.close()
            }
        }
        #endif
        finish()
    }

    private func finish() {
        onDismiss?()
        onDismiss = nil
    }
}

#if canImport(AppKit) && !canImport(UIKit)
extension Presentation: NSWindowDelegate {
    // A window of its own (no key window to attach a sheet to) closed with its close button.
    func windowWillClose(_ notification: Notification) {
        window = nil
        finish()
    }
}
#endif
#endif
