import Foundation
import Testing
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct BlockStoreBuilderTests {
    @Test func roundtripThroughReader() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try BlockStoreBuilder().build(
            ranges: [
                .single(33_612_345_678),
                NumberRange(start: 33_162_000_000, count: 1_000_000),
                .single(33_899_111_222),
            ],
            to: url
        )
        #expect(summary.count == 1_000_002)
        #expect(summary.rangeCount == 3)
        #expect(summary.bytesWritten == BlockStoreFormat.blockHeaderSize + 3 * BlockStoreFormat.rangeSize)

        let reader = try BlockStoreReader(url: url)
        #expect(reader.ranges == [
            NumberRange(start: 33_162_000_000, count: 1_000_000),
            .single(33_612_345_678),
            .single(33_899_111_222),
        ])
        #expect(reader.totalNumbers == 1_000_002)
    }

    @Test func mergesOverlappingAndDuplicateInput() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try BlockStoreBuilder().build(
            ranges: [.single(5), .single(5), NumberRange(start: 1, count: 4), NumberRange(start: 3, count: 4)],
            to: url
        )
        #expect(summary.rangeCount == 1)
        #expect(summary.count == 6)
        #expect(try BlockStoreReader(url: url).ranges == [NumberRange(start: 1, count: 6)])
    }

    @Test func atomicReplaceOnExistingFile() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let builder = BlockStoreBuilder()
        _ = try builder.build(ranges: [.single(1), .single(2), .single(3)], to: url)
        _ = try builder.build(ranges: [.single(99), .single(100)], to: url)

        #expect(try BlockStoreReader(url: url).ranges == [NumberRange(start: 99, count: 2)])
    }

    @Test func emptyInputProducesValidEmptyBlob() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try BlockStoreBuilder().build(ranges: [], to: url)
        #expect(summary.count == 0)
        #expect(summary.rangeCount == 0)
        #expect(summary.bytesWritten == BlockStoreFormat.blockHeaderSize)

        let reader = try BlockStoreReader(url: url)
        #expect(reader.rangeCount == 0)
    }
}

func makeTempURL() -> URL {
    URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("bin")
}
