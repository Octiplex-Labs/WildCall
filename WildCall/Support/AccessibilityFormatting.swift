import Foundation

enum AccessibilityFormatting {
    /// Insère des espaces entre chaque chiffre pour que VoiceOver lise
    /// `+33612345678` comme une suite de chiffres plutôt que comme un
    /// gros nombre ou des morceaux arbitraires.
    static func spelledOut(_ raw: String) -> String {
        raw.map { String($0) }.joined(separator: " ")
    }

    /// Le `OctiplexTrust.fingerprint(of:)` produit `F0:75:1B:D4:92:C1:ED:2A`.
    /// VoiceOver lit déjà les groupes hex correctement grâce aux `:`, mais
    /// on remplace les deux-points par " : " pour forcer une pause claire.
    static func readableFingerprint(_ fingerprint: String) -> String {
        fingerprint.replacingOccurrences(of: ":", with: " : ")
    }
}
