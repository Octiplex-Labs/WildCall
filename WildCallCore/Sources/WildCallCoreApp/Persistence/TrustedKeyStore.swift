import Dependencies
import Foundation
import SwiftData

public struct TrustedKeyStore: Sendable {
    public var fetchAll: @Sendable () async throws -> [TrustedKey]
    public var fetch: @Sendable (_ packId: String) async throws -> TrustedKey?
    public var pin: @Sendable (TrustedKey) async throws -> Void
    public var unpin: @Sendable (_ packId: String) async throws -> Void

    public init(
        fetchAll: @escaping @Sendable () async throws -> [TrustedKey],
        fetch: @escaping @Sendable (String) async throws -> TrustedKey?,
        pin: @escaping @Sendable (TrustedKey) async throws -> Void,
        unpin: @escaping @Sendable (String) async throws -> Void
    ) {
        self.fetchAll = fetchAll
        self.fetch = fetch
        self.pin = pin
        self.unpin = unpin
    }
}

@ModelActor
public actor TrustedKeysActor {
    public func fetchAll() throws -> [TrustedKey] {
        let descriptor = FetchDescriptor<TrustedKeyRecord>(
            sortBy: [SortDescriptor(\.pinnedAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map { $0.toValue() }
    }

    public func fetch(packId: String) throws -> TrustedKey? {
        let descriptor = FetchDescriptor<TrustedKeyRecord>(
            predicate: #Predicate { $0.packId == packId }
        )
        return try modelContext.fetch(descriptor).first?.toValue()
    }

    public func pin(_ key: TrustedKey) throws {
        // Upsert: delete any existing, insert fresh. Callers must verify the
        // overwrite policy themselves (a mismatched key import should fail
        // earlier, not silently overwrite the pin).
        let id = key.packId
        let existing = try modelContext.fetch(
            FetchDescriptor<TrustedKeyRecord>(predicate: #Predicate { $0.packId == id })
        )
        for record in existing {
            modelContext.delete(record)
        }
        modelContext.insert(TrustedKeyRecord.from(key))
        try modelContext.save()
    }

    public func unpin(packId: String) throws {
        let descriptor = FetchDescriptor<TrustedKeyRecord>(
            predicate: #Predicate { $0.packId == packId }
        )
        for record in try modelContext.fetch(descriptor) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}

extension TrustedKeyStore {
    public static func live(container: ModelContainer) -> TrustedKeyStore {
        let actor = TrustedKeysActor(modelContainer: container)
        return TrustedKeyStore(
            fetchAll: { try await actor.fetchAll() },
            fetch: { try await actor.fetch(packId: $0) },
            pin: { try await actor.pin($0) },
            unpin: { try await actor.unpin(packId: $0) }
        )
    }

    public static let inMemory: TrustedKeyStore = {
        let container = try! ModelContainer(
            for: TrustedKeyRecord.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        return .live(container: container)
    }()
}

extension TrustedKeyStore: DependencyKey {
    public static let liveValue: TrustedKeyStore = .inMemory
    public static let testValue: TrustedKeyStore = TrustedKeyStore(
        fetchAll: { unimplemented("TrustedKeyStore.fetchAll", placeholder: []) },
        fetch: { _ in unimplemented("TrustedKeyStore.fetch", placeholder: nil) },
        pin: { _ in unimplemented("TrustedKeyStore.pin") },
        unpin: { _ in unimplemented("TrustedKeyStore.unpin") }
    )
}

extension DependencyValues {
    public var trustedKeyStore: TrustedKeyStore {
        get { self[TrustedKeyStore.self] }
        set { self[TrustedKeyStore.self] = newValue }
    }
}
