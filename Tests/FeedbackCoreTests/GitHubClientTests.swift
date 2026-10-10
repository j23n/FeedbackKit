import Foundation
import Testing
@testable import FeedbackCore

@Suite struct GitHubClientTests {
    func client(_ transport: FakeTransport) -> GitHubClient {
        GitHubClient(repository: Sample.inbox, token: "secret", transport: transport)
    }

    @Test func commitFilePutsTheContentsInBase64() async throws {
        let transport = FakeTransport([.committed("screenshots/a.png")])
        let url = try await client(transport).commitFile(at: "screenshots/a.png", contents: Data("png".utf8), message: "Add it")

        #expect(url.absoluteString == "https://github.com/j23n/feedback/blob/main/screenshots/a.png")
        let request = try #require(transport.requests.first)
        #expect(request.method == "PUT")
        #expect(request.url.absoluteString == "https://api.github.com/repos/j23n/feedback/contents/screenshots/a.png")
        #expect(request.headers["Authorization"] == "Bearer secret")
        #expect(request.headers["X-GitHub-Api-Version"] == "2022-11-28")
        let body = try JSONSerialization.jsonObject(with: try #require(request.body)) as? [String: String]
        #expect(body == ["message": "Add it", "content": Data("png".utf8).base64EncodedString()])
    }

    @Test func aFileAlreadyThereIsLookedUp() async throws {
        let transport = FakeTransport([
            .json(422, #"{"message":"Invalid request.\n\n\"sha\" wasn't supplied."}"#),
            .json(200, #"{"html_url":"https://github.com/j23n/feedback/blob/main/screenshots/a.png"}"#),
        ])
        let url = try await client(transport).commitFile(at: "screenshots/a.png", contents: Data(), message: "Add it")

        #expect(url.absoluteString == "https://github.com/j23n/feedback/blob/main/screenshots/a.png")
        #expect(transport.requests.map(\.method) == ["PUT", "GET"])
    }

    @Test func createIssueSendsTitleBodyAndLabels() async throws {
        let transport = FakeTransport([.issue(12)])
        let issue = try await client(transport).createIssue(title: "T", body: "B", labels: ["feedback"])

        #expect(issue == CreatedIssue(number: 12, url: try #require(URL(string: "https://github.com/j23n/feedback/issues/12"))))
        let request = try #require(transport.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://api.github.com/repos/j23n/feedback/issues")
        let body = try JSONSerialization.jsonObject(with: try #require(request.body)) as? [String: Any]
        #expect(body?["title"] as? String == "T")
        #expect(body?["labels"] as? [String] == ["feedback"])
    }

    @Test func errorsAreNamedByStatus() async {
        await #expect(throws: GitHubError.badToken) {
            try await client(FakeTransport([.json(401, #"{"message":"Bad credentials"}"#)]))
                .createIssue(title: "T", body: "B", labels: [])
        }
        await #expect(throws: GitHubError.notFound) {
            try await client(FakeTransport([.json(404, #"{"message":"Not Found"}"#)]))
                .createIssue(title: "T", body: "B", labels: [])
        }
        await #expect(throws: GitHubError.failed(status: 500, message: "Oops")) {
            try await client(FakeTransport([.json(500, #"{"message":"Oops"}"#)]))
                .createIssue(title: "T", body: "B", labels: [])
        }
    }
}
