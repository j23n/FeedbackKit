import Foundation
import Testing
@testable import FeedbackCore

@Suite struct FeedbackOutboxTests {
    @Test func reportsComeBackOldestFirstWithTheirScreenshots() async throws {
        let outbox = FeedbackOutbox(directory: Sample.temporaryDirectory())
        let newer = Sample.report(id: "b", createdAt: Sample.date.addingTimeInterval(60))
        let older = Sample.report(id: "a", hasScreenshot: true)
        try await outbox.add(newer, screenshot: nil)
        try await outbox.add(older, screenshot: Data("png".utf8))

        #expect(await outbox.reports() == [older, newer])
        #expect(await outbox.screenshot(for: "a") == Data("png".utf8))
        #expect(await outbox.screenshot(for: "b") == nil)

        try await outbox.remove("a")
        #expect(await outbox.reports() == [newer])
        try await outbox.remove("a")  // already gone: no error
    }

    @Test func updateDoesNotRecreateARemovedReport() async throws {
        let outbox = FeedbackOutbox(directory: Sample.temporaryDirectory())
        var report = Sample.report()
        try await outbox.add(report, screenshot: nil)
        try await outbox.remove(report.id)
        report.screenshotURL = "https://example.com"
        try await outbox.update(report)
        #expect(await outbox.reports().isEmpty)
    }

    @Test func aMissingDirectoryIsAnEmptyOutbox() async {
        #expect(await FeedbackOutbox(directory: Sample.temporaryDirectory()).reports().isEmpty)
    }
}

@Suite struct FeedbackSenderTests {
    @Test func sendsTheScreenshotThenTheIssueAndEmptiesTheOutbox() async throws {
        let outbox = FeedbackOutbox(directory: Sample.temporaryDirectory())
        let report = Sample.report(hasScreenshot: true)
        try await outbox.add(report, screenshot: Data("png".utf8))
        let path = IssueComposer().screenshotPath(for: report)
        let transport = FakeTransport([.committed(path), .issue(3)])

        let result = await FeedbackSender(outbox: outbox, client: client(transport)).sendAll()

        #expect(result.sent.map(\.number) == [3])
        #expect(result.error == nil)
        #expect(await outbox.reports().isEmpty)
        #expect(transport.requests.map(\.method) == ["PUT", "POST"])
        let issue = try JSONSerialization.jsonObject(with: try #require(transport.requests[1].body)) as? [String: Any]
        #expect((issue?["body"] as? String)?.contains("![Screenshot](https://github.com/j23n/feedback/blob/main/\(path)?raw=true)") == true)
    }

    @Test func aFailedIssueKeepsTheReportAndItsUploadedScreenshot() async throws {
        let outbox = FeedbackOutbox(directory: Sample.temporaryDirectory())
        let report = Sample.report(hasScreenshot: true)
        try await outbox.add(report, screenshot: Data("png".utf8))
        let path = IssueComposer().screenshotPath(for: report)

        // The screenshot goes up, then the network goes away.
        let first = await FeedbackSender(outbox: outbox, client: client(FakeTransport([.committed(path)]))).sendAll()
        #expect(first.sent.isEmpty)
        #expect(first.error is FakeTransport.Offline)
        let waiting = try #require(await outbox.reports().first)
        #expect(waiting.screenshotURL == "https://github.com/j23n/feedback/blob/main/\(path)")

        // The retry doesn't upload the screenshot again.
        let transport = FakeTransport([.issue(4)])
        let second = await FeedbackSender(outbox: outbox, client: client(transport)).sendAll()
        #expect(second.sent.map(\.number) == [4])
        #expect(transport.requests.map(\.method) == ["POST"])
    }

    @Test func aBadTokenStopsAtTheFirstReport() async throws {
        let outbox = FeedbackOutbox(directory: Sample.temporaryDirectory())
        try await outbox.add(Sample.report(id: "a"), screenshot: nil)
        try await outbox.add(Sample.report(id: "b", createdAt: Sample.date.addingTimeInterval(1)), screenshot: nil)
        let transport = FakeTransport([.json(401, #"{"message":"Bad credentials"}"#)])

        let result = await FeedbackSender(outbox: outbox, client: client(transport)).sendAll()

        #expect(result.error as? GitHubError == .badToken)
        #expect(transport.requests.count == 1)
        #expect(await outbox.reports().count == 2)
    }

    @Test func aReportGitHubRejectsDoesNotHoldUpTheOthers() async throws {
        let outbox = FeedbackOutbox(directory: Sample.temporaryDirectory())
        try await outbox.add(Sample.report(id: "a"), screenshot: nil)
        try await outbox.add(Sample.report(id: "b", createdAt: Sample.date.addingTimeInterval(1)), screenshot: nil)
        let transport = FakeTransport([.json(422, #"{"message":"Validation Failed"}"#), .issue(5)])

        let result = await FeedbackSender(outbox: outbox, client: client(transport)).sendAll()

        #expect(result.sent.map(\.number) == [5])
        #expect(result.error as? GitHubError == .failed(status: 422, message: "Validation Failed"))
        #expect(await outbox.reports().map(\.id) == ["a"])
    }

    func client(_ transport: FakeTransport) -> GitHubClient {
        GitHubClient(repository: Sample.inbox, token: "secret", transport: transport)
    }
}
