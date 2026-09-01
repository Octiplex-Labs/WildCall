import Foundation
import Testing
@testable import WildCallCoreShared

@Suite struct ExtensionRunReportTests {
    @Test func roundtripThroughDisk() throws {
        let url = URL(filePath: NSTemporaryDirectory())
            .appendingPathComponent("run-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        var report = ExtensionRunReport(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isIncremental: true,
            blockNumbers: 20_000_000,
            identNumbers: 3
        )
        report.finishedAt = Date(timeIntervalSince1970: 1_700_000_084)
        report.outcome = .completed
        try report.write(to: url)

        let loaded = try ExtensionRunReport.load(from: url)
        #expect(loaded == report)
        #expect(loaded?.duration == 84)
    }

    @Test func missingFileIsNil() throws {
        let url = URL(filePath: NSTemporaryDirectory()).appendingPathComponent("missing-\(UUID().uuidString).json")
        #expect(try ExtensionRunReport.load(from: url) == nil)
    }
}
