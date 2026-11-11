#if DEBUG
import Dependencies
import Foundation
import WildCallCoreApp
import WildCallCoreShared

/// Demo state for the App Store screenshots (`Tools/screenshots/capture.sh`).
/// Debug builds only, switched on by the `-WildCallScreenshots` launch
/// argument : the real packs are installed in memory, the extensions are
/// reported as enabled (the simulator cannot enable them) and a few
/// personal rules are added.
enum ScreenshotFixtures {
    static let launchArgument = "-WildCallScreenshots"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func apply(to values: inout DependencyValues) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "wildcall-screenshots", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        values.sharedContainer = .ephemeral(root: root)
        values.extensionReloader = ExtensionReloader(
            reload: { _ in },
            getEnabledStatus: { _ in .enabled }
        )
    }

    /// Numbers from ranges set aside for fiction, so no screenshot shows a
    /// real subscriber : 01 99 00 in France, 555-01xx in the United States.
    static func seed(_ rules: RulesRepository) async {
        let now = Date()
        let samples: [BlockRule?] = [
            BlockRule(
                kind: .prefix(E164Prefix(fixedDigits: "3319900", wildcardLength: 4)),
                source: .user, action: .block, countryCode: "FR",
                createdAt: now
            ),
            BlockRule(
                kind: .prefix(E164Prefix(fixedDigits: "120255501", wildcardLength: 2)),
                source: .user, action: .block, countryCode: "US",
                createdAt: now.addingTimeInterval(-60)
            ),
            E164(33_199_001_234).map {
                BlockRule(
                    kind: .exact($0),
                    source: .user, action: .identify, countryCode: "FR",
                    label: "Assurance", createdAt: now.addingTimeInterval(-120)
                )
            },
        ].compactMap(\.self)
        for rule in samples {
            try? await rules.insert(rule)
        }
    }
}
#endif
