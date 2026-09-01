import Foundation

/// Reads a WCB2 blob. Ranges are decoded eagerly into an array : the file
/// holds one entry per pattern (or per exact number), never one per
/// expanded number, so even a large rule set stays in the kilobytes.
public struct BlockStoreReader: Sendable {
    public enum Error: Swift.Error, Equatable {
        case fileTooSmall
        case badMagic
        case unsupportedVersion(UInt32)
        case truncated
        case rangesNotSorted
        case emptyRange
        case totalMismatch
    }

    public let ranges: [NumberRange]
    public let totalNumbers: Int64

    public var rangeCount: Int { ranges.count }

    public init(url: URL) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        try self.init(data: data)
    }

    public init(data: Data) throws {
        guard data.count >= BlockStoreFormat.blockHeaderSize else { throw Error.fileTooSmall }
        guard data.prefix(4).elementsEqual(BlockStoreFormat.blockMagic) else { throw Error.badMagic }

        let version: UInt32 = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
        guard version == BlockStoreFormat.version else { throw Error.unsupportedVersion(version) }

        let rangeCount = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self) })
        let declaredTotal = Int64(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt64.self) })

        let ranges = try Self.decodeRanges(
            data,
            at: BlockStoreFormat.blockHeaderSize,
            count: rangeCount
        )
        try Self.validate(ranges, declaredTotal: declaredTotal)

        self.ranges = ranges
        self.totalNumbers = declaredTotal
    }

    /// Visits every number of every range, ascending. This is what the
    /// extension feeds to `addBlockingEntry(withNextSequentialPhoneNumber:)`.
    public func forEachNumber(_ body: (Int64) throws -> Void) rethrows {
        for range in ranges {
            var number = range.start
            let end = range.end
            while number < end {
                try body(number)
                number += 1
            }
        }
    }

    static func decodeRanges(_ data: Data, at offset: Int, count: Int) throws -> [NumberRange] {
        guard count >= 0 else { throw Error.truncated }
        let bytesNeeded = count * BlockStoreFormat.rangeSize
        guard data.count >= offset + bytesNeeded else { throw Error.truncated }
        var ranges: [NumberRange] = []
        ranges.reserveCapacity(count)
        data.withUnsafeBytes { raw in
            var cursor = offset
            for _ in 0..<count {
                let start = raw.loadUnaligned(fromByteOffset: cursor, as: Int64.self)
                let length = raw.loadUnaligned(fromByteOffset: cursor + 8, as: Int64.self)
                ranges.append(NumberRange(start: start, count: length))
                cursor += BlockStoreFormat.rangeSize
            }
        }
        return ranges
    }

    static func validate(_ ranges: [NumberRange], declaredTotal: Int64) throws {
        var total: Int64 = 0
        var previousEnd: Int64? = nil
        for range in ranges {
            guard range.count > 0 else { throw Error.emptyRange }
            if let previousEnd, range.start < previousEnd { throw Error.rangesNotSorted }
            previousEnd = range.end
            total += range.count
        }
        guard total == declaredTotal else { throw Error.totalMismatch }
    }
}
