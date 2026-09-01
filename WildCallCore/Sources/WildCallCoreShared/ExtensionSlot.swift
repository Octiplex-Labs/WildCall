import Foundation

/// One Call Directory extension. iOS caps every extension at 1 999 999
/// entries (measured 2026-09-01), so WildCall ships several identical
/// extensions and spreads the ranges across them. Each slot appears as its
/// own toggle in Réglages → Téléphone → Blocage et identification d'appel,
/// and reads its own pair of files in the App Group.
public struct ExtensionSlot: Hashable, Sendable, Codable, Identifiable, Comparable {
    /// 1-based, stable : slot 1 keeps the original bundle identifier so
    /// existing installs stay enabled.
    public let index: Int

    public init(_ index: Int) {
        precondition(index >= 1, "slots are 1-based")
        self.index = index
    }

    public var id: Int { index }

    public static let count = 4
    public static let all: [ExtensionSlot] = (1...count).map(ExtensionSlot.init)

    public static let bundleIdentifierPrefix = "com.octiplex.wildcall.directory"

    public var bundleIdentifier: String {
        index == 1 ? Self.bundleIdentifierPrefix : "\(Self.bundleIdentifierPrefix)\(index)"
    }

    /// Matches CFBundleDisplayName of the extension target, which is what
    /// Réglages shows next to the toggle.
    public var displayName: String { "WildCall \(index)" }

    public var blockFileName: String { "block-\(index).bin" }
    public var identFileName: String { "ident-\(index).bin" }
    public var extensionRunFileName: String { "extension-run-\(index).json" }

    /// Info.plist key carrying the slot index inside each extension bundle.
    public static let infoPlistKey = "WildCallSlot"

    /// Resolves the slot of the running extension from its Info.plist.
    public static func current(bundle: Bundle = .main) -> ExtensionSlot {
        if let raw = bundle.object(forInfoDictionaryKey: infoPlistKey) {
            if let value = raw as? Int, value >= 1 { return ExtensionSlot(value) }
            if let text = raw as? String, let value = Int(text), value >= 1 { return ExtensionSlot(value) }
        }
        return ExtensionSlot(1)
    }

    public static func < (lhs: ExtensionSlot, rhs: ExtensionSlot) -> Bool { lhs.index < rhs.index }
}
