# FeedbackKit

In-app feedback for SwiftUI apps on iPhone, iPad and Mac. Shake, take a screenshot or pick Help › Send Feedback…; the app captures its own window (hiding its private values first, if it has any), you mark the screenshot up, write what happened, and the report becomes an issue in a private GitHub repository: the **inbox**. There, a triage workflow refines it and, once you approve it, files it in the app's own repository ([j23n/feedback](https://github.com/j23n/feedback), private).

No third-party code. The only network calls are two GitHub REST calls, with a token you paste into the app's Settings.

## What it does

- **Starting a report**: shake the iPhone or iPad; take a screenshot, and a banner offers to send the screen for a few seconds; Help › Send Feedback… on the Mac and on iPad (`FeedbackCommands`); or a `FeedbackButton` anywhere. Each can be turned off in Settings (`FeedbackSettingsSection`).
- **The capture** draws the app's key window, so it needs no permission: `drawHierarchy` on iOS, `cacheDisplay` on the Mac. On the Mac it captures the key window, which is the sheet when one is open.
- **Hiding values** before the capture (`CaptureRedaction`). Put `.feedbackRedaction(center)` on the root view of each of the app's windows (the main window, Settings, a menu bar extra's window):
  - `.allContent`, for an app whose screens are mostly the user's own data: SwiftUI draws placeholders for all text and images for the capture, and the text UIKit or AppKit draws itself, which SwiftUI's redaction doesn't reach (navigation and window titles, buttons' titles, text fields), is painted over in the screenshot. Only the tab bar's labels stay. Mark a view `.unredacted()` to show it as it is. The screenshot keeps the screen's layout and the app's chrome, and no value, name or word of the user's.
  - `.privacySensitiveViews`: views marked `.privacySensitive()` are redacted for the capture, and what's in text fields is painted over.
  - `.custom`: the app hides its values itself while `center.isCapturing` is true, as an app with a "Hide Amounts" mode already can.
  - Shapes stay: a chart without its labels keeps its lines and bars.
- **Markup** on iPhone and iPad opens the screenshot in Quick Look with the system's Markup tools. (The Mac doesn't offer Markup yet; PaperKit's `MarkupToolbarViewController` is the way to add it.)
- **Details** sent with every report: the app's name, version and build, the commit if the build writes `FeedbackGitCommit` into Info.plist, the system, the device model, the window's size, the appearance, the text size, the locale, the screen (`center.currentScreen`) and whatever `center.additionalContext` adds. The form lists them before you send.
- **The outbox**: a report is saved in `Application Support/FeedbackKit/Outbox` first and sent when it can be: right away, when the app becomes active, or with Send Now in Settings. Without a network or a token, nothing is lost.
- **Sending**: the screenshot is committed to the inbox (`screenshots/<app>/<yyyy-MM>/<id>.png`, since GitHub has no API for issue attachments), then the issue is opened with the labels `feedback`, `app:<app>` and `type:<kind>`, and a first line the inbox's workflows read: `<!-- feedbackkit {"app":…,"id":…,"kind":…,"screenshot":…} -->`.

## Adding it to an app

Add the package (`https://github.com/j23n/feedbackkit`, product `FeedbackKit`) and compile the feedback code only into the builds you use yourself, behind a `FEEDBACK` compilation condition, so App Store builds have no gesture, no token field and no network call:

```swift
#if FEEDBACK
import FeedbackKit
#endif

@main
struct MyApp: App {
    #if FEEDBACK
    @State private var feedback = FeedbackCenter(configuration: FeedbackConfiguration(
        inbox: GitHubRepository(owner: "j23n", name: "feedback"),
        app: "myapp",
        redaction: .privacySensitiveViews
    ))
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                #if FEEDBACK
                .feedbackRedaction(feedback)
                .environment(feedback)
                #endif
        }
        #if FEEDBACK
        .commands { FeedbackCommands(center: feedback) }
        #endif
    }
}
```

And in Settings, `FeedbackSettingsSection(center: feedback)` inside a `Form`.

The token is a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) for the inbox repository only, with **Issues: read and write** and **Contents: read and write**. It's kept in the Keychain, synchronized through iCloud Keychain, so each app asks for it once.

## Development

```sh
swift build
swift test          # FeedbackCore's tests; they run on Linux too
xcodebuild build -scheme FeedbackKit -destination 'generic/platform=iOS Simulator'
```

`FeedbackCore` (reports, outbox, issue text, GitHub client) is Foundation only and tested on Linux and macOS. `FeedbackKit` (capture, gestures, form, settings) is SwiftUI with UIKit or AppKit, and compiles to nothing elsewhere. CI builds both, with warnings as errors, on Linux, the Mac and the iOS Simulator.
