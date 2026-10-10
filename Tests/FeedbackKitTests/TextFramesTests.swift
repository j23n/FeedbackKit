#if canImport(AppKit) && !canImport(UIKit)
import AppKit
import Testing

@testable import FeedbackKit

/// What the Mac's capture paints over. (UIKit's side is the same walk over UIKit's classes.)
@MainActor
struct TextFramesTests {
    private let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    private let title = NSTextField(labelWithString: "Lasagne")
    private let field = NSTextField(string: "two eggs")
    private let hidden = NSTextField(string: "hidden")

    init() {
        title.frame = NSRect(x: 10, y: 160, width: 120, height: 20)
        field.frame = NSRect(x: 10, y: 100, width: 200, height: 24)
        hidden.frame = NSRect(x: 10, y: 40, width: 200, height: 24)
        hidden.isHidden = true
        let group = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        group.addSubview(field)
        root.addSubview(title)
        root.addSubview(group)
        root.addSubview(hidden)
    }

    @Test func nothingWhenTextIsKeptAndNothingIsMarked() {
        #expect(ScreenCapture.maskedFrames(in: root, hiding: .none).isEmpty)
    }

    @Test func typedTextOnly() {
        #expect(ScreenCapture.maskedFrames(in: root, hiding: .typed) == [field.frame])
    }

    @Test func allTextButNotHiddenViews() {
        let frames = ScreenCapture.maskedFrames(in: root, hiding: .all)
        #expect(frames.count == 2)
        #expect(frames.contains(title.frame))
        #expect(frames.contains(field.frame))
    }

    @Test func markedRegionsWhateverTheRedaction() {
        let picker = NSPopUpButton(frame: NSRect(x: 150, y: 10, width: 120, height: 24))
        let marker = HiddenRegionView(frame: picker.frame)
        root.addSubview(marker)
        root.addSubview(picker)
        #expect(ScreenCapture.maskedFrames(in: root, hiding: .none) == [marker.frame])
        #expect(ScreenCapture.maskedFrames(in: root, hiding: .typed).contains(marker.frame))
    }

    @Test func clippedToTheView() {
        title.frame = NSRect(x: 250, y: 160, width: 120, height: 20)
        let frames = ScreenCapture.maskedFrames(in: root, hiding: .all)
        #expect(frames.contains(NSRect(x: 250, y: 160, width: 50, height: 20)))
    }
}
#endif
