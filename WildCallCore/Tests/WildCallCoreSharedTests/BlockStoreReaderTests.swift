import Foundation
import Testing
@testable import WildCallCoreShared

@Suite struct BlockStoreReaderTests {
    @Test func readsValidBlob() throws {
        let data = makeBlockBlob(ranges: [
            NumberRange(start: 33_162_000_000, count: 1_000_000),
            NumberRange(start: 33_612_345_678, count: 1),
        ])

        let reader = try BlockStoreReader(data: data)
        #expect(reader.rangeCount == 2)
        #expect(reader.totalNumbers == 1_000_001)
        #expect(reader.ranges[0] == NumberRange(start: 33_162_000_000, count: 1_000_000))
        #expect(reader.ranges[1] == .single(33_612_345_678))
    }

    @Test func forEachNumberWalksEveryRangeAscending() throws {
        let data = makeBlockBlob(ranges: [
            NumberRange(start: 10, count: 3),
            NumberRange(start: 20, count: 2),
        ])
        let reader = try BlockStoreReader(data: data)
        var visited: [Int64] = []
        reader.forEachNumber { visited.append($0) }
        #expect(visited == [10, 11, 12, 20, 21])
    }

    @Test func emptyBlobIsValid() throws {
        let reader = try BlockStoreReader(data: makeBlockBlob(ranges: []))
        #expect(reader.rangeCount == 0)
        #expect(reader.totalNumbers == 0)
    }

    @Test func rejectsBadMagic() {
        let data = Data(repeating: 0, count: BlockStoreFormat.blockHeaderSize)
        #expect(throws: BlockStoreReader.Error.badMagic) {
            try BlockStoreReader(data: data)
        }
    }

    @Test func rejectsLegacyVersionOneMagic() {
        var data = Data("WCB1".utf8)
        data.append(Data(repeating: 0, count: BlockStoreFormat.blockHeaderSize - 4))
        #expect(throws: BlockStoreReader.Error.badMagic) {
            try BlockStoreReader(data: data)
        }
    }

    @Test func rejectsUnsortedRanges() {
        let data = makeBlockBlob(ranges: [
            NumberRange(start: 20, count: 5),
            NumberRange(start: 10, count: 5),
        ])
        #expect(throws: BlockStoreReader.Error.rangesNotSorted) {
            try BlockStoreReader(data: data)
        }
    }

    @Test func rejectsOverlappingRanges() {
        let data = makeBlockBlob(ranges: [
            NumberRange(start: 10, count: 5),
            NumberRange(start: 12, count: 5),
        ])
        #expect(throws: BlockStoreReader.Error.rangesNotSorted) {
            try BlockStoreReader(data: data)
        }
    }

    @Test func rejectsEmptyRange() {
        let data = makeBlockBlob(ranges: [NumberRange(start: 10, count: 0)])
        #expect(throws: BlockStoreReader.Error.emptyRange) {
            try BlockStoreReader(data: data)
        }
    }

    @Test func rejectsTotalMismatch() {
        let data = makeBlockBlob(ranges: [NumberRange(start: 10, count: 5)], declaredTotal: 4)
        #expect(throws: BlockStoreReader.Error.totalMismatch) {
            try BlockStoreReader(data: data)
        }
    }

    @Test func rejectsTruncatedPayload() {
        var data = makeBlockBlob(ranges: [NumberRange(start: 10, count: 5)])
        data.removeLast(4)
        #expect(throws: BlockStoreReader.Error.truncated) {
            try BlockStoreReader(data: data)
        }
    }
}

// Hand-rolled encoder so the Shared tests never depend on the App-side
// builder (different target).
func makeBlockBlob(ranges: [NumberRange], declaredTotal: Int64? = nil) -> Data {
    var data = Data()
    data.append(contentsOf: BlockStoreFormat.blockMagic)
    data.appendLE(BlockStoreFormat.version)
    data.appendLE(UInt64(ranges.count))
    data.appendLE(UInt64(declaredTotal ?? ranges.reduce(0) { $0 + $1.count }))
    for range in ranges {
        data.appendLE(range.start)
        data.appendLE(range.count)
    }
    return data
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
