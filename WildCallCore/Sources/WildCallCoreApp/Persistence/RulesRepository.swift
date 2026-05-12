import Dependencies
import Foundation
import IssueReporting
import SwiftData

public struct RulesRepository: Sendable {
    public var fetchAll: @Sendable () async throws -> [BlockRule]
    public var insert: @Sendable (BlockRule) async throws -> Void
    public var delete: @Sendable (UUID) async throws -> Void
    public var update: @Sendable (BlockRule) async throws -> Void

    public init(
        fetchAll: @escaping @Sendable () async throws -> [BlockRule],
        insert: @escaping @Sendable (BlockRule) async throws -> Void,
        delete: @escaping @Sendable (UUID) async throws -> Void,
        update: @escaping @Sendable (BlockRule) async throws -> Void
    ) {
        self.fetchAll = fetchAll
        self.insert = insert
        self.delete = delete
        self.update = update
    }
}

@ModelActor
public actor RulesActor {
    public func fetchAll() throws -> [BlockRule] {
        let descriptor = FetchDescriptor<BlockRuleRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let records = try modelContext.fetch(descriptor)
        return records.compactMap { record in
            do { return try record.toRule() }
            catch {
                reportIssue("Skipping malformed BlockRuleRecord \(record.id): \(error)")
                return nil
            }
        }
    }

    public func insert(_ rule: BlockRule) throws {
        let record = BlockRuleRecord.from(rule)
        modelContext.insert(record)
        try modelContext.save()
    }

    public func delete(id: UUID) throws {
        let descriptor = FetchDescriptor<BlockRuleRecord>(
            predicate: #Predicate { $0.id == id }
        )
        let records = try modelContext.fetch(descriptor)
        for record in records {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    public func update(_ rule: BlockRule) throws {
        let ruleID = rule.id
        let descriptor = FetchDescriptor<BlockRuleRecord>(
            predicate: #Predicate { $0.id == ruleID }
        )
        guard let existing = try modelContext.fetch(descriptor).first else {
            // Insert if not found — keeps API forgiving and idempotent.
            modelContext.insert(BlockRuleRecord.from(rule))
            try modelContext.save()
            return
        }
        let fresh = BlockRuleRecord.from(rule)
        existing.kindRaw = fresh.kindRaw
        existing.e164Value = fresh.e164Value
        existing.prefixDigits = fresh.prefixDigits
        existing.prefixWildcardLength = fresh.prefixWildcardLength
        existing.sourceRaw = fresh.sourceRaw
        existing.actionRaw = fresh.actionRaw
        existing.countryCode = fresh.countryCode
        existing.label = fresh.label
        try modelContext.save()
    }
}

extension RulesRepository {
    public static func live(container: ModelContainer) -> RulesRepository {
        let actor = RulesActor(modelContainer: container)
        return RulesRepository(
            fetchAll: { try await actor.fetchAll() },
            insert: { try await actor.insert($0) },
            delete: { try await actor.delete(id: $0) },
            update: { try await actor.update($0) }
        )
    }

    public static let inMemory: RulesRepository = {
        let container = try! ModelContainer(
            for: BlockRuleRecord.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        return .live(container: container)
    }()
}

extension RulesRepository: DependencyKey {
    public static let liveValue: RulesRepository = .inMemory
    public static let testValue: RulesRepository = RulesRepository(
        fetchAll: { unimplemented("RulesRepository.fetchAll", placeholder: []) },
        insert: { _ in unimplemented("RulesRepository.insert") },
        delete: { _ in unimplemented("RulesRepository.delete") },
        update: { _ in unimplemented("RulesRepository.update") }
    )
}

extension DependencyValues {
    public var rulesRepository: RulesRepository {
        get { self[RulesRepository.self] }
        set { self[RulesRepository.self] = newValue }
    }
}
