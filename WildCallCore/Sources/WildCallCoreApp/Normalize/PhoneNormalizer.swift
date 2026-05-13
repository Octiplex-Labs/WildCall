import Dependencies
import Foundation
import WildCallCoreShared

public struct PhoneNormalizer: Sendable {
    public var normalize: @Sendable (_ raw: String, _ defaultRegion: String) throws -> E164
    public var validate: @Sendable (_ raw: String, _ defaultRegion: String) -> Bool
    public var format: @Sendable (_ e164: E164) -> String

    public init(
        normalize: @escaping @Sendable (String, String) throws -> E164,
        validate: @escaping @Sendable (String, String) -> Bool,
        format: @escaping @Sendable (E164) -> String
    ) {
        self.normalize = normalize
        self.validate = validate
        self.format = format
    }

    public enum Failure: Error, Equatable {
        case unparsable
        case invalid
        case outOfRange
    }
}

extension PhoneNormalizer {
    public static let live: PhoneNormalizer = {
        let box = PhoneNumberBox()
        return PhoneNormalizer(
            normalize: { raw, region in
                let number = try box.parse(raw, region: region)
                let formatted = box.e164(number)
                guard formatted.hasPrefix("+"),
                      let value = Int64(formatted.dropFirst()),
                      let e164 = E164(value)
                else { throw Failure.outOfRange }
                return e164
            },
            validate: { raw, region in
                box.isValid(raw, region: region)
            },
            format: { e164 in
                "+\(e164.value)"
            }
        )
    }()
}

extension PhoneNormalizer: DependencyKey {
    public static let liveValue: PhoneNormalizer = .live
    public static let testValue: PhoneNormalizer = PhoneNormalizer(
        normalize: { _, _ in unimplemented("PhoneNormalizer.normalize", placeholder: E164(33_612_345_678)!) },
        validate: { _, _ in unimplemented("PhoneNormalizer.validate", placeholder: false) },
        format: { _ in unimplemented("PhoneNormalizer.format", placeholder: "") }
    )
}

extension DependencyValues {
    public var phoneNormalizer: PhoneNormalizer {
        get { self[PhoneNormalizer.self] }
        set { self[PhoneNormalizer.self] = newValue }
    }
}
