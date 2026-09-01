import ComposableArchitecture
import Dependencies
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

        // Every dependency that reaches SwiftData is bound here, once, so the
        // BGAppRefreshTask handler and the store share the same repositories.
        prepareDependencies {
            $0.rulesRepository = .live(container: container)
            $0.packsRepository = .live(container: container)
            $0.trustedKeyStore = .live(container: container)
        }

        self.store = Store(initialState: AppFeature.State()) {
            AppFeature()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .modelContainer(modelContainer)
                .task {
                    // Register the BGAppRefreshTask handler once per process
                    // and submit a request for the next opportunity.
                    PackRefreshScheduler.live.register()
                    PackRefreshScheduler.live.schedule()
                }
        }
    }
}
