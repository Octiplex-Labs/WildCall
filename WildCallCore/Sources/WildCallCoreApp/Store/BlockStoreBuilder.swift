import CryptoKit
import Foundation
import WildCallCoreShared

public struct BlobBuildSummary: Equatable, Sendable {
    public let count: Int
    public let bytesWritten: Int
    public let sha256: String
}

public struct BlockStoreBuilder: Sendable {
    public init() {}

    public enum Failure: Error, Equatable {
        case writeFailed(String)
    }

    // Sorts + dedupes, then writes WCB1 blob atomically.
    public func build(numbers: [Int64], to url: URL) throws -> BlobBuildSummary {
        let sortedUnique = Self.sortDedupe(numbers)
        let payload = Self.encode(sortedUnique)
        try writeAtomically(payload, to: url)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return BlobBuildSummary(
            count: sortedUnique.count,
            bytesWritten: payload.count,
            sha256: digest
        )
    }

    static func sortDedupe(_ numbers: [Int64]) -> [Int64] {
        guard !numbers.isEmpty else { return [] }
        let sorted = numbers.sorted()
        var out: [Int64] = []
        out.reserveCapacity(sorted.count)
        var previous: Int64? = nil
        for n in sorted {
            if n != previous {
                out.append(n)
                previous = n
            }
        }
        return out
    }

    static func encode(_ sortedUnique: [Int64]) -> Data {
        var data = Data(capacity: BlockStoreFormat.blockHeaderSize + sortedUnique.count * 8)
        data.append(contentsOf: BlockStoreFormat.blockMagic)
        var version = BlockStoreFormat.version
        withUnsafeBytes(of: &version) { data.append(contentsOf: $0) }
        var count = UInt64(sortedUnique.count)
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        sortedUnique.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            data.append(Data(bytes: base, count: buffer.count * MemoryLayout<Int64>.size))
        }
        return data
    }
}

func writeAtomically(_ data: Data, to url: URL) throws {
    let tmp = url.appendingPathExtension("tmp")
    try? FileManager.default.removeItem(at: tmp)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: tmp, options: [.atomic])
    if FileManager.default.fileExists(atPath: url.path) {
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    } else {
        try FileManager.default.moveItem(at: tmp, to: url)
    }
}
