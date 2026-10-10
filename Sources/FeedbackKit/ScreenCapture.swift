#if canImport(UIKit) || canImport(AppKit)
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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

    static func capture() -> Data? {
        guard let window = appWindow() else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return image.pngData()
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

    static func capture() -> Data? {
        // The content view's superview is the whole window, with its title bar and toolbar.
        guard let window = appWindow(), let view = window.contentView?.superview ?? window.contentView else {
            return nil
        }
        let bounds = view.bounds
        guard let representation = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: representation)
        return representation.representation(using: .png, properties: [:])
    }
    #endif
}
#endif
