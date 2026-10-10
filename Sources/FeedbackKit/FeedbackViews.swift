#if canImport(UIKit) || canImport(AppKit)
import SwiftUI

extension View {
    /// Redacts the views marked `privacySensitive()` while the center captures the screen, when
    /// its configuration's redaction is `.privacySensitiveViews`. Apply it once, to the root view.
    @MainActor
    public func feedbackRedaction(_ center: FeedbackCenter) -> some View {
        redacted(reason: center.configuration.redaction == .privacySensitiveViews && center.isCapturing ? .privacy : [])
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
