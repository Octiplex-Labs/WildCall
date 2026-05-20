import Dependencies
import Foundation

/// URL used for the Octiplex remote pack index. Packs are co-hosted with the
/// app in `Octiplex-Labs/WildCall/dist/packs/` (separate from the
/// capital-`Packs/` folder which holds the *embedded* manifest sources);
/// this points to the index JSON served via GitHub raw. The `dist/packs/`
/// folder must exist on `main` and contain `index.json` (shape: `PackIndex`).
public let octiplexPackIndexURL = URL(string: "https://raw.githubusercontent.com/Octiplex-Labs/WildCall/main/dist/packs/index.json")!

public struct PackIndexFetcher: Sendable {
    public var fetch: @Sendable () async throws -> PackIndex

    public init(fetch: @escaping @Sendable () async throws -> PackIndex) {
        self.fetch = fetch
    }
}

extension PackIndexFetcher {
    public static let live = PackIndexFetcher {
        let (data, response) = try await URLSession.shared.data(from: octiplexPackIndexURL)
        try TransportError.checkHTTPStatus(response)
        return try JSONDecoder().decode(PackIndex.self, from: data)
    }
}

extension PackIndexFetcher: DependencyKey {
    public static let liveValue: PackIndexFetcher = .live
    public static let testValue: PackIndexFetcher = PackIndexFetcher {
        unimplemented("PackIndexFetcher.fetch", placeholder: PackIndex(version: 1, updatedAt: "", packs: []))
    }
}

extension DependencyValues {
    public var packIndexFetcher: PackIndexFetcher {
        get { self[PackIndexFetcher.self] }
        set { self[PackIndexFetcher.self] = newValue }
    }
}

public struct PackFetcher: Sendable {
    public var fetch: @Sendable (_ url: URL) async throws -> Data

    public init(fetch: @escaping @Sendable (URL) async throws -> Data) {
        self.fetch = fetch
    }
}

extension PackFetcher {
    public static let live = PackFetcher { url in
        let (data, response) = try await URLSession.shared.data(from: url)
        try TransportError.checkHTTPStatus(response)
        return data
    }
}

extension PackFetcher: DependencyKey {
    public static let liveValue: PackFetcher = .live
    public static let testValue: PackFetcher = PackFetcher { _ in
        unimplemented("PackFetcher.fetch", placeholder: Data())
    }
}

extension DependencyValues {
    public var packFetcher: PackFetcher {
        get { self[PackFetcher.self] }
        set { self[PackFetcher.self] = newValue }
    }
}

public enum TransportError: Error, Equatable {
    case notHTTP
    case status(Int)

    static func checkHTTPStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw TransportError.notHTTP }
        guard (200..<300).contains(http.statusCode) else { throw TransportError.status(http.statusCode) }
    }
}
