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
        let (block, ident) = try StoreOrchestrator.split(rules: rules, expander: expander, quotas: quotas)
        #expect(block == [.single(1)])
        #expect(ident == [
            IdentRange(range: .single(2), label: "Spam"),
            IdentRange(range: .single(3), label: "WildCall"),
        ])
    }

    @Test func prefixBlockRuleBecomesOneRange() throws {
        let rules: [BlockRule] = [
            .init(kind: .prefix(.init(fixedDigits: "33162", wildcardLength: 6)), source: .user, action: .block, countryCode: "FR"),
        ]
        let (block, ident) = try StoreOrchestrator.split(rules: rules, expander: expander, quotas: quotas)
        #expect(block == [NumberRange(start: 33_162_000_000, count: 1_000_000)])
        #expect(ident.isEmpty)
    }

    @Test func prefixIdentifyRulePreservesLabel() throws {
        let rules: [BlockRule] = [
            .init(kind: .prefix(.init(fixedDigits: "33162999", wildcardLength: 1)),
                  source: .user, action: .identify, countryCode: "FR", label: "Démarchage Paris"),
        ]
        let (block, ident) = try StoreOrchestrator.split(rules: rules, expander: expander, quotas: quotas)
        #expect(block.isEmpty)
        #expect(ident == [IdentRange(range: NumberRange(start: 33_162_999_0, count: 10), label: "Démarchage Paris")])
    }

    @Test func identifyRuleCarvesHoleInBlockedPrefix() throws {
        let rules: [BlockRule] = [
            .init(kind: .prefix(.init(fixedDigits: "33162", wildcardLength: 6)),
                  source: .pack(packId: "fr.arcep"), action: .block, countryCode: "FR"),
            .init(kind: .exact(E164(33_162_345_678)!), source: .user, action: .identify, countryCode: "FR", label: "Plombier"),
        ]
        let (block, ident) = try StoreOrchestrator.split(rules: rules, expander: expander, quotas: quotas)
        #expect(block == [
            NumberRange(start: 33_162_000_000, count: 345_678),
            NumberRange(start: 33_162_345_679, count: 654_321),
        ])
        #expect(ident == [IdentRange(range: .single(33_162_345_678), label: "Plombier")])
    }

    @Test func overlappingBlockRulesAreMerged() throws {
        let rules: [BlockRule] = [
            .init(kind: .prefix(.init(fixedDigits: "33162", wildcardLength: 6)), source: .pack(packId: "a"), action: .block, countryCode: "FR"),
            .init(kind: .prefix(.init(fixedDigits: "331629", wildcardLength: 5)), source: .pack(packId: "b"), action: .block, countryCode: "FR"),
            .init(kind: .exact(E164(33_162_000_001)!), source: .user, action: .block, countryCode: "FR"),
        ]
        let (block, _) = try StoreOrchestrator.split(rules: rules, expander: expander, quotas: quotas)
        #expect(block == [NumberRange(start: 33_162_000_000, count: 1_000_000)])
    }

    @Test func throwsWhenUserTotalQuotaExceeded() {
        let tight = WildcardQuotas(perPattern: 10_000, totalUser: 15, minFixedDigits: 6)
        let rules: [BlockRule] = [
            .init(kind: .prefix(.init(fixedDigits: "33162999", wildcardLength: 1)), source: .user, action: .block, countryCode: "FR"),
            .init(kind: .prefix(.init(fixedDigits: "33162888", wildcardLength: 1)), source: .user, action: .block, countryCode: "FR"),
        ]
        #expect(throws: OrchestratorError.exceedsTotalQuota(expanded: 20, limit: 15)) {
            _ = try StoreOrchestrator.split(rules: rules, expander: expander, quotas: tight)
        }
    }

    @Test func packPrefixRulesAreNotCountedInUserTotal() throws {
        let tight = WildcardQuotas(perPattern: 10_000, totalUser: 5, minFixedDigits: 6)
        let rules: [BlockRule] = [
            .init(kind: .prefix(.init(fixedDigits: "33162999", wildcardLength: 0)), source: .user, action: .block, countryCode: "FR"),
            .init(kind: .prefix(.init(fixedDigits: "44712345", wildcardLength: 2)), source: .pack(packId: "uk.test"), action: .block, countryCode: "GB"),
        ]
        let (block, _) = try StoreOrchestrator.split(rules: rules, expander: expander, quotas: tight)
        #expect(RangeSet.total(block) == 1 + 100)
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
        #expect(keptIds == [1, 2])
    }

    @Test func filterByPackActivationKeepsAllWhenNoneDisabled() {
        let rules: [BlockRule] = [
            .init(kind: .exact(E164(1)!), source: .user, action: .block, countryCode: "FR"),
            .init(kind: .exact(E164(2)!), source: .pack(packId: "fr.arcep"), action: .block, countryCode: "FR"),
        ]
        let packs: [InstalledPack] = [
            InstalledPack(id: "fr.arcep", version: "v1", country: "FR", enabled: true, installedAt: Date()),
        ]
        #expect(StoreOrchestrator.filterByPackActivation(rules: rules, packs: packs).count == 2)
    }

    @Test func sourcesListsDistinctOrigins() {
        let rules: [BlockRule] = [
            .init(kind: .exact(E164(1)!), source: .user, action: .block, countryCode: "FR"),
            .init(kind: .exact(E164(2)!), source: .pack(packId: "fr.arcep"), action: .block, countryCode: "FR"),
            .init(kind: .exact(E164(3)!), source: .pack(packId: "fr.arcep"), action: .block, countryCode: "FR"),
        ]
        #expect(StoreOrchestrator.sources(of: rules) == ["pack:fr.arcep", "user"])
    }

    // MARK: - Live cycle

    struct Harness {
        let root: URL
        let container: SharedContainer
        let hub = StoreStatusHub()
        let reloadCalls = LockIsolated(0)
        let rules = LockIsolated([BlockRule]())

        init() throws {
            root = URL(filePath: NSTemporaryDirectory()).appendingPathComponent("WildCallTest-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            container = .ephemeral(root: root)
        }

        func tearDown() { try? FileManager.default.removeItem(at: root) }

        func orchestrator(
            reload: @escaping @Sendable () async throws -> Void = {}
        ) -> StoreOrchestrator {
            StoreOrchestrator.live(
                repository: RulesRepository(
                    fetchAll: { rules.value },
                    insert: { _ in }, delete: { _ in }, update: { _ in }
                ),
                packsRepository: .inMemory,
                container: container,
                reloader: ExtensionReloader(
                    reload: { reloadCalls.withValue { $0 += 1 }; try await reload() },
                    getEnabledStatus: { .enabled }
                ),
                expander: .live,
                quotas: .default,
                status: hub.client,
                now: { Date(timeIntervalSince1970: 1_700_000_000) }
            )
        }
    }

    @Test func rebuildAndReloadHappyPath() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        harness.rules.withValue {
            $0 = [
                BlockRule(kind: .exact(E164(33_612_345_678)!), source: .user, action: .block, countryCode: "FR"),
                BlockRule(kind: .prefix(.init(fixedDigits: "33162", wildcardLength: 6)), source: .user, action: .block, countryCode: "FR"),
            ]
        }

        let summary = try await harness.orchestrator().rebuildAndReload()
        #expect(summary.blockCount == 1_000_001)
        #expect(summary.block.rangeCount == 2)
        #expect(summary.identCount == 0)
        #expect(harness.reloadCalls.value == 1)

        let reader = try BlockStoreReader(url: harness.container.blockStoreURL())
        #expect(reader.ranges == [NumberRange(start: 33_162_000_000, count: 1_000_000), .single(33_612_345_678)])

        let manifest = try StoreManifest.load(from: harness.container.manifestURL())
        #expect(manifest?.formatVersion == StoreManifest.currentFormatVersion)
        #expect(manifest?.block.count == 1_000_001)
        #expect(manifest?.lastReload?.succeeded == true)
        #expect(manifest?.sources == ["user"])
        #expect(harness.hub.current == .ready(numbers: 1_000_001, date: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    @Test func reloadFailureIsRecordedAndPublished() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let orchestrator = harness.orchestrator(reload: { throw ReloadFailure.extensionDisabled })

        await #expect(throws: ReloadFailure.extensionDisabled) {
            try await orchestrator.rebuildAndReload()
        }
        let manifest = try StoreManifest.load(from: harness.container.manifestURL())
        #expect(manifest?.lastReload?.succeeded == false)
        #expect(manifest?.lastReload?.failure == .extensionDisabled)
        #expect(harness.hub.current == .failed(.extensionDisabled, numbers: 0, date: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    @Test func statusStreamSeesEveryPhase() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let orchestrator = harness.orchestrator()

        let stream = harness.hub.stream()
        _ = try await orchestrator.rebuildAndReload()

        var seen: [StoreStatus] = []
        for await status in stream {
            seen.append(status)
            if case .ready = status { break }
        }
        #expect(seen == [
            .unknown,
            .building,
            .reloading(numbers: 0),
            .ready(numbers: 0, date: Date(timeIntervalSince1970: 1_700_000_000)),
        ])
    }

    @Test func requestRebuildCoalescesBurstsAndSerializesReloads() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let gate = AsyncGate()
        let orchestrator = harness.orchestrator(reload: { await gate.wait() })

        // First request starts a cycle and blocks inside reload.
        await orchestrator.requestRebuild()
        await waitUntil { harness.reloadCalls.value == 1 }

        // A burst of requests while the first cycle runs schedules exactly one more.
        for _ in 0..<5 { await orchestrator.requestRebuild() }

        await gate.open()
        await waitUntil { harness.reloadCalls.value == 2 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(harness.reloadCalls.value == 2)
        if case .ready = harness.hub.current {} else {
            Issue.record("expected ready, got \(harness.hub.current)")
        }
    }
}

actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let resumed = waiters
        waiters.removeAll()
        for waiter in resumed { waiter.resume() }
    }
}

func waitUntil(timeout: Duration = .seconds(5), _ condition: @escaping @Sendable () -> Bool) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
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
