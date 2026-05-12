import Foundation

public struct BlockStoreReader {
    public enum Error: Swift.Error {
        case fileTooSmall
        case badMagic
        case unsupportedVersion(UInt32)
        case truncated
    }

    public let count: Int
    public let numbers: UnsafeBufferPointer<Int64>
    private let data: Data

    public init(url: URL, expectedMagic: [UInt8] = BlockStoreFormat.blockMagic) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        try self.init(data: data, expectedMagic: expectedMagic)
    }

    public init(data: Data, expectedMagic: [UInt8] = BlockStoreFormat.blockMagic) throws {
        guard data.count >= 16 else { throw Error.fileTooSmall }
        let magicOK = data.prefix(4).elementsEqual(expectedMagic)
        guard magicOK else { throw Error.badMagic }

        let version: UInt32 = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        guard version == BlockStoreFormat.version else { throw Error.unsupportedVersion(version) }

        let count64: UInt64 = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt64.self) }
        let count = Int(count64)
        let payloadStart = 16
        let payloadBytes = count * MemoryLayout<Int64>.size
        guard data.count >= payloadStart + payloadBytes else { throw Error.truncated }

        self.data = data
        self.count = count
        self.numbers = data.withUnsafeBytes { raw -> UnsafeBufferPointer<Int64> in
            let base = raw.baseAddress!.advanced(by: payloadStart)
                .assumingMemoryBound(to: Int64.self)
            return UnsafeBufferPointer(start: base, count: count)
        }
    }
}
