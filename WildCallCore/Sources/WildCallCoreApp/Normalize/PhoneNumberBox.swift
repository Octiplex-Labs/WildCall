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

    /// Resolve the country code (e.g. "FR") for a given ISO region.
    /// Returns nil if PhoneNumberKit has no metadata for the region.
    func countryCode(forRegion region: String) -> UInt64? {
        utility.withLock { box in
            guard let metadata = box.metadata(for: region) else { return nil }
            return metadata.countryCode
        }
    }

    /// Given the leading digits of an E.164 number (without `+`), try to
    /// identify the country by matching the first 1/2/3 digits against
    /// PhoneNumberKit's country-code metadata. Returns the canonical ISO
    /// region (e.g. "US" for NANPA code 1) and the integer country code.
    func regionAndCode(forLeadingDigits digits: String) -> (region: String, countryCode: UInt64)? {
        utility.withLock { box in
            for codeLen in 1...3 {
                guard digits.count >= codeLen else { break }
                let prefix = String(digits.prefix(codeLen))
                guard let code = UInt64(prefix) else { continue }
                guard let territories = box.metadata(forCode: code),
                      let main = territories.first
                else { continue }
                return (region: main.codeID, countryCode: code)
            }
            return nil
        }
    }

    /// Maximum national length (in digits) reported by PhoneNumberKit across
    /// all phone-number types for the given ISO region. Returns nil if no
    /// metadata is available for the region or no national lengths are
    /// declared (degenerate case).
    func maxNationalLength(forRegion region: String) -> Int? {
        let allTypes: [PhoneNumberType] = [
            .fixedLine, .mobile, .fixedOrMobile, .pager, .personalNumber,
            .premiumRate, .sharedCost, .tollFree, .voicemail, .voip, .uan
        ]
        return utility.withLock { box in
            allTypes
                .flatMap { box.possiblePhoneNumberLengths(forCountry: region, phoneNumberType: $0, lengthType: .national) }
                .max()
        }
    }
}
