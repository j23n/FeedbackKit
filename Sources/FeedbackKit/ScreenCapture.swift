#if canImport(UIKit) || canImport(AppKit)
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The text UIKit or AppKit draws itself, which SwiftUI's redaction doesn't reach, that the
/// capture paints over.
enum SystemText: Sendable {
    case none
    /// Text fields and editable text views: what the user typed.
    case typed
    /// All of it but the tab bar's labels: titles, labels, buttons' titles and text fields.
    case all
}

/// Captures the app's own window as a PNG. It needs no permission: it draws the window's views
/// rather than reading the screen.
@MainActor
enum ScreenCapture {
    #if canImport(UIKit)
    /// The key window of the app's frontmost scene, leaving out FeedbackKit's own banner.
    static func appWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.filter { $0.activationState == .foregroundActive }
        let windows = (active.isEmpty ? scenes : active)
            .flatMap(\.windows)
            .filter { !$0.isHidden && !($0 is ScreenshotOfferWindow) }
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    static func capture(hiding text: SystemText) -> Data? {
        guard let window = appWindow() else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            UIColor.systemGray3.setFill()
            for frame in textFrames(in: window, hiding: text) {
                UIBezierPath(roundedRect: frame, cornerRadius: 4).fill()
            }
        }
        return image.pngData()
    }

    /// Where, in the window, UIKit draws the text to hide.
    static func textFrames(in window: UIWindow, hiding text: SystemText) -> [CGRect] {
        guard text != .none else { return [] }
        var frames: [CGRect] = []
        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            // The tab bar's labels are the app's own words.
            if view is UITabBar { return }
            let typed = view is UITextField || (view as? UITextView)?.isEditable == true
            if typed || (text == .all && (view is UILabel || view is UITextView)) {
                let frame = view.convert(view.bounds, to: window).intersection(window.bounds)
                if !frame.isEmpty { frames.append(frame) }
                return
            }
            view.subviews.forEach(visit)
        }
        visit(window)
        return frames
    }

    #elseif canImport(AppKit)
    /// The key window, which is a sheet when one is open; otherwise the frontmost of the app's
    /// own windows, leaving out panels such as a menu bar extra's popover.
    static func appWindow() -> NSWindow? {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow, !(window is NSPanel) {
            return window
        }
        return NSApp.orderedWindows.first { $0.isVisible && !($0 is NSPanel) && $0.frame.width > 200 }
    }

    static func capture(hiding text: SystemText) -> Data? {
        // The content view's superview is the whole window, with its title bar and toolbar.
        guard let window = appWindow(), let view = window.contentView?.superview ?? window.contentView else {
            return nil
        }
        let bounds = view.bounds
        guard let representation = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: representation)
        let frames = textFrames(in: view, hiding: text)
        if !frames.isEmpty, let context = NSGraphicsContext(bitmapImageRep: representation) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSColor.systemGray.setFill()
            for frame in frames {
                // The bitmap's origin is at the bottom left, a flipped view's at the top left.
                let y = view.isFlipped ? bounds.maxY - frame.maxY : frame.minY - bounds.minY
                let rect = NSRect(x: frame.minX - bounds.minX, y: y, width: frame.width, height: frame.height)
                NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        return representation.representation(using: .png, properties: [:])
    }

    /// Where, in `root`, AppKit draws the text to hide.
    static func textFrames(in root: NSView, hiding text: SystemText) -> [NSRect] {
        guard text != .none else { return [] }
        var frames: [NSRect] = []
        func visit(_ view: NSView) {
            guard !view.isHidden, view.alphaValue > 0.01 else { return }
            let typed = (view as? NSTextField)?.isEditable == true || (view as? NSTextView)?.isEditable == true
            if typed || (text == .all && (view is NSTextField || view is NSTextView)) {
                var frame = view.convert(view.bounds, to: root).intersection(root.bounds)
                // A text view scrolls: only the part its scroll view shows.
                if let clip = view.enclosingScrollView?.contentView {
                    frame = frame.intersection(clip.convert(clip.bounds, to: root))
                }
                if !frame.isEmpty { frames.append(frame) }
                return
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        return frames
    }
    #endif
}
#endif
