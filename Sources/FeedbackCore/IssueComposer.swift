import Foundation

/// Turns a report into the inbox issue: its title, labels, body and the screenshot's path.
///
/// The body starts with a machine-readable comment the inbox's workflows read:
///
///     <!-- feedbackkit {"app":"caniretireyet","id":"…","kind":"bug","screenshot":"screenshots/…"} -->
public struct IssueComposer: Sendable {
    /// The longest title, in characters.
    public static let titleLength = 80

    public init() {}

    /// `[app] first line of the message`, shortened to `titleLength`.
    public func title(for report: FeedbackReport) -> String {
        let firstLine = report.message
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
        let title = "[\(report.app)] \(firstLine ?? report.kind.title)"
        guard title.count > Self.titleLength else { return title }
        return String(title.prefix(Self.titleLength - 1)) + "…"
    }

    /// `feedback`, `app:<key>` and `type:<kind>`.
    public func labels(for report: FeedbackReport) -> [String] {
        ["feedback", "app:\(Self.slug(report.app))", "type:\(Self.slug(report.kind.id))"]
    }

    /// `screenshots/<app>/<yyyy-MM>/<id>.png`, the month in UTC.
    public func screenshotPath(for report: FeedbackReport) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = calendar.dateComponents([.year, .month], from: report.createdAt)
        let month = "\(Self.padded(parts.year ?? 0, to: 4))-\(Self.padded(parts.month ?? 0, to: 2))"
        return "screenshots/\(Self.slug(report.app))/\(month)/\(Self.slug(report.id)).png"
    }

    /// The issue's Markdown.
    public func body(for report: FeedbackReport) -> String {
        var lines = [metadataComment(for: report), "", "### Report", ""]
        let message = report.message.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(message.isEmpty ? "_No message._" : message)

        if report.hasScreenshot {
            lines += ["", "### Screenshot", ""]
            if let url = report.screenshotURL {
                lines.append("![Screenshot](\(url)?raw=true)")
            } else {
                lines.append("`\(screenshotPath(for: report))`")
            }
            if report.screenshotRedacted {
                lines += ["", "_The app hid its values before the capture._"]
            }
        }

        if !report.context.isEmpty {
            lines += ["", "### Details", "", "| | |", "| --- | --- |"]
            for item in report.context {
                lines.append("| \(Self.tableCell(item.name)) | \(Self.tableCell(item.value)) |")
            }
        }

        lines += ["", "<sub>Sent from the app with FeedbackKit.</sub>", ""]
        return lines.joined(separator: "\n")
    }

    private func metadataComment(for report: FeedbackReport) -> String {
        struct Metadata: Encodable {
            let app: String
            let id: String
            let kind: String
            let screenshot: String?
        }
        let metadata = Metadata(
            app: Self.slug(report.app),
            id: Self.slug(report.id),
            kind: Self.slug(report.kind.id),
            screenshot: report.hasScreenshot ? screenshotPath(for: report) : nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = (try? encoder.encode(metadata)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "<!-- feedbackkit \(json) -->"
    }

    /// Lowercase letters, digits, `-`, `_` and `.`; anything else becomes `-`.
    static func slug(_ text: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_.")
        let slug = String(text.lowercased().map { allowed.contains($0) ? $0 : "-" })
        return slug.isEmpty ? "-" : slug
    }

    static func padded(_ number: Int, to width: Int) -> String {
        let digits = String(number)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    static func tableCell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
    }
}
