import CryptoKit
import Foundation
import WildCallCoreShared

public struct IdentStoreBuilder: Sendable {
    public init() {}

    /// Normalizes labelled ranges (see `RangeSet.normalizeIdent`) and writes
    /// a WCI2 blob atomically.
    public func build(entries: [IdentRange], to url: URL) throws -> BlobBuildSummary {
        let normalized = RangeSet.normalizeIdent(entries)
        let payload = Self.encode(normalized)
        try writeAtomically(payload, to: url)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return BlobBuildSummary(
            count: Int(RangeSet.total(normalized.map(\.range))),
            rangeCount: normalized.count,
            bytesWritten: payload.count,
            sha256: digest
        )
    }

    static func encode(_ normalized: [IdentRange]) -> Data {
        let count = normalized.count
        let stringTableStart = BlockStoreFormat.identHeaderSize
            + count * BlockStoreFormat.rangeSize
            + count * MemoryLayout<UInt32>.size

        var stringTable = Data()
        var offsets: [UInt32] = []
        offsets.reserveCapacity(count)
        for entry in normalized {
            offsets.append(UInt32(stringTable.count))
            let utf8 = Data(entry.label.utf8)
            stringTable.appendLittleEndian(UInt32(utf8.count))
            stringTable.append(utf8)
        }

        var data = Data(capacity: stringTableStart + stringTable.count)
        data.append(contentsOf: BlockStoreFormat.identMagic)
        data.appendLittleEndian(BlockStoreFormat.version)
        data.appendLittleEndian(UInt64(count))
        data.appendLittleEndian(UInt64(RangeSet.total(normalized.map(\.range))))
        data.appendLittleEndian(UInt64(stringTableStart))
        data.appendRanges(normalized.map(\.range))
        for offset in offsets {
            data.appendLittleEndian(offset)
        }
        data.append(stringTable)
        return data
    }
}
