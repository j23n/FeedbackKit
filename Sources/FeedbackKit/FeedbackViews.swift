#if canImport(UIKit) || canImport(AppKit)
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension View {
    /// Redacts what the configuration's redaction hides while the center captures the screen:
    /// the views marked `privacySensitive()` (`.privacySensitiveViews`), or all text and images
    /// (`.allContent`). Apply it to the root view of each of the app's windows.
    @MainActor
    public func feedbackRedaction(_ center: FeedbackCenter) -> some View {
        redacted(reason: center.isCapturing ? center.configuration.redaction.reasons : [])
    }
}

extension View {
    /// Hides this view in a feedback screenshot, whatever the configuration's redaction: the capture paints over its
    /// frame, so what UIKit or AppKit draw inside it (a picker's title, a text view) is hidden too, which
    /// `privacySensitive()` can't reach. For the person's own data on a screen that otherwise stays visible, such as
    /// what they typed or said. It works in sheets too: the capture finds the region in the window's views.
    public func feedbackHidden(_ hidden: Bool = true) -> some View {
        background {
            if hidden { HiddenRegionMarker() }
        }
    }
}

#if canImport(UIKit)
/// A region the capture paints over (`feedbackHidden()`), as it sits in the window's UIKit views.
final class HiddenRegionView: UIView {}

struct HiddenRegionMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> HiddenRegionView {
        let view = HiddenRegionView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: HiddenRegionView, context: Context) {}
}
#elseif canImport(AppKit)
/// A region the capture paints over (`feedbackHidden()`), as it sits in the window's AppKit views.
final class HiddenRegionView: NSView {
    // Clicks go to the view it's behind.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct HiddenRegionMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> HiddenRegionView { HiddenRegionView() }

    func updateNSView(_ view: HiddenRegionView, context: Context) {}
}
#endif

extension CaptureRedaction {
    /// What SwiftUI redacts while the screen is captured.
    var reasons: RedactionReasons {
        switch self {
        case .none, .custom: []
        case .privacySensitiveViews: .privacy
        case .allContent: [.placeholder, .privacy]
        }
    }

    /// What the capture paints over of the text UIKit or AppKit draws.
    var systemText: SystemText {
        switch self {
        case .none, .custom: .none
        case .privacySensitiveViews: .typed
        case .allContent: .all
        }
    }
}

/// "Send Feedback…" in the Help menu, on the Mac and on iPad.
public struct FeedbackCommands: Commands {
    let center: FeedbackCenter

    public init(center: FeedbackCenter) {
        self.center = center
    }

    public var body: some Commands {
        CommandGroup(after: .help) {
            Button("Send Feedback…") {
                Task { await center.begin() }
            }
            .disabled(!center.isEnabled)
        }
    }
}

/// A button that opens the form, for a toolbar, a menu or Settings.
public struct FeedbackButton: View {
    let center: FeedbackCenter

    public init(center: FeedbackCenter) {
        self.center = center
    }

    public var body: some View {
        Button {
            Task { await center.begin() }
        } label: {
            Label("Send Feedback", systemImage: "exclamationmark.bubble")
        }
        .disabled(!center.isEnabled)
        .accessibilityIdentifier("feedback.open")
    }
}

/// The feedback settings, for the app's Settings: whether it's on, the gestures, the token and
/// what's waiting to be sent.
public struct FeedbackSettingsSection: View {
    @Bindable var center: FeedbackCenter
    @State private var token = ""

    public init(center: FeedbackCenter) {
        self.center = center
    }

    public var body: some View {
        Section {
            Toggle("Send Feedback from the App", isOn: $center.isEnabled)
                .accessibilityIdentifier("settings.feedback.enabled")
            #if canImport(UIKit)
            Toggle("Shake to Send Feedback", isOn: $center.opensOnShake)
                .disabled(!center.isEnabled)
                .accessibilityIdentifier("settings.feedback.shake")
            Toggle("Offer after a Screenshot", isOn: $center.offersAfterScreenshot)
                .disabled(!center.isEnabled)
                .accessibilityIdentifier("settings.feedback.screenshot")
            #endif

            if center.hasToken {
                LabeledContent("GitHub Token", value: "Saved")
                Button("Remove Token", role: .destructive) { center.removeToken() }
                    .accessibilityIdentifier("settings.feedback.removeToken")
            } else {
                SecureField("GitHub Token", text: $token)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settings.feedback.token")
                Button("Save Token") {
                    center.saveToken(token)
                    token = ""
                }
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("settings.feedback.saveToken")
            }

            if center.pendingCount > 0 {
                LabeledContent("Waiting to Send", value: "\(center.pendingCount)")
                Button("Send Now") {
                    Task { await center.sendPending() }
                }
                .disabled(center.isSending || !center.hasToken)
                .accessibilityIdentifier("settings.feedback.sendNow")
            }
            if let error = center.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            FeedbackButton(center: center)
        } header: {
            Text("Feedback")
        } footer: {
            Text("Reports go to the private GitHub repository \(center.configuration.inbox.description). The token is a fine-grained personal access token with read and write access to its issues and contents.")
        }
        .task { await center.refreshPendingCount() }
    }
}
#endif
