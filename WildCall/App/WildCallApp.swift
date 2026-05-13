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
            container = try ModelContainer(for: BlockRuleRecord.self, PackRecord.self)
        } catch {
            fatalError("Failed to create persistent ModelContainer: \(error)")
        }
        self.modelContainer = container

        self.store = withDependencies {
            $0.rulesRepository = .live(container: container)
            $0.packsRepository = .live(container: container)
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
        }
    }

    @Sendable
    private func runBootstrap() async {
        guard let url = Bundle.main.url(forResource: "prefixes-FR.source", withExtension: "json") else {
            reportIssue("Embedded ARCEP manifest not found in bundle")
            return
        }
        do {
            let manifest = try PackManifest.load(from: url)
            _ = try await withDependencies {
                $0.rulesRepository = .live(container: modelContainer)
                $0.packsRepository = .live(container: modelContainer)
            } operation: {
                try await PackBootstrap.live.run([manifest])
            }
        } catch {
            reportIssue("PackBootstrap failed: \(error)")
        }
    }
}
