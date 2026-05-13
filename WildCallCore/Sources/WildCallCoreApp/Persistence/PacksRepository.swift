import Dependencies
import Foundation
import IssueReporting
import SwiftData

public struct PacksRepository: Sendable {
    public var fetchAll: @Sendable () async throws -> [InstalledPack]
    public var fetch: @Sendable (_ id: String) async throws -> InstalledPack?
    public var insert: @Sendable (InstalledPack) async throws -> Void
    public var setEnabled: @Sendable (_ id: String, _ enabled: Bool) async throws -> Void
    public var delete: @Sendable (_ id: String) async throws -> Void

    public init(
        fetchAll: @escaping @Sendable () async throws -> [InstalledPack],
        fetch: @escaping @Sendable (String) async throws -> InstalledPack?,
        insert: @escaping @Sendable (InstalledPack) async throws -> Void,
        setEnabled: @escaping @Sendable (String, Bool) async throws -> Void,
        delete: @escaping @Sendable (String) async throws -> Void
    ) {
        self.fetchAll = fetchAll
        self.fetch = fetch
        self.insert = insert
        self.setEnabled = setEnabled
        self.delete = delete
    }
}

@ModelActor
public actor PacksActor {
    public func fetchAll() throws -> [InstalledPack] {
        let descriptor = FetchDescriptor<PackRecord>(
            sortBy: [SortDescriptor(\.installedAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map { $0.toValue() }
    }

    public func fetch(id: String) throws -> InstalledPack? {
        let descriptor = FetchDescriptor<PackRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first?.toValue()
    }

    public func insert(_ pack: InstalledPack) throws {
        modelContext.insert(PackRecord.from(pack))
        try modelContext.save()
    }

    public func setEnabled(id: String, enabled: Bool) throws {
        let descriptor = FetchDescriptor<PackRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let record = try modelContext.fetch(descriptor).first else { return }
        record.enabled = enabled
        try modelContext.save()
    }

    public func delete(id: String) throws {
        let descriptor = FetchDescriptor<PackRecord>(
            predicate: #Predicate { $0.id == id }
        )
        for record in try modelContext.fetch(descriptor) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}

extension PacksRepository {
    public static func live(container: ModelContainer) -> PacksRepository {
        let actor = PacksActor(modelContainer: container)
        return PacksRepository(
            fetchAll: { try await actor.fetchAll() },
            fetch: { try await actor.fetch(id: $0) },
            insert: { try await actor.insert($0) },
            setEnabled: { try await actor.setEnabled(id: $0, enabled: $1) },
            delete: { try await actor.delete(id: $0) }
        )
    }

    public static let inMemory: PacksRepository = {
        let container = try! ModelContainer(
            for: PackRecord.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        return .live(container: container)
    }()
}

extension PacksRepository: DependencyKey {
    public static let liveValue: PacksRepository = .inMemory
    public static let testValue: PacksRepository = PacksRepository(
        fetchAll: { unimplemented("PacksRepository.fetchAll", placeholder: []) },
        fetch: { _ in unimplemented("PacksRepository.fetch", placeholder: nil) },
        insert: { _ in unimplemented("PacksRepository.insert") },
        setEnabled: { _, _ in unimplemented("PacksRepository.setEnabled") },
        delete: { _ in unimplemented("PacksRepository.delete") }
    )
}

extension DependencyValues {
    public var packsRepository: PacksRepository {
        get { self[PacksRepository.self] }
        set { self[PacksRepository.self] = newValue }
    }
}
