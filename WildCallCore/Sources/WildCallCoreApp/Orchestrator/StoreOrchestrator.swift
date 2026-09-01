import Dependencies
import Foundation
import IssueReporting
import WildCallCoreShared

public struct RebuildSummary: Equatable, Sendable {
    public let blockCount: Int
    public let identCount: Int
    public let block: BlobBuildSummary
    public let ident: BlobBuildSummary

    public init(
        blockCount: Int,
        identCount: Int,
        block: BlobBuildSummary,
        ident: BlobBuildSummary
    ) {
        self.blockCount = blockCount
        self.identCount = identCount
        self.block = block
        self.ident = ident
    }

    public var totalNumbers: Int { blockCount + identCount }
}

public enum OrchestratorError: Error, Equatable, Sendable {
    case exceedsTotalQuota(expanded: Int, limit: Int)
}

/// Owns the "rules → shared store → reloadExtension" cycle.
///
/// - `rebuildAndReload` runs the full cycle and waits for iOS to finish
///   ingesting. Used where the caller must know the outcome before
///   continuing (background refresh, tests).
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
                status.set(.failed(.unknown(String(describing: error)), numbers: 0, date: now()))
                throw error
            }
            WildCallLog.info("Rebuild: store root \(manifestURL.deletingLastPathComponent().path)")
            let summary: RebuildSummary
            var manifest: StoreManifest
            do {
                let rules = try await repository.fetchAll()
                WildCallLog.info("Rebuild: \(rules.count) rules fetched")
                let packs = try await packsRepository.fetchAll()
                let activeRules = Self.filterByPackActivation(rules: rules, packs: packs)
                var (blockRanges, identRanges) = try Self.split(
                    rules: activeRules,
                    expander: expander,
                    quotas: quotas
                )
                if let cap = DebugProbe.maxNumbers {
                    // Measurement harness : WILDCALL_DEBUG_MAX_NUMBERS caps the
                    // volume sent to iOS so the extension's ceiling can be
                    // bisected on device. Debug builds only.
                    blockRanges = RangeSet.truncate(blockRanges, to: cap)
                    identRanges = []
                    WildCallLog.info("Rebuild: DEBUG cap applied, \(RangeSet.total(blockRanges)) numbers")
                }

                let blockSummary = try BlockStoreBuilder().build(ranges: blockRanges, to: container.blockStoreURL())
                let identSummary = try IdentStoreBuilder().build(entries: identRanges, to: container.identStoreURL())

                manifest = StoreManifest(
                    buildDate: now(),
                    block: .init(count: blockSummary.count, ranges: blockSummary.rangeCount, bytes: blockSummary.bytesWritten, sha256: blockSummary.sha256),
                    ident: .init(count: identSummary.count, ranges: identSummary.rangeCount, bytes: identSummary.bytesWritten, sha256: identSummary.sha256),
                    sources: Self.sources(of: activeRules)
                )
                try manifest.write(to: manifestURL)
                WildCallLog.info("Rebuild: block \(blockSummary.count) numbers / \(blockSummary.rangeCount) ranges, ident \(identSummary.count) / \(identSummary.rangeCount)")

                summary = RebuildSummary(
                    blockCount: blockSummary.count,
                    identCount: identSummary.count,
                    block: blockSummary,
                    ident: identSummary
                )
            } catch {
                WildCallLog.error("Rebuild failed before reload: \(error)")
                status.set(.failed(.unknown(String(describing: error)), numbers: 0, date: now()))
                throw error
            }

            // iOS rejects the whole list past the ceiling, after ingesting it
            // for tens of seconds : fail fast with the same typed error so the
            // UI can explain and the user can disable a pack.
            if summary.totalNumbers > quotas.maxExtensionEntries {
                WildCallLog.error("Reload skipped: \(summary.totalNumbers) numbers exceed the extension ceiling \(quotas.maxExtensionEntries)")
                manifest.lastReload = .init(date: now(), succeeded: false, failure: .maximumEntriesExceeded)
                try? manifest.write(to: manifestURL)
                status.set(.failed(.maximumEntriesExceeded, numbers: summary.totalNumbers, date: now()))
                throw ReloadFailure.maximumEntriesExceeded
            }

            status.set(.reloading(numbers: summary.totalNumbers))
            WildCallLog.info("Reload: asking iOS to ingest \(summary.totalNumbers) numbers")
            let reloadStart = now()
            do {
                try await reloader.reload()
                WildCallLog.info("Reload: completed in \(Int(now().timeIntervalSince(reloadStart))) s")
            } catch {
                let failure = ReloadFailure(error)
                WildCallLog.error("Reload failed: \(failure)")
                manifest.lastReload = .init(date: now(), succeeded: false, failure: failure)
                try? manifest.write(to: manifestURL)
                status.set(.failed(failure, numbers: summary.totalNumbers, date: now()))
                throw failure
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
