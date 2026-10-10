@.apple-ci/claude/j23n.md

# FeedbackKit

In-app feedback for the j23n apps; the README says what it does and how apps use it. The inbox it files into, with its triage and publishing workflows, is the private repository j23n/feedback.

## Rules

- No third-party dependencies. `FeedbackCore` imports Foundation only (and FoundationNetworking on Linux) and must build and test on Linux; everything Apple-only lives in `FeedbackKit`, each file wrapped in `#if canImport(UIKit) || canImport(AppKit)`.
- Swift 6 language mode with complete strict concurrency; no warnings (CI builds with warnings as errors). No force unwraps outside tests.
- Swift Testing (`@Test`, `#expect`). Network calls go through `HTTPTransport`, faked in tests; tests never touch the network.
- The issue format (`IssueComposer`, the `<!-- feedbackkit {…} -->` first line, the labels, the screenshot path) is a contract with j23n/feedback's workflows: change both together.
- Every interactive element has an accessibility identifier (`feedback.*`, `settings.feedback.*`) and a label.
- The apps compile FeedbackKit only into builds with the `FEEDBACK` condition; nothing here may assume it ships to the App Store.
- `.apple-ci/claude/` holds copies of j23n/apple-ci's shared Claude rules (imported above) and `link-pr.sh`; refresh them with `curl -fsSL https://raw.githubusercontent.com/j23n/apple-ci/main/claude/update.sh | sh`, never by hand.

## Commands

```sh
swift build && swift test
xcodebuild build -scheme FeedbackKit -destination 'generic/platform=iOS Simulator'
```
