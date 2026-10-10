#if canImport(UIKit) || canImport(AppKit)
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The details every report carries: the app's version, the system, the device and the window.
@MainActor
enum DeviceContext {
    static func items(bundle: Bundle = .main) -> [ContextItem] {
        let info = bundle.infoDictionary ?? [:]
        let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "App"
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        var items = [ContextItem(name: "App", value: "\(name) \(version) (\(build))")]
        // A build phase can write the commit into Info.plist under this key.
        if let commit = info["FeedbackGitCommit"] as? String, !commit.isEmpty {
            items.append(ContextItem(name: "Commit", value: commit))
        }

        #if canImport(UIKit)
        let device = UIDevice.current
        items.append(ContextItem(name: "System", value: "\(device.systemName) \(device.systemVersion)"))
        items.append(ContextItem(name: "Device", value: modelIdentifier()))
        if let window = ScreenCapture.appWindow() {
            let traits = window.traitCollection
            items.append(ContextItem(name: "Window", value: size(window.bounds.size)))
            items.append(ContextItem(name: "Appearance", value: traits.userInterfaceStyle == .dark ? "Dark" : "Light"))
            let textSize = traits.preferredContentSizeCategory.rawValue
                .replacingOccurrences(of: "UICTContentSizeCategory", with: "")
            items.append(ContextItem(name: "Text size", value: textSize))
        }
        #elseif canImport(AppKit)
        let system = ProcessInfo.processInfo.operatingSystemVersion
        items.append(ContextItem(
            name: "System",
            value: "macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
        ))
        items.append(ContextItem(name: "Device", value: sysctlString("hw.model") ?? "Mac"))
        if let window = ScreenCapture.appWindow() {
            items.append(ContextItem(name: "Window", value: size(window.frame.size)))
            let dark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            items.append(ContextItem(name: "Appearance", value: dark ? "Dark" : "Light"))
        }
        #endif

        items.append(ContextItem(name: "Locale", value: Locale.current.identifier))
        return items
    }

    private static func size(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))×\(Int(size.height.rounded())) pt"
    }

    #if canImport(UIKit)
    /// Such as `iPhone17,1`; the simulated model in the Simulator.
    private static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        return sysctlString("hw.machine") ?? UIDevice.current.model
    }
    #endif

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
#endif
