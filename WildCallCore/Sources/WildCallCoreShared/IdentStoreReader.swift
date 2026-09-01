import Foundation

public struct IdentRangeEntry: Hashable, Sendable {
    public let range: NumberRange
    public let label: String

    public init(range: NumberRange, label: String) {
        self.range = range
        self.label = label
    }
}

/// Reads a WCI2 blob : sorted, disjoint ranges with one caller-ID label each.
public struct IdentStoreReader: Sendable {
    public enum Error: Swift.Error, Equatable {
        case fileTooSmall
        case badMagic
        case unsupportedVersion(UInt32)
        case truncated
        case stringTableOutOfBounds
        case malformedLabel
        case rangesNotSorted
        case emptyRange
        case totalMismatch
    }

    public let entries: [IdentRangeEntry]
    public let totalNumbers: Int64

    public var rangeCount: Int { entries.count }

    public init(url: URL) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        try self.init(data: data)
    }

    public init(data: Data) throws {
        guard data.count >= BlockStoreFormat.identHeaderSize else { throw Error.fileTooSmall }
        guard data.prefix(4).elementsEqual(BlockStoreFormat.identMagic) else { throw Error.badMagic }

        let version: UInt32 = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
        guard version == BlockStoreFormat.version else { throw Error.unsupportedVersion(version) }

        let rangeCount = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self) })
        let declaredTotal = Int64(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt64.self) })
        let stringTableOffset = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24, as: UInt64.self) })

        let rangesStart = BlockStoreFormat.identHeaderSize
        let offsetsStart = rangesStart + rangeCount * BlockStoreFormat.rangeSize
        let stringTableStart = offsetsStart + rangeCount * MemoryLayout<UInt32>.size
        guard rangeCount >= 0, data.count >= stringTableStart else { throw Error.truncated }
        guard stringTableOffset == stringTableStart else { throw Error.stringTableOutOfBounds }

        let ranges: [NumberRange]
        do {
            ranges = try BlockStoreReader.decodeRanges(data, at: rangesStart, count: rangeCount)
        } catch {
            throw Error.truncated
        }

        var entries: [IdentRangeEntry] = []
        entries.reserveCapacity(rangeCount)
        var total: Int64 = 0
        var previousEnd: Int64? = nil
        for (index, range) in ranges.enumerated() {
            guard range.count > 0 else { throw Error.emptyRange }
            if let previousEnd, range.start < previousEnd { throw Error.rangesNotSorted }
            previousEnd = range.end
            total += range.count

            let labelOffset = Int(data.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: offsetsStart + index * 4, as: UInt32.self)
            })
            let label = try Self.readLabel(data, at: stringTableStart + labelOffset)
            entries.append(IdentRangeEntry(range: range, label: label))
        }
        guard total == declaredTotal else { throw Error.totalMismatch }

        self.entries = entries
        self.totalNumbers = declaredTotal
    }

    /// Visits every (number, label) pair ascending, for
    /// `addIdentificationEntry(withNextSequentialPhoneNumber:label:)`.
    public func forEachNumber(_ body: (Int64, String) throws -> Void) rethrows {
        for entry in entries {
            var number = entry.range.start
            let end = entry.range.end
            while number < end {
                try body(number, entry.label)
                number += 1
            }
        }
    }

    private static func readLabel(_ data: Data, at offset: Int) throws -> String {
        guard offset + 4 <= data.count else { throw Error.malformedLabel }
        let length = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) })
        let stringStart = offset + 4
        let stringEnd = stringStart + length
        guard stringEnd <= data.count else { throw Error.malformedLabel }
        guard let label = String(data: data.subdata(in: stringStart..<stringEnd), encoding: .utf8) else {
            throw Error.malformedLabel
        }
        return label
    }
}
