import Dependencies
import Foundation
import IssueReporting
import WildCallCoreShared

public struct RebuildSummary: Equatable, Sendable {
    public let blockCount: Int
    public let identCount: Int
    public let block: BlobBuildSummary
    public let ident: BlobBuildSummary
    public let slots: [SlotSummary]

    public struct SlotSummary: Equatable, Sendable {
        public let slot: ExtensionSlot
        public let block: BlobBuildSummary
        public let ident: BlobBuildSummary

        public init(slot: ExtensionSlot, block: BlobBuildSummary, ident: BlobBuildSummary) {
            self.slot = slot
            self.block = block
            self.ident = ident
        }

        public var totalNumbers: Int { block.count + ident.count }
    }

    public init(
        blockCount: Int,
        identCount: Int,
        block: BlobBuildSummary,
        ident: BlobBuildSummary,
        slots: [SlotSummary] = []
    ) {
        self.blockCount = blockCount
        self.identCount = identCount
        self.block = block
        self.ident = ident
        self.slots = slots
    }

    public var totalNumbers: Int { blockCount + identCount }
}

public enum OrchestratorError: Error, Equatable, Sendable {
    case exceedsTotalQuota(expanded: Int, limit: Int)
}

/// Owns the "rules → per-slot shared stores → reloadExtension ×N" cycle.
///
/// - `rebuildAndReload` runs the full cycle and waits for iOS to finish
///   ingesting every slot. Used where the caller must know the outcome
///   before continuing (background refresh, tests).
/// - `requestRebuild` returns immediately. Cycles are serialized (CallKit
///   rejects concurrent reloads with `currentlyLoading`) and coalesced :
///   ten quick edits produce at most one extra cycle after the running one.
///   Progress and failures are published through `StoreStatusClient`.
public struct StoreOrchestrator: Sendable {
    public var rebuildAndReload: @Sendable () async throws -> RebuildSummary
    public var requestRebuild: @Sendable () async -> Void

    public init(
        rebuildAndReload: @escaping @Sendable () async throws -> RebuildSummary,
        requestRebuild: (@Sendable () async -> Void)? = nil
    ) {
        self.rebuildAndReload = rebuildAndReload
        self.requestRebuild = requestRebuild ?? { _ = try? await rebuildAndReload() }
    }
}

extension StoreOrchestrator {
    public static func live(
        repository: RulesRepository,
        packsRepository: PacksRepository,
        container: SharedContainer,
        reloader: ExtensionReloader,
        expander: WildcardExpander,
        quotas: WildcardQuotas,
        status: StoreStatusClient,
        slots: [ExtensionSlot] = ExtensionSlot.all,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> StoreOrchestrator {
        let serializer = RebuildSerializer()

        @Sendable func performCycle() async throws -> RebuildSummary {
            status.set(.building)
            let manifestURL: URL
            do {
                manifestURL = try container.manifestURL()
            } catch {
                WildCallLog.error("App Group container unavailable: \(error)")
                status.set(.failed(.unknown(String(describing: error)), numbers: 0, date: now(), slot: nil))
                throw error
            }
            WildCallLog.info("Rebuild: store root \(manifestURL.deletingLastPathComponent().path)")

            // 1. Rules → normalized ranges.
            let blockRanges: [NumberRange]
            let identRanges: [IdentRange]
            let sources: [String]
            do {
                let rules = try await repository.fetchAll()
                WildCallLog.info("Rebuild: \(rules.count) rules fetched")
                let packs = try await packsRepository.fetchAll()
                let activeRules = Self.filterByPackActivation(rules: rules, packs: packs)
                var split = try Self.split(rules: activeRules, expander: expander, quotas: quotas)
                if let cap = DebugProbe.maxNumbers {
                    // Measurement harness : WILDCALL_DEBUG_MAX_NUMBERS caps the
                    // volume sent to iOS so the extension's ceiling can be
                    // bisected on device. Debug builds only.
                    split.block = RangeSet.truncate(split.block, to: cap)
                    split.ident = []
                    WildCallLog.info("Rebuild: DEBUG cap applied, \(RangeSet.total(split.block)) numbers")
                }
                blockRanges = split.block
                identRanges = split.ident
                sources = Self.sources(of: activeRules)
            } catch {
                WildCallLog.error("Rebuild failed while reading rules: \(error)")
                status.set(.failed(.unknown(String(describing: error)), numbers: 0, date: now(), slot: nil))
                throw error
            }

            // 2. Spread across the slots. Past the total capacity iOS would
            //    reject the last slot after ingesting for seconds : fail fast
            //    with the same typed error so the UI can explain.
            let total = Int(RangeSet.total(blockRanges) + RangeSet.total(identRanges.map(\.range)))
            let payloads: [SlotPayload]
            do {
                payloads = try SlotDistributor.distribute(
                    block: blockRanges,
                    ident: identRanges,
                    slots: slots,
                    perSlot: Int64(quotas.maxExtensionEntries)
                )
            } catch {
                WildCallLog.error("Reload skipped: \(total) numbers exceed the capacity of \(slots.count) extension(s)")
                var manifest = StoreManifest(
                    buildDate: now(), block: .init(count: total, ranges: blockRanges.count, bytes: 0, sha256: ""),
                    ident: .empty, sources: sources
                )
                manifest.lastReload = .init(date: now(), succeeded: false, failure: .maximumEntriesExceeded)
                try? manifest.write(to: manifestURL)
                status.set(.failed(.maximumEntriesExceeded, numbers: total, date: now(), slot: nil))
                throw ReloadFailure.maximumEntriesExceeded
            }

            // 3. Write one pair of files per slot.
            var slotSummaries: [RebuildSummary.SlotSummary] = []
            do {
                for payload in payloads {
                    let blockSummary = try BlockStoreBuilder().build(ranges: payload.block, to: container.blockStoreURL(payload.slot))
                    let identSummary = try IdentStoreBuilder().build(entries: payload.ident, to: container.identStoreURL(payload.slot))
                    slotSummaries.append(.init(slot: payload.slot, block: blockSummary, ident: identSummary))
                    WildCallLog.info("Rebuild: slot \(payload.slot.index) block \(blockSummary.count) numbers / \(blockSummary.rangeCount) ranges, ident \(identSummary.count) / \(identSummary.rangeCount)")
                }
            } catch {
                WildCallLog.error("Rebuild failed while writing stores: \(error)")
                status.set(.failed(.unknown(String(describing: error)), numbers: total, date: now(), slot: nil))
                throw error
            }

            let blockTotal = Self.aggregate(slotSummaries.map(\.block))
            let identTotal = Self.aggregate(slotSummaries.map(\.ident))
            var manifest = StoreManifest(
                buildDate: now(),
                block: .init(count: blockTotal.count, ranges: blockTotal.rangeCount, bytes: blockTotal.bytesWritten, sha256: blockTotal.sha256),
                ident: .init(count: identTotal.count, ranges: identTotal.rangeCount, bytes: identTotal.bytesWritten, sha256: identTotal.sha256),
                slots: slotSummaries.map {
                    .init(
                        slot: $0.slot.index,
                        block: .init(count: $0.block.count, ranges: $0.block.rangeCount, bytes: $0.block.bytesWritten, sha256: $0.block.sha256),
                        ident: .init(count: $0.ident.count, ranges: $0.ident.rangeCount, bytes: $0.ident.bytesWritten, sha256: $0.ident.sha256)
                    )
                },
                sources: sources
            )
            try? manifest.write(to: manifestURL)
            let summary = RebuildSummary(
                blockCount: blockTotal.count,
                identCount: identTotal.count,
                block: blockTotal,
                ident: identTotal,
                slots: slotSummaries
            )

            // 4. Reload every slot, sequentially : CallKit serves one load at a time.
            for slotSummary in slotSummaries {
                let slot = slotSummary.slot
                status.set(.reloading(numbers: summary.totalNumbers, slot: slot.index))
                WildCallLog.info("Reload: slot \(slot.index), asking iOS to ingest \(slotSummary.totalNumbers) numbers")
                let reloadStart = now()
                do {
                    try await reloader.reload(slot)
                    WildCallLog.info("Reload: slot \(slot.index) completed in \(Int(now().timeIntervalSince(reloadStart))) s")
                } catch {
                    let failure = ReloadFailure(error)
                    WildCallLog.error("Reload: slot \(slot.index) failed: \(failure)")
                    manifest.lastReload = .init(date: now(), succeeded: false, failure: failure, slot: slot.index)
                    try? manifest.write(to: manifestURL)
                    status.set(.failed(failure, numbers: summary.totalNumbers, date: now(), slot: slot.index))
                    throw failure
                }
            }

            manifest.lastReload = .init(date: now(), succeeded: true)
            try? manifest.write(to: manifestURL)
            status.set(.ready(numbers: summary.totalNumbers, date: now()))
            return summary
        }

        return StoreOrchestrator(
            rebuildAndReload: {
                await serializer.acquire()
                do {
                    let summary = try await performCycle()
                    await serializer.release()
                    return summary
                } catch {
                    await serializer.release()
                    throw error
                }
            },
            requestRebuild: {
                guard await serializer.markPending() else { return }
                Task {
                    await serializer.acquire()
                    await serializer.clearPending()
                    do {
                        _ = try await performCycle()
                    } catch {
                        // Already surfaced through StoreStatusClient.
                        reportIssue("Store rebuild failed: \(error)")
                    }
                    await serializer.release()
                }
            }
        )
    }

    static func aggregate(_ summaries: [BlobBuildSummary]) -> BlobBuildSummary {
        BlobBuildSummary(
            count: summaries.reduce(0) { $0 + $1.count },
            rangeCount: summaries.reduce(0) { $0 + $1.rangeCount },
            bytesWritten: summaries.reduce(0) { $0 + $1.bytesWritten },
            sha256: summaries.map(\.sha256).joined(separator: "+")
        )
    }

    static func split(
        rules: [BlockRule],
        expander: WildcardExpander,
        quotas: WildcardQuotas
    ) throws -> (block: [NumberRange], ident: [IdentRange]) {
        var block: [NumberRange] = []
        var ident: [IdentRange] = []
        var userExpanded = 0
        block.reserveCapacity(rules.count)

        for rule in rules {
            let range: NumberRange
            switch rule.kind {
            case .exact(let e164):
                range = .single(e164.value)
            case .prefix(let prefix):
                guard let expanded = expander.range(prefix) else {
                    reportIssue("Skipping prefix rule \(rule.id): cannot expand \(prefix)")
                    continue
                }
                if case .user = rule.source {
                    userExpanded += Int(expanded.count)
                    if userExpanded > quotas.totalUser {
                        throw OrchestratorError.exceedsTotalQuota(
                            expanded: userExpanded,
                            limit: quotas.totalUser
                        )
                    }
                }
                range = expanded
            }

            switch rule.action {
            case .block:
                block.append(range)
            case .identify:
                ident.append(IdentRange(range: range, label: rule.label ?? "WildCall"))
            }
        }

        // An explicit "identify" rule wins over blocking : if the user asks
        // to see a label for a number that a pack would block, the call must
        // ring. Ranges are normalized here so the builders receive disjoint
        // input and the two files never overlap.
        let normalizedIdent = RangeSet.normalizeIdent(ident)
        let normalizedBlock = RangeSet.subtract(block, removing: normalizedIdent.map(\.range))
        return (normalizedBlock, normalizedIdent)
    }

    static func filterByPackActivation(
        rules: [BlockRule],
        packs: [InstalledPack]
    ) -> [BlockRule] {
        let disabledIds = Set(packs.filter { !$0.enabled }.map(\.id))
        guard !disabledIds.isEmpty else { return rules }
        return rules.filter { rule in
            if case .pack(let id) = rule.source {
                return !disabledIds.contains(id)
            }
            return true
        }
    }

    static func sources(of rules: [BlockRule]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for rule in rules {
            let name: String
            switch rule.source {
            case .user: name = "user"
            case .pack(let id): name = "pack:\(id)"
            }
            if seen.insert(name).inserted { out.append(name) }
        }
        return out.sorted()
    }
}

/// Serializes rebuild cycles and coalesces pending requests.
actor RebuildSerializer {
    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var hasPendingRequest = false

    func acquire() async {
        while isRunning {
            await withCheckedContinuation { waiters.append($0) }
        }
        isRunning = true
    }

    func release() {
        isRunning = false
        let resumed = waiters
        waiters.removeAll()
        for waiter in resumed { waiter.resume() }
    }

    /// Returns true when the caller should schedule a cycle; false when one
    /// is already queued and will pick up the caller's changes.
    func markPending() -> Bool {
        if hasPendingRequest { return false }
        hasPendingRequest = true
        return true
    }

    func clearPending() {
        hasPendingRequest = false
    }
}

/// Debug-only knobs read from the environment (`devicectl ... --environment-variables`).
enum DebugProbe {
    static var maxNumbers: Int64? {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["WILDCALL_DEBUG_MAX_NUMBERS"],
              let value = Int64(raw) else { return nil }
        return value
        #else
        return nil
        #endif
    }

    static var forceRebuild: Bool {
        #if DEBUG
        return maxNumbers != nil
        #else
        return false
        #endif
    }
}

extension StoreOrchestrator: DependencyKey {
    public static let liveValue: StoreOrchestrator = {
        @Dependency(\.sharedContainer) var container
        @Dependency(\.rulesRepository) var repository
        @Dependency(\.packsRepository) var packsRepository
        @Dependency(\.extensionReloader) var reloader
        @Dependency(\.wildcardExpander) var expander
        @Dependency(\.wildcardQuotas) var quotas
        @Dependency(\.storeStatus) var status
        return .live(
            repository: repository,
            packsRepository: packsRepository,
            container: container,
            reloader: reloader,
            expander: expander,
            quotas: quotas,
            status: status
        )
    }()

    public static let testValue: StoreOrchestrator = StoreOrchestrator(
        rebuildAndReload: {
            unimplemented(
                "StoreOrchestrator.rebuildAndReload",
                placeholder: RebuildSummary(
                    blockCount: 0,
                    identCount: 0,
                    block: BlobBuildSummary(count: 0, bytesWritten: 0, sha256: ""),
                    ident: BlobBuildSummary(count: 0, bytesWritten: 0, sha256: "")
                )
            )
        },
        requestRebuild: { unimplemented("StoreOrchestrator.requestRebuild") }
    )
}

extension DependencyValues {
    public var storeOrchestrator: StoreOrchestrator {
        get { self[StoreOrchestrator.self] }
        set { self[StoreOrchestrator.self] = newValue }
    }
}
