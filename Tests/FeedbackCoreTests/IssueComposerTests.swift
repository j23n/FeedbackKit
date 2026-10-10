import Foundation
import Testing
@testable import FeedbackCore

@Suite struct IssueComposerTests {
    let composer = IssueComposer()

    @Test func titleIsTheAppAndTheMessagesFirstLine() {
        #expect(composer.title(for: Sample.report()) == "[caniretireyet] The chart overlaps the legend")
    }

    @Test func titleSkipsBlankLinesAndFallsBackToTheKind() {
        #expect(composer.title(for: Sample.report(message: "\n   \nSecond line")) == "[caniretireyet] Second line")
        #expect(composer.title(for: Sample.report(message: "  ")) == "[caniretireyet] Bug")
    }

    @Test func longTitlesAreShortened() {
        let title = composer.title(for: Sample.report(message: String(repeating: "a", count: 200)))
        #expect(title.count == IssueComposer.titleLength)
        #expect(title.hasSuffix("…"))
    }

    @Test func labelsNameTheAppAndTheKind() {
        #expect(composer.labels(for: Sample.report()) == ["feedback", "app:caniretireyet", "type:bug"])
    }

    @Test func screenshotPathIsByAppAndMonthInUTC() {
        #expect(composer.screenshotPath(for: Sample.report())
            == "screenshots/caniretireyet/2026-10/6f1c2a9e-0000-4000-8000-000000000001.png")
        // 1 November 2026, 00:30 in Berlin is still October in UTC.
        let lateOctober = Date(timeIntervalSince1970: 1_793_489_400)
        #expect(composer.screenshotPath(for: Sample.report(createdAt: lateOctober)).contains("/2026-10/"))
    }

    @Test func bodyStartsWithTheMetadataTheInboxReads() {
        var report = Sample.report(hasScreenshot: true)
        report.screenshotURL = "https://github.com/j23n/feedback/blob/main/screenshots/x.png"
        let body = composer.body(for: report)
        let firstLine = body.split(separator: "\n").first.map(String.init)
        #expect(firstLine == #"<!-- feedbackkit {"app":"caniretireyet","id":"6f1c2a9e-0000-4000-8000-000000000001","kind":"bug","screenshot":"screenshots/caniretireyet/2026-10/6f1c2a9e-0000-4000-8000-000000000001.png"} -->"#)
        #expect(body.contains("### Report\n\nThe chart overlaps the legend\nOn the plan screen."))
        #expect(body.contains("![Screenshot](https://github.com/j23n/feedback/blob/main/screenshots/x.png?raw=true)"))
        #expect(body.contains("_The app hid its values before the capture._"))
        #expect(body.contains("| App | Can I Retire Yet 1.0 (7) |"))
    }

    @Test func bodyWithoutAScreenshotHasNoScreenshotSection() {
        let body = composer.body(for: Sample.report())
        #expect(!body.contains("### Screenshot"))
        #expect(body.contains(#""screenshot""#) == false)
    }

    @Test func tableCellsEscapePipesAndJoinLines() {
        #expect(IssueComposer.tableCell("a | b\nc") == #"a \| b c"#)
    }

    @Test func slugsKeepOnlySafeCharacters() {
        #expect(IssueComposer.slug("Can I/Retire") == "can-i-retire")
        #expect(IssueComposer.slug("") == "-")
    }
}
