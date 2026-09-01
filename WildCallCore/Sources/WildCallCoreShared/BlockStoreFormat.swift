import Foundation

/// Half-open range of E.164 numbers `[start, start + count)`.
///
/// This is the unit the Call Directory extension iterates : a user exact
/// number is a range of count 1, a wildcard such as `+33162*` is a single
/// range of count 10^6. Storing ranges instead of expanded numbers keeps the
/// shared file tiny regardless of how wide the patterns are, and removes the
/// app-side cost of materialising millions of Int64.
public struct NumberRange: Hashable, Sendable, Codable {
    public var start: Int64
    public var count: Int64

    public init(start: Int64, count: Int64) {
        self.start = start
        self.count = count
    }

    public static func single(_ number: Int64) -> NumberRange {
        NumberRange(start: number, count: 1)
    }

    /// Exclusive upper bound.
    public var end: Int64 { start + count }

    /// Inclusive upper bound. Only meaningful when `count > 0`.
    public var last: Int64 { start + count - 1 }

    public var isEmpty: Bool { count <= 0 }

    public func contains(_ number: Int64) -> Bool {
        number >= start && number < end
    }
}

public enum BlockStoreFormat {
    public static let blockMagic: [UInt8] = Array("WCB2".utf8)
    public static let identMagic: [UInt8] = Array("WCI2".utf8)
    public static let version: UInt32 = 2

    // WCB2 header layout (24 bytes):
    //   [0..4)   magic "WCB2"
    //   [4..8)   version      u32
    //   [8..16)  rangeCount   u64
    //   [16..24) totalNumbers u64  (sum of range counts, informational)
    //   [24...)  rangeCount × NumberRange (start i64, count i64), sorted
    //            ascending by start, disjoint, non-empty
    public static let blockHeaderSize = 24

    // WCI2 header layout (32 bytes):
    //   [0..4)   magic "WCI2"
    //   [4..8)   version           u32
    //   [8..16)  rangeCount        u64
    //   [16..24) totalNumbers      u64
    //   [24..32) stringTableOffset u64
    //   followed by: rangeCount × NumberRange (start i64, count i64)
    //   followed by: rangeCount × u32 label offsets into string table
    //   followed by: string table (each entry = u32 length + UTF-8 bytes)
    public static let identHeaderSize = 32

    public static let rangeSize = 16

    // Files exchanged through the App Group container.
    public static let appGroupIdentifier = "group.com.octiplex.wildcall"
    public static let blockFileName = "block.bin"
    public static let identFileName = "ident.bin"
    public static let manifestFileName = "store.json"
    public static let extensionRunFileName = "extension-run.json"
}
