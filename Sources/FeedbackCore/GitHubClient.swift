import Foundation

/// The issue a report became.
public struct CreatedIssue: Hashable, Sendable {
    public var number: Int
    public var url: URL

    public init(number: Int, url: URL) {
        self.number = number
        self.url = url
    }
}

public enum GitHubError: Error, Hashable, LocalizedError {
    /// 401: the token is wrong or expired.
    case badToken
    /// 403: the token may not do this, or the rate limit was hit.
    case forbidden(String)
    /// 404: the repository doesn't exist, or the token can't see it.
    case notFound
    /// Any other answer that isn't a success.
    case failed(status: Int, message: String)
    /// An answer that couldn't be read.
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .badToken:
            "GitHub didn't accept the token. Check it in Settings."
        case .forbidden(let message):
            "GitHub refused the request (\(message)). The token needs read and write access to the inbox's issues and contents."
        case .notFound:
            "GitHub couldn't find the inbox repository with this token."
        case .failed(let status, let message):
            "GitHub answered \(status): \(message)"
        case .invalidResponse:
            "GitHub's answer couldn't be read."
        }
    }

    /// Whether only this report failed, so the ones after it may still go through.
    var concernsOneReport: Bool {
        if case .failed(let status, _) = self { return (400..<500).contains(status) && status != 429 }
        return false
    }
}

/// The two calls FeedbackKit makes to GitHub's REST API.
public struct GitHubClient: Sendable {
    public var repository: GitHubRepository
    public var token: String
    public var transport: any HTTPTransport

    public init(repository: GitHubRepository, token: String, transport: any HTTPTransport) {
        self.repository = repository
        self.token = token
        self.transport = transport
    }

    /// Commits a file to the default branch and returns its page on github.com. A file already at
    /// the path, left by an attempt whose answer was lost, is returned as it is.
    public func commitFile(at path: String, contents: Data, message: String) async throws -> URL {
        struct Body: Encodable {
            let message: String
            let content: String
        }
        let body = try JSONEncoder().encode(Body(message: message, content: contents.base64EncodedString()))
        let response = try await transport.send(request("PUT", "/contents/\(path)", body: body))
        switch response.status {
        case 200, 201:
            struct Answer: Decodable {
                struct Content: Decodable { let html_url: String }
                let content: Content
            }
            return try url(decoding: Answer.self, from: response) { $0.content.html_url }
        case 422:
            // The file exists (GitHub asks for its `sha` to replace it): look it up instead.
            let existing = try await transport.send(request("GET", "/contents/\(path)"))
            guard existing.status == 200 else { throw error(for: response) }
            struct Answer: Decodable { let html_url: String }
            return try url(decoding: Answer.self, from: existing) { $0.html_url }
        default:
            throw error(for: response)
        }
    }

    /// Opens an issue. Labels the repository doesn't have yet are created by GitHub.
    public func createIssue(title: String, body: String, labels: [String]) async throws -> CreatedIssue {
        struct Body: Encodable {
            let title: String
            let body: String
            let labels: [String]
        }
        let encoded = try JSONEncoder().encode(Body(title: title, body: body, labels: labels))
        let response = try await transport.send(request("POST", "/issues", body: encoded))
        guard response.status == 201 else { throw error(for: response) }
        struct Answer: Decodable {
            let number: Int
            let html_url: String
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: response.body),
              let url = URL(string: answer.html_url)
        else { throw GitHubError.invalidResponse }
        return CreatedIssue(number: answer.number, url: url)
    }

    func request(_ method: String, _ path: String, body: Data? = nil) throws -> HTTPRequest {
        guard let url = URL(string: "https://api.github.com/repos/\(repository.owner)/\(repository.name)\(path)") else {
            throw GitHubError.invalidResponse
        }
        var headers = [
            "Accept": "application/vnd.github+json",
            "Authorization": "Bearer \(token)",
            "User-Agent": "FeedbackKit",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
        if body != nil { headers["Content-Type"] = "application/json" }
        return HTTPRequest(method: method, url: url, headers: headers, body: body)
    }

    private func url<Answer: Decodable>(
        decoding type: Answer.Type,
        from response: HTTPResponse,
        _ field: (Answer) -> String
    ) throws -> URL {
        guard let answer = try? JSONDecoder().decode(type, from: response.body),
              let url = URL(string: field(answer))
        else { throw GitHubError.invalidResponse }
        return url
    }

    func error(for response: HTTPResponse) -> GitHubError {
        struct Answer: Decodable { let message: String }
        let message = (try? JSONDecoder().decode(Answer.self, from: response.body))?.message
            ?? String(decoding: response.body.prefix(200), as: UTF8.self)
        switch response.status {
        case 401: return .badToken
        case 403: return .forbidden(message)
        case 404: return .notFound
        default: return .failed(status: response.status, message: message)
        }
    }
}
