import Foundation

/// One line of the details sent with a report, such as the app's version or the screen it was on.
public struct ContextItem: Hashable, Codable, Sendable, Identifiable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }

    public var id: String { name }
}

/// A report as it waits in the outbox and becomes an issue.
public struct FeedbackReport: Hashable, Codable, Sendable, Identifiable {
    /// A lowercase UUID; it names the screenshot's file in the inbox.
    public var id: String
    public var createdAt: Date
    /// The app's key (`FeedbackConfiguration.app`).
    public var app: String
    public var kind: FeedbackKind
    public var message: String
    public var context: [ContextItem]
    /// Whether a screenshot was attached; the outbox keeps it next to the report.
    public var hasScreenshot: Bool
    /// Whether the app hid its values before the screen was captured.
    public var screenshotRedacted: Bool
    /// The screenshot's page in the inbox once it's committed, so a retry doesn't upload it again.
    public var screenshotURL: String?

    public init(
        id: String = UUID().uuidString.lowercased(),
        createdAt: Date,
        app: String,
        kind: FeedbackKind,
        message: String,
        context: [ContextItem] = [],
        hasScreenshot: Bool = false,
        screenshotRedacted: Bool = false,
        screenshotURL: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.app = app
        self.kind = kind
        self.message = message
        self.context = context
        self.hasScreenshot = hasScreenshot
        self.screenshotRedacted = screenshotRedacted
        self.screenshotURL = screenshotURL
    }
}
