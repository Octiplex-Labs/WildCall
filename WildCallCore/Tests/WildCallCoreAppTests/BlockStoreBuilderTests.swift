import Foundation
import Testing
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct BlockStoreBuilderTests {
    @Test func sortDedupeKeepsAscendingUnique() {
        let input: [Int64] = [3, 1, 2, 1, 3, 5, 4, 2]
        let result = BlockStoreBuilder.sortDedupe(input)
        #expect(result == [1, 2, 3, 4, 5])
    }

    @Test func roundtripThroughReader() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let builder = BlockStoreBuilder()
        let summary = try builder.build(
            numbers: [33_612_345_678, 33_162_000_000, 33_899_111_222],
            to: url
        )
        #expect(summary.count == 3)
        #expect(summary.bytesWritten == BlockStoreFormat.blockHeaderSize + 3 * 8)

        let reader = try BlockStoreReader(url: url)
        #expect(reader.count == 3)
        #expect(Array(reader.numbers) == [33_162_000_000, 33_612_345_678, 33_899_111_222])
    }

    @Test func atomicReplaceOnExistingFile() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let builder = BlockStoreBuilder()
        _ = try builder.build(numbers: [1, 2, 3], to: url)
        _ = try builder.build(numbers: [99, 100], to: url)

        let reader = try BlockStoreReader(url: url)
        #expect(Array(reader.numbers) == [99, 100])
    }

    @Test func emptyInputProducesValidEmptyBlob() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let builder = BlockStoreBuilder()
        let summary = try builder.build(numbers: [], to: url)
        #expect(summary.count == 0)
        #expect(summary.bytesWritten == BlockStoreFormat.blockHeaderSize)

        let reader = try BlockStoreReader(url: url)
        #expect(reader.count == 0)
    }
}

func makeTempURL() -> URL {
    URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("bin")
}
