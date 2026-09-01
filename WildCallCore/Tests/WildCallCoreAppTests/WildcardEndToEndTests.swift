import Foundation
import Testing
import CustomDump
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct WildcardEndToEndTests {
    @Test func userWildcardRuleFlowsFromParseToBlob() async throws {
        // 1. Parse the input a French user actually types.
        let parsed = WildcardParser.live.parse("0123*", "FR")
        guard case .success(let prefix) = parsed else {
            Issue.record("expected parse success, got \(parsed)")
            return
        }
        #expect(prefix == E164Prefix(fixedDigits: "33123", wildcardLength: 6))

        // 2. Round-trip through the SwiftData mapping.
        let rule = BlockRule(
            kind: .prefix(prefix),
            source: .user,
            action: .block,
            countryCode: "FR",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let recovered = try BlockRuleRecord.from(rule).toRule()
        expectNoDifference(recovered, rule)

        // 3. Run the orchestrator end-to-end against an ephemeral container.
        let tmpRoot = URL(filePath: NSTemporaryDirectory())
            .appendingPathComponent("WildCallE2E-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let container = SharedContainer.ephemeral(root: tmpRoot)
        let orchestrator = StoreOrchestrator.live(
            repository: RulesRepository(fetchAll: { [rule] }, insert: { _ in }, delete: { _ in }, update: { _ in }),
            packsRepository: .inMemory,
            container: container,
            reloader: ExtensionReloader(reload: { _ in }, getEnabledStatus: { _ in .enabled }),
            expander: .live,
            quotas: .default,
            status: StoreStatusHub().client,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let summary = try await orchestrator.rebuildAndReload()
        #expect(summary.blockCount == 1_000_000)
        #expect(summary.block.rangeCount == 1)
        #expect(summary.identCount == 0)

        // 4. Read the blob back the way the extension does.
        let reader = try BlockStoreReader(url: container.blockStoreURL(ExtensionSlot(1)))
        #expect(reader.ranges == [NumberRange(start: 33_123_000_000, count: 1_000_000)])
        #expect(reader.ranges.first?.contains(33_123_456_789) == true)
        #expect(reader.ranges.first?.contains(33_124_000_000) == false)

        var visited: Int64 = 0
        var first: Int64? = nil
        var last: Int64? = nil
        reader.forEachNumber { number in
            if first == nil { first = number }
            last = number
            visited += 1
        }
        #expect(visited == 1_000_000)
        #expect(first == 33_123_000_000)
        #expect(last == 33_123_999_999)
    }
}
