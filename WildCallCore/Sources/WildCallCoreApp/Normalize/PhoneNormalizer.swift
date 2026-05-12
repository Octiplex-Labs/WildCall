import Dependencies
import Foundation
import PhoneNumberKit
import Synchronization
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

// PhoneNumberUtility's metadata is loaded once at init and read-only after,
// but the class is not annotated Sendable. We serialize access through a
// Mutex (iOS 18+ Synchronization) and expose a Sendable wrapper.
private final class PhoneNumberBox: Sendable {
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
