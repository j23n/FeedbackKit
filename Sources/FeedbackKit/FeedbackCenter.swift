#if canImport(UIKit) || canImport(AppKit)
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Feedback in one app: what starts a report, the capture, the form and sending.
///
/// Create one when the app starts, keep it for the app's lifetime and hand it to
/// `feedbackRedaction(_:)`, `FeedbackCommands` and `FeedbackSettingsSection`:
///
///     let feedback = FeedbackCenter(configuration: FeedbackConfiguration(
///         inbox: GitHubRepository(owner: "j23n", name: "feedback"),
///         app: "omnomnom",
///         redaction: .privacySensitiveViews
///     ))
///
/// On iPhone and iPad a shake opens the form, and taking a screenshot offers to. Reports wait
/// in an outbox in Application Support until GitHub has them, and the center sends what's
/// waiting each time the app becomes active.
@MainActor
@Observable
public final class FeedbackCenter {
    public let configuration: FeedbackConfiguration

    /// Whether anything starts a report: the gestures, the menu command, `FeedbackButton`.
    public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }

    /// Whether shaking the iPhone or iPad opens the form.
    public var opensOnShake: Bool {
        didSet { defaults.set(opensOnShake, forKey: Keys.shake) }
    }

    /// Whether taking a screenshot on iPhone or iPad offers to send feedback.
    public var offersAfterScreenshot: Bool {
        didSet { defaults.set(offersAfterScreenshot, forKey: Keys.screenshot) }
    }

    /// True for the moment the screen is captured. An app with `.custom` redaction hides its
    /// values while it is.
    public private(set) var isCapturing = false
    /// Whether the form is open.
    public private(set) var isPresenting = false
    public private(set) var isSending = false
    /// Reports in the outbox.
    public private(set) var pendingCount = 0
    /// Why the last attempt to save or send failed, until one succeeds.
    public private(set) var lastError: String? = nil
    /// The last issue opened.
    public private(set) var lastSentIssue: URL? = nil
    public private(set) var hasToken: Bool

    /// The screen the app is on, such as `plan.chart` or a lesson's ID; sent with the report.
    @ObservationIgnored public var currentScreen: @MainActor () -> String? = { nil }
    /// More details to send with each report.
    @ObservationIgnored public var additionalContext: @MainActor () -> [ContextItem] = { [] }

    @ObservationIgnored private let outbox: FeedbackOutbox
    @ObservationIgnored private let tokenStore: any TokenStore
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    #if canImport(UIKit)
    @ObservationIgnored private var screenshotOffer: ScreenshotOffer? = nil
    #endif

    /// - Parameters:
    ///   - tokenStore: The Keychain by default, under the inbox's name.
    ///   - outboxDirectory: `Application Support/FeedbackKit/Outbox` by default.
    ///   - transport: `URLSession` by default.
    public init(
        configuration: FeedbackConfiguration,
        tokenStore: (any TokenStore)? = nil,
        outboxDirectory: URL? = nil,
        transport: (any HTTPTransport)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.configuration = configuration
        let tokenStore = tokenStore ?? KeychainTokenStore(account: configuration.inbox.description)
        self.tokenStore = tokenStore
        self.transport = transport ?? URLSessionTransport()
        self.defaults = defaults
        outbox = FeedbackOutbox(directory: outboxDirectory
            ?? URL.applicationSupportDirectory.appending(path: "FeedbackKit/Outbox", directoryHint: .isDirectory))
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        opensOnShake = defaults.object(forKey: Keys.shake) as? Bool ?? true
        offersAfterScreenshot = defaults.object(forKey: Keys.screenshot) as? Bool ?? true
        hasToken = !(tokenStore.token() ?? "").isEmpty
        observe()
    }

    // MARK: Reporting

    /// Captures the screen and opens the form. The app's values are hidden for the capture when
    /// the configuration asks for it.
    public func begin() async {
        guard isEnabled, !isPresenting else { return }
        isPresenting = true
        #if canImport(UIKit)
        screenshotOffer?.dismiss()
        screenshotOffer = nil
        #endif

        let redacts = configuration.redaction != .none
        if redacts { setCapturing(true) }
        // Lets SwiftUI draw the hidden values, and a menu or banner close, before the capture.
        try? await Task.sleep(for: .milliseconds(redacts ? 150 : 50))
        let screenshot = ScreenCapture.capture(hiding: configuration.redaction.systemText)
        if redacts { setCapturing(false) }

        let form = FeedbackForm(
            kind: configuration.kinds.first ?? .bug,
            screenshot: screenshot,
            screenshotRedacted: redacts && screenshot != nil,
            context: collectContext()
        )
        FeedbackPresenter.present(title: "Send Feedback", onDismiss: { [weak self] in
            self?.isPresenting = false
        }) { close in
            FeedbackSheet(center: self, form: form, close: close)
        }
    }

    /// Saves the report in the outbox and sends what's waiting. Returns whether it was saved.
    func submit(_ form: FeedbackForm) async -> Bool {
        let includesScreenshot = form.includesScreenshot && form.screenshot != nil
        let report = FeedbackReport(
            id: form.id,
            createdAt: .now,
            app: configuration.app,
            kind: form.kind,
            message: form.message.trimmingCharacters(in: .whitespacesAndNewlines),
            context: form.context,
            hasScreenshot: includesScreenshot,
            screenshotRedacted: includesScreenshot && form.screenshotRedacted
        )
        do {
            try await outbox.add(report, screenshot: includesScreenshot ? form.screenshot : nil)
        } catch {
            lastError = "The report couldn't be saved: \(error.localizedDescription)"
            return false
        }
        await refreshPendingCount()
        Task { await sendPending() }
        return true
    }

    /// Sends the reports in the outbox, if there's a token.
    public func sendPending() async {
        guard !isSending else { return }
        await refreshPendingCount()
        guard pendingCount > 0 else { return }
        guard let token = tokenStore.token(), !token.isEmpty else {
            lastError = "Add a GitHub token in Settings to send the reports waiting on this device."
            return
        }
        isSending = true
        defer { isSending = false }
        let client = GitHubClient(repository: configuration.inbox, token: token, transport: transport)
        let result = await FeedbackSender(outbox: outbox, client: client).sendAll()
        if let issue = result.sent.last { lastSentIssue = issue.url }
        lastError = result.error.map { "Not sent yet: \($0.localizedDescription)" }
        await refreshPendingCount()
    }

    public func refreshPendingCount() async {
        pendingCount = await outbox.reports().count
    }

    // MARK: Token

    /// Saves the token (a fine-grained personal access token that can read and write the inbox's
    /// issues and contents) and sends what's waiting.
    public func saveToken(_ token: String) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try tokenStore.setToken(token.isEmpty ? nil : token)
            hasToken = !token.isEmpty
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        Task { await sendPending() }
    }

    public func removeToken() {
        try? tokenStore.setToken(nil)
        hasToken = !(tokenStore.token() ?? "").isEmpty
    }

    // MARK: Private

    private func setCapturing(_ capturing: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isCapturing = capturing }
    }

    private func collectContext() -> [ContextItem] {
        var items = DeviceContext.items()
        if let screen = currentScreen() {
            items.append(ContextItem(name: "Screen", value: screen))
        }
        return items + additionalContext()
    }

    private func observe() {
        let center = NotificationCenter.default
        #if canImport(UIKit)
        let didBecomeActive = UIApplication.didBecomeActiveNotification
        observers.append(center.addObserver(forName: .feedbackDeviceDidShake, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.shaken() }
        })
        observers.append(center.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenshotTaken() }
        })
        #elseif canImport(AppKit)
        let didBecomeActive = NSApplication.didBecomeActiveNotification
        #endif
        observers.append(center.addObserver(forName: didBecomeActive, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.sendPending() }
            }
        })
    }

    #if canImport(UIKit)
    private func shaken() {
        guard isEnabled, opensOnShake else { return }
        Task { await begin() }
    }

    private func screenshotTaken() {
        guard isEnabled, offersAfterScreenshot, !isPresenting else { return }
        screenshotOffer?.dismiss()
        screenshotOffer = ScreenshotOffer.show { [weak self] in
            guard let self else { return }
            Task { await self.begin() }
        }
    }
    #endif

    private enum Keys {
        static let enabled = "FeedbackKit.enabled"
        static let shake = "FeedbackKit.opensOnShake"
        static let screenshot = "FeedbackKit.offersAfterScreenshot"
    }
}

/// What the form edits.
@MainActor
@Observable
final class FeedbackForm {
    let id = UUID().uuidString.lowercased()
    var kind: FeedbackKind
    var message = ""
    var screenshot: Data?
    var includesScreenshot: Bool
    let screenshotRedacted: Bool
    let context: [ContextItem]
    var isSending = false
    var error: String? = nil

    init(kind: FeedbackKind, screenshot: Data?, screenshotRedacted: Bool, context: [ContextItem]) {
        self.kind = kind
        self.screenshot = screenshot
        includesScreenshot = screenshot != nil
        self.screenshotRedacted = screenshotRedacted
        self.context = context
    }
}
#endif
