import Foundation

/// Reports waiting to be sent, one folder each: `<id>/report.json` and `<id>/screenshot.png`.
///
/// A report is saved here before anything is sent, so it survives having no network, no token
/// or the app quitting, and is sent the next time the app comes to the front.
public actor FeedbackOutbox {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Saves a report and its screenshot. The screenshot is written first: a folder without
    /// `report.json` is an unfinished save, which `reports()` skips.
    public func add(_ report: FeedbackReport, screenshot: Data?) throws {
        let folder = location(of: report.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let screenshot {
            try screenshot.write(to: folder.appending(path: Self.screenshotFile), options: .atomic)
        }
        try write(report, to: folder)
    }

    /// Saves a changed report, such as one whose screenshot has been uploaded.
    public func update(_ report: FeedbackReport) throws {
        let folder = location(of: report.id)
        guard FileManager.default.fileExists(atPath: folder.appending(path: Self.reportFile).path(percentEncoded: false)) else { return }
        try write(report, to: folder)
    }

    /// The waiting reports, oldest first.
    public func reports() -> [FeedbackReport] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let decoder = JSONDecoder()
        return folders
            .compactMap { folder in
                guard let data = try? Data(contentsOf: folder.appending(path: Self.reportFile)) else { return nil }
                return try? decoder.decode(FeedbackReport.self, from: data)
            }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    public func screenshot(for id: String) -> Data? {
        try? Data(contentsOf: location(of: id).appending(path: Self.screenshotFile))
    }

    /// Removes a report that has been sent, or that its sender gave up on.
    public func remove(_ id: String) throws {
        let folder = location(of: id)
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    static let reportFile = "report.json"
    static let screenshotFile = "screenshot.png"

    private func location(of id: String) -> URL {
        directory.appending(path: IssueComposer.slug(id), directoryHint: .isDirectory)
    }

    private func write(_ report: FeedbackReport, to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: folder.appending(path: Self.reportFile), options: .atomic)
    }
}
