import ComposableArchitecture
import Dependencies
import IssueReporting
import SwiftData
import SwiftUI
import WildCallCoreApp
import WildCallCoreShared

@main
struct WildCallApp: App {
    let modelContainer: ModelContainer
    let store: StoreOf<AppFeature>

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: BlockRuleRecord.self, PackRecord.self, TrustedKeyRecord.self)
        } catch {
            fatalError("Failed to create persistent ModelContainer: \(error)")
        }
        self.modelContainer = container

        self.store = withDependencies {
            $0.rulesRepository = .live(container: container)
            $0.packsRepository = .live(container: container)
            $0.trustedKeyStore = .live(container: container)
        } operation: {
            Store(initialState: AppFeature.State()) {
                AppFeature()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .modelContainer(modelContainer)
                .task { await runBootstrap() }
                .task {
                    // Register the BGAppRefreshTask handler once per process
                    // and submit a request for the next opportunity.
                    PackRefreshScheduler.live.register()
                    PackRefreshScheduler.live.schedule()
                }
        }
    }

    @Sendable
    private func runBootstrap() async {
        // Discover every embedded *.source.json under the Packs/ bundle
        // folder. Adding a new country is as simple as dropping a new
        // `<id>.source.json` in `Packs/` and rebuilding : no code change.
        let urls = (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasSuffix(".source.json") }

        guard !urls.isEmpty else {
            reportIssue("No embedded *.source.json packs found in bundle")
            return
        }

        var manifests: [PackManifest] = []
        for url in urls {
            do {
                manifests.append(try PackManifest.load(from: url))
            } catch {
                reportIssue("Embedded pack \(url.lastPathComponent) failed to decode: \(error)")
            }
        }

        do {
            _ = try await withDependencies {
                $0.rulesRepository = .live(container: modelContainer)
                $0.packsRepository = .live(container: modelContainer)
            } operation: {
                try await PackBootstrap.live.run(manifests)
            }
        } catch {
            reportIssue("PackBootstrap failed: \(error)")
        }
    }
}
