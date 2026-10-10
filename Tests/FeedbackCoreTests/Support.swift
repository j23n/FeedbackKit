import Foundation
import FeedbackCore

/// Answers requests from a script of responses and records them.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    struct Offline: Error {}

    private let lock = NSLock()
    private var responses: [HTTPResponse]
    private var recorded: [HTTPRequest] = []

    init(_ responses: [HTTPResponse]) {
        self.responses = responses
    }

    var requests: [HTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        guard !responses.isEmpty else { throw Offline() }
        return responses.removeFirst()
    }
}

extension HTTPResponse {
    static func json(_ status: Int, _ text: String) -> HTTPResponse {
        HTTPResponse(status: status, body: Data(text.utf8))
    }

    static func committed(_ path: String) -> HTTPResponse {
        .json(201, #"{"content":{"html_url":"https://github.com/j23n/feedback/blob/main/\#(path)"}}"#)
    }

    static func issue(_ number: Int) -> HTTPResponse {
        .json(201, #"{"number":\#(number),"html_url":"https://github.com/j23n/feedback/issues/\#(number)"}"#)
    }
}

enum Sample {
    static let inbox = GitHubRepository(owner: "j23n", name: "feedback")

    /// 10 October 2026, 12:00 UTC.
    static let date = Date(timeIntervalSince1970: 1_791_633_600)

    static func report(
        id: String = "6f1c2a9e-0000-4000-8000-000000000001",
        message: String = "The chart overlaps the legend\nOn the plan screen.",
        hasScreenshot: Bool = false,
        createdAt: Date = date
    ) -> FeedbackReport {
        FeedbackReport(
            id: id,
            createdAt: createdAt,
            app: "caniretireyet",
            kind: .bug,
            message: message,
            context: [ContextItem(name: "App", value: "Can I Retire Yet 1.0 (7)")],
            hasScreenshot: hasScreenshot,
            screenshotRedacted: hasScreenshot
        )
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "FeedbackCoreTests-\(UUID().uuidString)")
    }
}
