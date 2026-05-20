import Foundation
import Testing
import CustomDump
@testable import WildCallCoreApp

@Suite struct PackArchiveTests {
    let archive = PackArchive()

    @Test func roundtripWithoutPayload() throws {
        let contents = PackArchive.Contents(
            manifest: Data("{\"id\":\"fr.test\"}".utf8),
            signature: Data(repeating: 0xAB, count: 64),
            payload: nil
        )
        let bytes = try archive.write(contents)
        let recovered = try archive.read(bytes)
        expectNoDifference(recovered, contents)
    }

    @Test func roundtripWithPayload() throws {
        let payload = Data((1...100).flatMap { Int64($0).littleEndianBytes })
        let contents = PackArchive.Contents(
            manifest: Data("{\"id\":\"fr.test\",\"kind\":\"preExpanded\"}".utf8),
            signature: Data(repeating: 0x12, count: 64),
            payload: payload
        )
        let bytes = try archive.write(contents)
        let recovered = try archive.read(bytes)
        expectNoDifference(recovered, contents)
    }

    @Test func compressionShrinksRepetitiveManifest() throws {
        // A repetitive manifest gzips to noticeably less than the raw size.
        let manifest = Data(String(repeating: "{\"a\":1}", count: 200).utf8)
        let contents = PackArchive.Contents(
            manifest: manifest,
            signature: Data(repeating: 0, count: 64),
            payload: nil
        )
        let bytes = try archive.write(contents)
        #expect(bytes.count < manifest.count / 2)
    }

    @Test func rejectsCorruptedGzip() {
        let garbage = Data([0xFF, 0x00, 0x01, 0x02, 0x03])
        do {
            _ = try archive.read(garbage)
            Issue.record("expected decompression failure")
        } catch PackArchive.ArchiveError.decompressionFailed {
            // expected
        } catch {
            Issue.record("expected .decompressionFailed, got \(error)")
        }
    }

}

private extension Int64 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.littleEndian) { Array($0) }
    }
}
