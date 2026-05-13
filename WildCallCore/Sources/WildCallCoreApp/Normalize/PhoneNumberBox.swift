import Foundation
import PhoneNumberKit
import Synchronization

// PhoneNumberUtility's metadata is loaded once at init and read-only after,
// but the class is not annotated Sendable. We serialize access through a
// Mutex (iOS 18+ Synchronization) and expose a Sendable wrapper.
//
// Shared between PhoneNormalizer (E.164 normalization) and WildcardParser
// (national-length lookup). A single instance avoids loading the
// PhoneNumberKit metadata multiple times.
final class PhoneNumberBox: Sendable {
    private let utility = Mutex(PhoneNumberUtility())

    func parse(_ raw: String, region: String) throws -> PhoneNumber {
        try utility.withLock { try $0.parse(raw, withRegion: region, ignoreType: true) }
    }

    func isValid(_ raw: String, region: String) -> Bool {
        utility.withLock { (try? $0.parse(raw, withRegion: region, ignoreType: true)) != nil }
    }

    func e164(_ number: PhoneNumber) -> String {
        utility.withLock { $0.format(number, toType: .e164) }
    }
}
