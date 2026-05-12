import Foundation
import Testing
@testable import WildCallCoreShared

@Suite struct BlockStoreReaderTests {
    @Test func readsValidBlob() throws {
        var data = Data()
        data.append(contentsOf: BlockStoreFormat.blockMagic)
        var version = BlockStoreFormat.version
        withUnsafeBytes(of: &version) { data.append(contentsOf: $0) }
        var count: UInt64 = 3
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        for n: Int64 in [33_162_999_999, 33_162_999_998, 33_162_999_997].sorted() {
            var v = n
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        let reader = try BlockStoreReader(data: data)
        #expect(reader.count == 3)
        #expect(reader.numbers[0] == 33_162_999_997)
    }

    @Test func rejectsBadMagic() throws {
        let data = Data(repeating: 0, count: 16)
        #expect(throws: BlockStoreReader.Error.self) {
            try BlockStoreReader(data: data)
        }
    }
}
