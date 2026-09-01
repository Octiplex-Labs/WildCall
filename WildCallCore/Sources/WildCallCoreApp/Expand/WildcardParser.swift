import Dependencies
import Foundation

public enum ParseError: Error, Equatable, Sendable {
    case empty
    case missingWildcard
    case wildcardNotTrailing
    case unparseable
    case unknownNationalLength(country: String)
    case fixedTooShort(minimum: Int)
    case fixedTooLong(maximum: Int)
    case exceedsPerPatternQuota(expanded: Int, limit: Int)
}

public struct WildcardParser: Sendable {
    public var parse: @Sendable (_ raw: String, _ defaultRegion: String) -> Result<E164Prefix, ParseError>

    public init(parse: @escaping @Sendable (String, String) -> Result<E164Prefix, ParseError>) {
        self.parse = parse
    }
}

extension WildcardParser {
    public static let live: WildcardParser = {
        let box = PhoneNumberBox()
        return WildcardParser { raw, defaultRegion in
            @Dependency(\.wildcardQuotas) var quotas
            return Self.parse(raw: raw, defaultRegion: defaultRegion, box: box, quotas: quotas)
        }
    }()

    static func parse(
        raw: String,
        defaultRegion: String,
        box: PhoneNumberBox,
        quotas: WildcardQuotas
    ) -> Result<E164Prefix, ParseError> {
        let cleaned = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        if cleaned.isEmpty { return .failure(.empty) }

        let starCount = cleaned.filter { $0 == "*" }.count
        if starCount == 0 { return .failure(.missingWildcard) }
        if starCount > 1 || !cleaned.hasSuffix("*") { return .failure(.wildcardNotTrailing) }

        let fixedPart = String(cleaned.dropLast())
        if fixedPart.isEmpty { return .failure(.wildcardNotTrailing) }

        let leadingPlus = fixedPart.hasPrefix("+")
        let digitsString = leadingPlus ? String(fixedPart.dropFirst()) : fixedPart
        guard !digitsString.isEmpty,
              digitsString.allSatisfy({ $0.isASCII && $0.isNumber })
        else {
            return .failure(.unparseable)
        }

        let region: String
        let countryCodeString: String
        let nationalDigits: String

        if leadingPlus {
            guard let resolved = box.regionAndCode(forLeadingDigits: digitsString) else {
                return .failure(.unparseable)
            }
            region = resolved.region
            countryCodeString = String(resolved.countryCode)
            nationalDigits = String(digitsString.dropFirst(countryCodeString.count))
        } else {
            guard let code = box.countryCode(forRegion: defaultRegion) else {
                return .failure(.unparseable)
            }
            region = defaultRegion
            countryCodeString = String(code)
            // National input carries the trunk prefix ("0" in France, "1" in
            // NANP countries) which is not part of the E.164 number : `0162*`
            // must become `33162*`, not `330162*`.
            nationalDigits = Self.stripTrunkPrefix(
                digitsString,
                trunkPrefix: box.nationalPrefix(forRegion: defaultRegion)
            )
        }

        if nationalDigits.count < quotas.minFixedDigits {
            return .failure(.fixedTooShort(minimum: quotas.minFixedDigits))
        }

        guard let maxLength = box.maxNationalLength(forRegion: region) else {
            return .failure(.unknownNationalLength(country: region))
        }

        if nationalDigits.count > maxLength {
            return .failure(.fixedTooLong(maximum: maxLength))
        }

        let wildcardLength = maxLength - nationalDigits.count
        let expanded = Self.pow10(wildcardLength)

        if expanded > quotas.perPattern {
            return .failure(.exceedsPerPatternQuota(expanded: expanded, limit: quotas.perPattern))
        }

        return .success(
            E164Prefix(
                fixedDigits: countryCodeString + nationalDigits,
                wildcardLength: wildcardLength
            )
        )
    }

    static func stripTrunkPrefix(_ digits: String, trunkPrefix: String?) -> String {
        guard let trunkPrefix, !trunkPrefix.isEmpty, digits.hasPrefix(trunkPrefix) else { return digits }
        return String(digits.dropFirst(trunkPrefix.count))
    }

    static func pow10(_ exponent: Int) -> Int {
        guard exponent >= 0 else { return 0 }
        return (0..<exponent).reduce(1) { acc, _ in acc * 10 }
    }
}

extension WildcardParser: DependencyKey {
    public static let liveValue: WildcardParser = .live
    public static let testValue: WildcardParser = WildcardParser { _, _ in
        unimplemented("WildcardParser.parse", placeholder: .failure(.empty))
    }
}

extension DependencyValues {
    public var wildcardParser: WildcardParser {
        get { self[WildcardParser.self] }
        set { self[WildcardParser.self] = newValue }
    }
}
