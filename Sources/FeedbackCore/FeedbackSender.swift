import Foundation

/// Sends the outbox's reports to the inbox, oldest first: the screenshot is committed, then the
/// issue opened, then the report removed from the outbox.
public struct FeedbackSender: Sendable {
    public struct Result: Sendable {
        /// The issues opened, in order.
        public var sent: [CreatedIssue]
        /// The last error, if any report is still waiting because of it.
        public var error: (any Error)?
    }

    public var outbox: FeedbackOutbox
    public var client: GitHubClient
    public var composer: IssueComposer

    public init(outbox: FeedbackOutbox, client: GitHubClient, composer: IssueComposer = IssueComposer()) {
        self.outbox = outbox
        self.client = client
        self.composer = composer
    }

    /// Sends every waiting report. It stops at the first error that would fail the rest too (no
    /// network, a bad token) and skips past one that only concerns its own report, which stays
    /// in the outbox.
    public func sendAll() async -> Result {
        var sent: [CreatedIssue] = []
        var lastError: (any Error)?
        for var report in await outbox.reports() {
            do {
                if report.hasScreenshot, report.screenshotURL == nil {
                    if let screenshot = await outbox.screenshot(for: report.id) {
                        let url = try await client.commitFile(
                            at: composer.screenshotPath(for: report),
                            contents: screenshot,
                            message: "Add the screenshot of feedback \(report.id)"
                        )
                        report.screenshotURL = url.absoluteString
                        try await outbox.update(report)
                    } else {
                        report.hasScreenshot = false
                    }
                }
                let issue = try await client.createIssue(
                    title: composer.title(for: report),
                    body: composer.body(for: report),
                    labels: composer.labels(for: report)
                )
                try await outbox.remove(report.id)
                sent.append(issue)
            } catch let error as GitHubError where error.concernsOneReport {
                lastError = error
            } catch {
                return Result(sent: sent, error: error)
            }
        }
        return Result(sent: sent, error: lastError)
    }
}
