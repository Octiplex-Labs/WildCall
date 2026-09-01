import CryptoKit
import Foundation
import WildCallCoreShared

public struct BlobBuildSummary: Equatable, Sendable {
    /// Numbers covered (sum of range counts).
    public let count: Int
    /// Ranges written.
    public let rangeCount: Int
    public let bytesWritten: Int
    public let sha256: String

    public init(count: Int, rangeCount: Int? = nil, bytesWritten: Int, sha256: String) {
        self.count = count
        self.rangeCount = rangeCount ?? count
        self.bytesWritten = bytesWritten
        self.sha256 = sha256
    }
}

public struct BlockStoreBuilder: Sendable {
    public init() {}

    /// Normalizes the ranges (sort, merge, drop empty) and writes a WCB2 blob
    /// atomically.
    public func build(ranges: [NumberRange], to url: URL) throws -> BlobBuildSummary {
        let normalized = RangeSet.normalize(ranges)
        let payload = Self.encode(normalized)
        try writeAtomically(payload, to: url)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return BlobBuildSummary(
            count: Int(RangeSet.total(normalized)),
            rangeCount: normalized.count,
            bytesWritten: payload.count,
            sha256: digest
        )
    }

    static func encode(_ normalized: [NumberRange]) -> Data {
        var data = Data(capacity: BlockStoreFormat.blockHeaderSize + normalized.count * BlockStoreFormat.rangeSize)
        data.append(contentsOf: BlockStoreFormat.blockMagic)
        data.appendLittleEndian(BlockStoreFormat.version)
        data.appendLittleEndian(UInt64(normalized.count))
        data.appendLittleEndian(UInt64(RangeSet.total(normalized)))
        data.appendRanges(normalized)
        return data
    }
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendRanges(_ ranges: [NumberRange]) {
        for range in ranges {
            appendLittleEndian(range.start)
            appendLittleEndian(range.count)
        }
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
