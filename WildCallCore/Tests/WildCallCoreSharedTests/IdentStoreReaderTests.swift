import Foundation
import Testing
@testable import WildCallCoreShared

@Suite struct IdentStoreReaderTests {
    @Test func roundtripSingleEntry() throws {
        let data = makeIdentBlob(entries: [(33_612_345_678, "Spam suspecté")])
        let reader = try IdentStoreReader(data: data)
        #expect(reader.count == 1)
        #expect(reader.numbers[0] == 33_612_345_678)
        #expect(try reader.label(at: 0) == "Spam suspecté")
    }

    @Test func roundtripMultipleEntries() throws {
        let entries: [(Int64, String)] = [
            (33_162_000_000, "ARCEP démarchage"),
            (33_270_000_000, "ARCEP démarchage"),
            (33_899_111_222, "Surtaxé"),
        ]
        let data = makeIdentBlob(entries: entries)
        let reader = try IdentStoreReader(data: data)
        #expect(reader.count == 3)
        for (index, entry) in entries.enumerated() {
            #expect(reader.numbers[index] == entry.0)
            #expect(try reader.label(at: index) == entry.1)
        }
    }

    @Test func rejectsBadMagic() {
        let data = Data(repeating: 0xFF, count: BlockStoreFormat.identHeaderSize)
        #expect(throws: IdentStoreReader.Error.badMagic) {
            try IdentStoreReader(data: data)
        }
    }

    @Test func rejectsTooSmall() {
        let data = Data(count: 4)
        #expect(throws: IdentStoreReader.Error.fileTooSmall) {
            try IdentStoreReader(data: data)
        }
    }
}

// Hand-rolled encoder used by tests so they don't depend on the App-side
// builder (which lives in a different target).
private func makeIdentBlob(entries: [(Int64, String)]) -> Data {
    let count = entries.count
    let numbersBytes = count * MemoryLayout<Int64>.size
    let offsetsBytes = count * MemoryLayout<UInt32>.size
    let stringTableStart = BlockStoreFormat.identHeaderSize + numbersBytes + offsetsBytes

    var stringTable = Data()
    var offsets: [UInt32] = []
    for (_, label) in entries {
        offsets.append(UInt32(stringTable.count))
        let utf8 = Data(label.utf8)
        var length = UInt32(utf8.count)
        withUnsafeBytes(of: &length) { stringTable.append(contentsOf: $0) }
        stringTable.append(utf8)
    }

    var data = Data()
    data.append(contentsOf: BlockStoreFormat.identMagic)
    var version = BlockStoreFormat.version
    withUnsafeBytes(of: &version) { data.append(contentsOf: $0) }
    var count64 = UInt64(count)
    withUnsafeBytes(of: &count64) { data.append(contentsOf: $0) }
    var stringTableOffset = UInt64(stringTableStart)
    withUnsafeBytes(of: &stringTableOffset) { data.append(contentsOf: $0) }

    for (number, _) in entries {
        var n = number
        withUnsafeBytes(of: &n) { data.append(contentsOf: $0) }
    }
    for offset in offsets {
        var o = offset
        withUnsafeBytes(of: &o) { data.append(contentsOf: $0) }
    }
    data.append(stringTable)
    return data
}
