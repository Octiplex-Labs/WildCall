import Dependencies
import Foundation

/// The region the iPhone is set to (Réglages → Général → Langue et région),
/// as an ISO 3166-1 alpha-2 code. No location permission involved.
public struct DeviceRegion: Sendable {
    public var code: @Sendable () -> String?

    public init(code: @escaping @Sendable () -> String?) {
        self.code = code
    }
}

extension DeviceRegion: DependencyKey {
    public static let liveValue = DeviceRegion { Locale.current.region?.identifier }
    /// Tests run as a French device unless they say otherwise, so the
    /// suites written around `fr.arcep` keep installing it enabled.
    public static let testValue = DeviceRegion { "FR" }
}

extension DependencyValues {
    public var deviceRegion: DeviceRegion {
        get { self[DeviceRegion.self] }
        set { self[DeviceRegion.self] = newValue }
    }
}

/// Decides which packs a fresh install switches on.
///
/// Every pack ships in the app, but the four extensions hold 7 999 996
/// numbers in total and `fr.arcep` alone takes 7.35 M of them. Enabling
/// every country would leave no room for the user's own rules, so only the
/// packs of the device's country start enabled. The others stay installed
/// and one toggle away in Réglages.
public enum DefaultPackPolicy {
    /// Regions whose numbers belong to another country's packs : the French
    /// overseas territories are covered by the `FR` packs.
    static let homeCountryByRegion: [String: String] = [
        "GP": "FR", "MQ": "FR", "GF": "FR", "RE": "FR", "YT": "FR",
        "BL": "FR", "MF": "FR", "PM": "FR",
    ]

    /// The pack country that serves `region`, uppercased.
    public static func homeCountry(for region: String?) -> String? {
        guard let region = region?.uppercased(), !region.isEmpty else { return nil }
        return homeCountryByRegion[region] ?? region
    }

    public static func isHomePack(country: String, region: String?) -> Bool {
        guard let home = homeCountry(for: region) else { return false }
        return country.uppercased() == home
    }

    /// Whether a pack installed for the first time starts enabled. A manifest
    /// that sets `enabledByDefault` to false is never switched on for the
    /// user, whatever the region. An unknown region enables nothing.
    public static func enablesOnFreshInstall(_ manifest: PackManifest, region: String?) -> Bool {
        guard manifest.enabledByDefault ?? true else { return false }
        return isHomePack(country: manifest.country, region: region)
    }
}
