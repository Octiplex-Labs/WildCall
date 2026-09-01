import Foundation
import Testing
@testable import WildCallCoreShared

@Suite struct IdentStoreReaderTests {
    @Test func roundtripSingleEntry() throws {
        let data = makeIdentBlob(entries: [(.single(33_612_345_678), "Spam suspecté")])
        let reader = try IdentStoreReader(data: data)
        #expect(reader.rangeCount == 1)
        #expect(reader.totalNumbers == 1)
        #expect(reader.entries[0].range == .single(33_612_345_678))
        #expect(reader.entries[0].label == "Spam suspecté")
    }

    @Test func roundtripMultipleEntries() throws {
        let entries: [(NumberRange, String)] = [
            (NumberRange(start: 33_162_000_000, count: 1_000_000), "ARCEP démarchage"),
            (NumberRange(start: 33_270_000_000, count: 1_000_000), "ARCEP démarchage"),
            (.single(33_899_111_222), "Surtaxé"),
        ]
        let reader = try IdentStoreReader(data: makeIdentBlob(entries: entries))
        #expect(reader.rangeCount == 3)
        #expect(reader.totalNumbers == 2_000_001)
        for (index, entry) in entries.enumerated() {
            #expect(reader.entries[index].range == entry.0)
            #expect(reader.entries[index].label == entry.1)
        }
    }

    @Test func forEachNumberRepeatsLabelPerNumber() throws {
        let data = makeIdentBlob(entries: [
            (NumberRange(start: 10, count: 2), "A"),
            (NumberRange(start: 20, count: 1), "B"),
        ])
        let reader = try IdentStoreReader(data: data)
        var visited: [(Int64, String)] = []
        reader.forEachNumber { visited.append(($0, $1)) }
        #expect(visited.map(\.0) == [10, 11, 20])
        #expect(visited.map(\.1) == ["A", "A", "B"])
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

    @Test func rejectsUnsortedRanges() {
        let data = makeIdentBlob(entries: [
            (NumberRange(start: 20, count: 1), "B"),
            (NumberRange(start: 10, count: 1), "A"),
        ])
        #expect(throws: IdentStoreReader.Error.rangesNotSorted) {
            try IdentStoreReader(data: data)
        }
    }
}

private func makeIdentBlob(entries: [(NumberRange, String)]) -> Data {
    let count = entries.count
    let stringTableStart = BlockStoreFormat.identHeaderSize
        + count * BlockStoreFormat.rangeSize
        + count * MemoryLayout<UInt32>.size

    var stringTable = Data()
    var offsets: [UInt32] = []
    for (_, label) in entries {
        offsets.append(UInt32(stringTable.count))
        let utf8 = Data(label.utf8)
        stringTable.appendLE(UInt32(utf8.count))
        stringTable.append(utf8)
    }

    var data = Data()
    data.append(contentsOf: BlockStoreFormat.identMagic)
    data.appendLE(BlockStoreFormat.version)
    data.appendLE(UInt64(count))
    data.appendLE(UInt64(entries.reduce(0) { $0 + $1.0.count }))
    data.appendLE(UInt64(stringTableStart))
    for (range, _) in entries {
        data.appendLE(range.start)
        data.appendLE(range.count)
    }
    for offset in offsets {
        data.appendLE(offset)
    }
    data.append(stringTable)
    return data
}
