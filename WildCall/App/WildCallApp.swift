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
            container = try ModelContainer(for: BlockRuleRecord.self)
        } catch {
            fatalError("Failed to create persistent ModelContainer: \(error)")
        }
        self.modelContainer = container

        self.store = withDependencies {
            $0.rulesRepository = .live(container: container)
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
        }
    }
}
