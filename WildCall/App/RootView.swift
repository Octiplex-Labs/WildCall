import ComposableArchitecture
import SwiftUI
import WildCallCoreApp

struct RootView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                OnboardingBanner(store: store)
                RulesListView(
                    store: store.scope(state: \.rules, action: \.rules)
                )
            }
            .background(Color(.systemGroupedBackground))
        }
        .task { await store.send(.task).finish() }
    }
}
