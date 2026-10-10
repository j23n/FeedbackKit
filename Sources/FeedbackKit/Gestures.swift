#if canImport(UIKit)
import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted when the device is shaken over any of the app's windows.
    static let feedbackDeviceDidShake = Notification.Name("FeedbackKit.deviceDidShake")
}

extension UIWindow {
    // SwiftUI has no shake gesture. A shake no view handled (a text field's Shake to Undo
    // handles its own) reaches the window.
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .feedbackDeviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

/// The window of the banner offered after a screenshot, which the capture leaves out.
final class ScreenshotOfferWindow: UIWindow {}

/// After a screenshot, a banner at the top offers to send the screen as feedback for a few
/// seconds. It's a small window of its own, so it shows over the app's sheets too.
@MainActor
final class ScreenshotOffer {
    private var window: UIWindow?
    private var timeout: Task<Void, Never>?

    static func show(send: @escaping @MainActor () -> Void) -> ScreenshotOffer? {
        guard let appWindow = ScreenCapture.appWindow(), let scene = appWindow.windowScene else { return nil }
        let offer = ScreenshotOffer()
        let banner = ScreenshotOfferBanner(
            send: { [weak offer] in
                offer?.dismiss()
                send()
            },
            close: { [weak offer] in offer?.dismiss() }
        )
        let host = UIHostingController(rootView: banner)
        host.view.backgroundColor = .clear

        let window = ScreenshotOfferWindow(windowScene: scene)
        window.rootViewController = host
        window.windowLevel = .alert
        window.backgroundColor = .clear
        let bounds = appWindow.bounds
        let width = min(bounds.width - 24, 440)
        window.frame = CGRect(x: (bounds.width - width) / 2, y: appWindow.safeAreaInsets.top + 8, width: width, height: 60)
        window.isHidden = false
        offer.window = window

        offer.timeout = Task { [weak offer] in
            try? await Task.sleep(for: .seconds(6))
            offer?.dismiss()
        }
        return offer
    }

    func dismiss() {
        timeout?.cancel()
        timeout = nil
        window?.isHidden = true
        window = nil
    }
}

private struct ScreenshotOfferBanner: View {
    let send: @MainActor () -> Void
    let close: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.bubble")
                .font(.title3)
                .accessibilityHidden(true)
            Text("Send this screen as feedback?")
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("Send") { send() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("feedback.offer.send")
            Button { close() } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("feedback.offer.close")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}
#endif
