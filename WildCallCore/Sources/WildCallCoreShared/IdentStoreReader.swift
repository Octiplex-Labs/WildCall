import Foundation

public struct IdentStoreReader {
    public enum Error: Swift.Error, Equatable {
        case fileTooSmall
        case badMagic
        case unsupportedVersion(UInt32)
        case truncated
        case stringTableOutOfBounds
        case malformedLabel
    }

    public let count: Int
    public let numbers: UnsafeBufferPointer<Int64>
    private let data: Data
    private let labelOffsets: UnsafeBufferPointer<UInt32>
    private let stringTableStart: Int

    public init(url: URL) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        try self.init(data: data)
    }

    public init(data: Data) throws {
        guard data.count >= BlockStoreFormat.identHeaderSize else { throw Error.fileTooSmall }
        let magicOK = data.prefix(4).elementsEqual(BlockStoreFormat.identMagic)
        guard magicOK else { throw Error.badMagic }

        let version: UInt32 = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        guard version == BlockStoreFormat.version else { throw Error.unsupportedVersion(version) }

        let count64: UInt64 = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt64.self) }
        let stringTableOffset: UInt64 = data.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt64.self) }
        let count = Int(count64)

        let numbersStart = BlockStoreFormat.identHeaderSize
        let numbersBytes = count * MemoryLayout<Int64>.size
        let labelOffsetsStart = numbersStart + numbersBytes
        let labelOffsetsBytes = count * MemoryLayout<UInt32>.size
        let stringTableStart = labelOffsetsStart + labelOffsetsBytes

        guard data.count >= stringTableStart else { throw Error.truncated }
        guard Int(stringTableOffset) == stringTableStart else { throw Error.stringTableOutOfBounds }

        self.data = data
        self.count = count
        self.stringTableStart = stringTableStart
        self.numbers = data.withUnsafeBytes { raw -> UnsafeBufferPointer<Int64> in
            let base = raw.baseAddress!.advanced(by: numbersStart)
                .assumingMemoryBound(to: Int64.self)
            return UnsafeBufferPointer(start: base, count: count)
        }
        self.labelOffsets = data.withUnsafeBytes { raw -> UnsafeBufferPointer<UInt32> in
            let base = raw.baseAddress!.advanced(by: labelOffsetsStart)
                .assumingMemoryBound(to: UInt32.self)
            return UnsafeBufferPointer(start: base, count: count)
        }
    }

    public func label(at index: Int) throws -> String {
        precondition(index >= 0 && index < count, "index out of bounds")
        let offset = stringTableStart + Int(labelOffsets[index])
        guard offset + 4 <= data.count else { throw Error.malformedLabel }
        // String-table entries are variable-length, so the u32 length prefix
        // can land on any byte offset : use the unaligned load.
        let length: UInt32 = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        let stringStart = offset + 4
        let stringEnd = stringStart + Int(length)
        guard stringEnd <= data.count else { throw Error.malformedLabel }
        let bytes = data.subdata(in: stringStart..<stringEnd)
        guard let str = String(data: bytes, encoding: .utf8) else { throw Error.malformedLabel }
        return str
    }
}
