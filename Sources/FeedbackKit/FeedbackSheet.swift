#if canImport(UIKit) || canImport(AppKit)
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The form: what kind of feedback, the message, the screenshot and the details sent with it.
struct FeedbackSheet: View {
    let center: FeedbackCenter
    @Bindable var form: FeedbackForm
    let close: @MainActor () -> Void
    @FocusState private var messageFocused: Bool

    var body: some View {
        #if canImport(UIKit)
        NavigationStack {
            fields
                .navigationTitle("Send Feedback")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { cancelButton }
                    ToolbarItem(placement: .confirmationAction) { sendButton }
                }
        }
        #else
        VStack(spacing: 0) {
            Text("Send Feedback")
                .font(.headline)
                .padding(.top, 16)
            fields
            Divider()
            HStack {
                Spacer()
                cancelButton.keyboardShortcut(.cancelAction)
                sendButton.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 520, idealHeight: 680)
        #endif
    }

    private var fields: some View {
        Form {
            Section {
                Picker("Kind", selection: $form.kind) {
                    ForEach(center.configuration.kinds) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("feedback.kind")

                TextField("What happened, or what would you like?", text: $form.message, axis: .vertical)
                    .lineLimit(4...12)
                    .focused($messageFocused)
                    .accessibilityLabel("Message")
                    .accessibilityIdentifier("feedback.message")
            }

            if let screenshot = form.screenshot {
                screenshotSection(screenshot)
            }

            Section("Sent with it") {
                ForEach(form.context) { item in
                    LabeledContent(item.name, value: item.value)
                }
            }

            if !center.hasToken {
                Section {
                    Text("There's no GitHub token on this device yet. The report waits here until you add one in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let error = form.error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { messageFocused = true }
    }

    private func screenshotSection(_ screenshot: Data) -> some View {
        Section {
            Toggle("Include the screenshot", isOn: $form.includesScreenshot)
                .accessibilityIdentifier("feedback.includeScreenshot")
            if form.includesScreenshot {
                ScreenshotImage(data: screenshot)
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .accessibilityLabel("Screenshot")
                #if canImport(UIKit)
                Button {
                    MarkupController.present(screenshot) { [form] edited in form.screenshot = edited }
                } label: {
                    Label("Mark Up", systemImage: "pencil.tip.crop.circle")
                }
                .accessibilityIdentifier("feedback.markUp")
                #endif
            }
        } header: {
            Text("Screenshot")
        } footer: {
            if form.screenshotRedacted {
                Text(redactionNote)
            }
        }
    }

    private var redactionNote: String {
        #if canImport(UIKit)
        "The app hid its values before the capture. Mark up the screenshot to cover anything else."
        #else
        "The app hid its values before the capture."
        #endif
    }

    private var cancelButton: some View {
        Button("Cancel", role: .cancel) { close() }
            .accessibilityIdentifier("feedback.cancel")
    }

    private var sendButton: some View {
        Button("Send") {
            Task {
                form.isSending = true
                form.error = nil
                if await center.submit(form) {
                    close()
                } else {
                    form.error = center.lastError
                    form.isSending = false
                }
            }
        }
        .disabled(form.isSending || form.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("feedback.send")
    }
}

/// A PNG, fitted to the space it's given.
struct ScreenshotImage: View {
    let data: Data

    var body: some View {
        #if canImport(UIKit)
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit()
        }
        #elseif canImport(AppKit)
        if let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit()
        }
        #endif
    }
}
#endif
