import Foundation
import Testing
import Dependencies
import WildCallCoreShared
@testable import WildCallCoreApp

@Suite struct StoreOrchestratorTests {
    let expander = WildcardExpander.live
    let quotas = WildcardQuotas.default

    @Test func splitsExactRulesByAction() throws {
        let rules: [BlockRule] = [
            .init(kind: .exact(E164(1)!), source: .user, action: .block, countryCode: "FR"),
            .init(kind: .exact(E164(2)!), source: .user, action: .identify, countryCode: "FR", label: "Spam"),
            .init(kind: .exact(E164(3)!), source: .user, action: .identify, countryCode: "FR", label: nil),
        ]
        let (numbers, entries) = try StoreOrchestrator.split(rules: rules, expander: expander, quotas: quotas)
        #expect(numbers == [1])
        #expect(entries.count == 2)
        #expect(entries[0].number == 2)
        #expect(entries[0].label == "Spam")
        #expect(entries[1].number == 3)
        #expect(entries[1].label == "WildCall")
    }

    @Test func expandsUserPrefixBlockRule() throws {
        let rules: [BlockRule] = [
            .init(
                kind: .prefix(.init(fixedDigits: "33162999", wildcardLength: 1)),
                source: .user, action: .block, countryCode: "FR"
            ),
        ]
        let (numbers, entries) = try StoreOrchestrator.split(rules: rules, expander: expander, quotas: quotas)
        #expect(numbers.count == 10)
        #expect(numbers.first == 33_162_999_0)
        #expect(numbers.last == 33_162_999_9)
        #expect(entries.isEmpty)
    }

    @Test func expandsUserPrefixIdentifyRulePreservingLabel() throws {
        let rules: [BlockRule] = [
            .init(
                kind: .prefix(.init(fixedDigits: "33162999", wildcardLength: 1)),
                source: .user, action: .identify, countryCode: "FR", label: "Démarchage Paris"
            ),
        ]
        let (numbers, entries) = try StoreOrchestrator.split(rules: rules, expander: expander, quotas: quotas)
        #expect(numbers.isEmpty)
        #expect(entries.count == 10)
        #expect(entries.allSatisfy { $0.label == "Démarchage Paris" })
        #expect(entries.first?.number == 33_162_999_0)
        #expect(entries.last?.number == 33_162_999_9)
    }

    @Test func throwsWhenUserTotalQuotaExceeded() {
        let tight = WildcardQuotas(perPattern: 10_000, totalUser: 15, minFixedDigits: 6)
        let rules: [BlockRule] = [
            .init(kind: .prefix(.init(fixedDigits: "33162999", wildcardLength: 1)),
                  source: .user, action: .block, countryCode: "FR"),
            .init(kind: .prefix(.init(fixedDigits: "33162888", wildcardLength: 1)),
                  source: .user, action: .block, countryCode: "FR"),
        ]
        #expect(throws: OrchestratorError.exceedsTotalQuota(expanded: 20, limit: 15)) {
            _ = try StoreOrchestrator.split(rules: rules, expander: expander, quotas: tight)
        }
    }

    @Test func packPrefixRulesAreExpandedButNotCountedInUserTotal() throws {
        let tight = WildcardQuotas(perPattern: 10_000, totalUser: 5, minFixedDigits: 6)
        let rules: [BlockRule] = [
            // User contributes 4 expanded numbers : under the 5 limit.
            .init(kind: .prefix(.init(fixedDigits: "33162999", wildcardLength: 0)),
                  source: .user, action: .block, countryCode: "FR"),
            // Pack contributes 100 expanded numbers : must NOT count against the user total.
            .init(kind: .prefix(.init(fixedDigits: "44712345", wildcardLength: 2)),
                  source: .pack(packId: "uk.test"), action: .block, countryCode: "GB"),
        ]
        let (numbers, _) = try StoreOrchestrator.split(rules: rules, expander: expander, quotas: tight)
        #expect(numbers.count == 1 + 100)
    }

    @Test func filterByPackActivationDropsDisabledPackRules() {
        let rules: [BlockRule] = [
            .init(kind: .exact(E164(1)!), source: .user, action: .block, countryCode: "FR"),
            .init(kind: .exact(E164(2)!), source: .pack(packId: "fr.arcep"), action: .block, countryCode: "FR"),
            .init(kind: .exact(E164(3)!), source: .pack(packId: "fr.other"), action: .block, countryCode: "FR"),
        ]
        let packs: [InstalledPack] = [
            InstalledPack(id: "fr.arcep", version: "v1", country: "FR", enabled: true, installedAt: Date()),
            InstalledPack(id: "fr.other", version: "v1", country: "FR", enabled: false, installedAt: Date()),
        ]
        let kept = StoreOrchestrator.filterByPackActivation(rules: rules, packs: packs)
        let keptIds = kept.map { rule -> Int64 in
            if case .exact(let e164) = rule.kind { return e164.value }
            return 0
        }
        #expect(keptIds == [1, 2])  // fr.other dropped, user + fr.arcep kept
    }

    @Test func filterByPackActivationKeepsAllWhenNoneDisabled() {
        let rules: [BlockRule] = [
            .init(kind: .exact(E164(1)!), source: .user, action: .block, countryCode: "FR"),
            .init(kind: .exact(E164(2)!), source: .pack(packId: "fr.arcep"), action: .block, countryCode: "FR"),
        ]
        let packs: [InstalledPack] = [
            InstalledPack(id: "fr.arcep", version: "v1", country: "FR", enabled: true, installedAt: Date()),
        ]
        let kept = StoreOrchestrator.filterByPackActivation(rules: rules, packs: packs)
        #expect(kept.count == 2)
    }

    @Test func mixesExactAndPrefixRules() throws {
        let rules: [BlockRule] = [
            .init(kind: .exact(E164(42)!), source: .user, action: .block, countryCode: "FR"),
            .init(kind: .prefix(.init(fixedDigits: "33162999", wildcardLength: 1)),
                  source: .user, action: .block, countryCode: "FR"),
        ]
        let (numbers, entries) = try StoreOrchestrator.split(rules: rules, expander: expander, quotas: quotas)
        #expect(numbers.count == 11)
        #expect(numbers.contains(42))
        #expect(entries.isEmpty)
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
            packsRepository: .inMemory,
            container: container,
            reloader: reloader,
            expander: .live,
            quotas: .default,
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
