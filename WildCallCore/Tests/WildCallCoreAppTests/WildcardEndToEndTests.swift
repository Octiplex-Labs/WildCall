import Foundation
import Testing
import CustomDump
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct WildcardEndToEndTests {
    @Test func userWildcardRuleFlowsFromParseToBlob() async throws {
        // 1. Parse user input.
        let parser = WildcardParser.live
        let parsed = parser.parse("+33162999*", "FR")
        guard case .success(let prefix) = parsed else {
            Issue.record("expected parse success, got \(parsed)")
            return
        }
        #expect(prefix.fixedDigits == "33162999")
        #expect(prefix.wildcardLength == 3)

        // 2. Build a BlockRule and round-trip through SwiftData mapping.
        let rule = BlockRule(
            kind: .prefix(prefix),
            source: .user,
            action: .block,
            countryCode: "FR",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let record = BlockRuleRecord.from(rule)
        let recovered = try record.toRule()
        expectNoDifference(recovered, rule)

        // 3. Run the orchestrator end-to-end against an ephemeral container.
        let tmpRoot = URL(filePath: NSTemporaryDirectory())
            .appendingPathComponent("WildCallE2E-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let container = SharedContainer.ephemeral(root: tmpRoot)
        let repository = RulesRepository(
            fetchAll: { [rule] },
            insert: { _ in },
            delete: { _ in },
            update: { _ in }
        )
        let reloader = ExtensionReloader(
            reload: { },
            getEnabledStatus: { .enabled }
        )

        let orchestrator = StoreOrchestrator.live(
            repository: repository,
            container: container,
            reloader: reloader,
            expander: .live,
            quotas: .default,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let summary = try await orchestrator.rebuildAndReload()
        #expect(summary.blockCount == 1_000)
        #expect(summary.identCount == 0)

        // 4. Read the blob back and check the contents match the expansion.
        let reader = try BlockStoreReader(url: container.blockStoreURL())
        let numbers = Array(reader.numbers)
        #expect(numbers.count == 1_000)
        #expect(numbers.first == 33_162_999_000)
        #expect(numbers.last == 33_162_999_999)
        #expect(numbers == numbers.sorted()) // builder guarantees sorted output
    }
}
