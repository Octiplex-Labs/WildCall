import Foundation
import Testing
import Dependencies
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct StoreOrchestratorTests {
    @Test func splitsRulesByAction() {
        let rules: [BlockRule] = [
            .init(kind: .exact(E164(1)!), source: .user, action: .block, countryCode: "FR"),
            .init(kind: .exact(E164(2)!), source: .user, action: .identify, countryCode: "FR", label: "Spam"),
            .init(kind: .prefix(.init(fixedDigits: "33162999", wildcardLength: 3)),
                  source: .user, action: .block, countryCode: "FR"),
            .init(kind: .exact(E164(3)!), source: .user, action: .identify, countryCode: "FR", label: nil),
        ]
        let (numbers, entries) = StoreOrchestrator.split(rules: rules)
        // Prefix rules are deferred to Phase 2 — they're ignored by the orchestrator for now.
        #expect(numbers == [1])
        #expect(entries.count == 2)
        #expect(entries[0].number == 2)
        #expect(entries[0].label == "Spam")
        #expect(entries[1].number == 3)
        #expect(entries[1].label == "WildCall")  // fallback when label is nil
    }

    @Test func rebuildAndReloadHappyPath() async throws {
        let tmpRoot = URL(filePath: NSTemporaryDirectory())
            .appendingPathComponent("WildCallTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let container = SharedContainer.ephemeral(root: tmpRoot)
        let rule = BlockRule(
            kind: .exact(E164(33_612_345_678)!),
            source: .user,
            action: .block,
            countryCode: "FR"
        )

        let repository = RulesRepository(
            fetchAll: { [rule] },
            insert: { _ in },
            delete: { _ in },
            update: { _ in }
        )

        let reloadCalls = LockIsolated(0)
        let reloader = ExtensionReloader(
            reload: { reloadCalls.withValue { $0 += 1 } },
            getEnabledStatus: { .enabled }
        )

        let orchestrator = StoreOrchestrator.live(
            repository: repository,
            container: container,
            reloader: reloader,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let summary = try await orchestrator.rebuildAndReload()
        #expect(summary.blockCount == 1)
        #expect(summary.identCount == 0)
        #expect(reloadCalls.value == 1)

        let blockReader = try BlockStoreReader(url: container.blockStoreURL())
        #expect(Array(blockReader.numbers) == [33_612_345_678])

        let manifest = try StoreManifest.load(from: container.manifestURL())
        #expect(manifest?.block.count == 1)
        #expect(manifest?.ident.count == 0)
    }
}

final class LockIsolated<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) { self._value = value }

    var value: Value { lock.withLock { _value } }

    func withValue<T>(_ operation: (inout Value) -> T) -> T {
        lock.withLock { operation(&_value) }
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
