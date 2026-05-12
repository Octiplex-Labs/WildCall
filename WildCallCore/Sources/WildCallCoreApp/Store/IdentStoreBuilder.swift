import CryptoKit
import Foundation
import WildCallCoreShared

public struct IdentEntry: Hashable, Sendable {
    public let number: Int64
    public let label: String

    public init(number: Int64, label: String) {
        self.number = number
        self.label = label
    }
}

public struct IdentStoreBuilder: Sendable {
    public init() {}

    // Sorts ascending by number, dedupes (last label wins on conflict),
    // and writes WCI1 blob atomically.
    public func build(entries: [IdentEntry], to url: URL) throws -> BlobBuildSummary {
        let sortedUnique = Self.sortDedupe(entries)
        let payload = Self.encode(sortedUnique)
        try writeAtomically(payload, to: url)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return BlobBuildSummary(
            count: sortedUnique.count,
            bytesWritten: payload.count,
            sha256: digest
        )
    }

    static func sortDedupe(_ entries: [IdentEntry]) -> [IdentEntry] {
        guard !entries.isEmpty else { return [] }
        let sorted = entries.sorted { $0.number < $1.number }
        var out: [IdentEntry] = []
        out.reserveCapacity(sorted.count)
        for entry in sorted {
            if let last = out.last, last.number == entry.number {
                out[out.count - 1] = entry
            } else {
                out.append(entry)
            }
        }
        return out
    }

    static func encode(_ sortedUnique: [IdentEntry]) -> Data {
        let count = sortedUnique.count
        let numbersBytes = count * MemoryLayout<Int64>.size
        let offsetsBytes = count * MemoryLayout<UInt32>.size
        let stringTableStart = BlockStoreFormat.identHeaderSize + numbersBytes + offsetsBytes

        var stringTable = Data()
        var offsets: [UInt32] = []
        offsets.reserveCapacity(count)
        for entry in sortedUnique {
            offsets.append(UInt32(stringTable.count))
            let utf8 = Data(entry.label.utf8)
            var length = UInt32(utf8.count)
            withUnsafeBytes(of: &length) { stringTable.append(contentsOf: $0) }
            stringTable.append(utf8)
        }

        var data = Data(capacity: stringTableStart + stringTable.count)
        data.append(contentsOf: BlockStoreFormat.identMagic)
        var version = BlockStoreFormat.version
        withUnsafeBytes(of: &version) { data.append(contentsOf: $0) }
        var count64 = UInt64(count)
        withUnsafeBytes(of: &count64) { data.append(contentsOf: $0) }
        var stringTableOffset = UInt64(stringTableStart)
        withUnsafeBytes(of: &stringTableOffset) { data.append(contentsOf: $0) }

        // Numbers section
        sortedUnique.map { $0.number }.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            data.append(Data(bytes: base, count: buffer.count * MemoryLayout<Int64>.size))
        }

        // Label offsets section
        offsets.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            data.append(Data(bytes: base, count: buffer.count * MemoryLayout<UInt32>.size))
        }

        // String table
        data.append(stringTable)

        return data
    }
}
