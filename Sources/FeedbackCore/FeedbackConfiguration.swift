import Foundation

/// A repository on GitHub, as `owner/name`.
public struct GitHubRepository: Hashable, Codable, Sendable, CustomStringConvertible {
    public var owner: String
    public var name: String

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    public var description: String { "\(owner)/\(name)" }
}

/// What a report is about. Its `id` becomes the issue's `type:<id>` label.
public struct FeedbackKind: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    /// The name the form shows.
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    public static let bug = FeedbackKind(id: "bug", title: "Bug")
    public static let idea = FeedbackKind(id: "idea", title: "Idea")
    /// About what the app shows (a course, a food database) rather than how it works.
    public static let content = FeedbackKind(id: "content", title: "Content")
}

/// How the screen is captured when the app shows private values.
public enum CaptureRedaction: Sendable, Equatable {
    /// The screen is captured as it is.
    case none
    /// Views marked `privacySensitive()` are redacted while the screen is captured
    /// (FeedbackKit's `feedbackRedaction(_:)` on the root view does it).
    case privacySensitiveViews
    /// The app hides its values itself while `FeedbackCenter.isCapturing` is true.
    case custom
}

/// Where an app's reports go and what its form offers.
public struct FeedbackConfiguration: Sendable {
    /// The repository the issues are filed in. Keep it private: reports carry screenshots.
    public var inbox: GitHubRepository
    /// The app's key in the inbox: the issue's `app:<key>` label and the screenshots' folder.
    public var app: String
    /// The kinds the form offers, the first one preselected.
    public var kinds: [FeedbackKind]
    /// How the screen is captured.
    public var redaction: CaptureRedaction

    public init(
        inbox: GitHubRepository,
        app: String,
        kinds: [FeedbackKind] = [.bug, .idea],
        redaction: CaptureRedaction = .none
    ) {
        self.inbox = inbox
        self.app = app
        self.kinds = kinds.isEmpty ? [.bug] : kinds
        self.redaction = redaction
    }
}
