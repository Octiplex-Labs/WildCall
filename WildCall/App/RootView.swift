import ComposableArchitecture
import SwiftUI
import WildCallCoreApp

struct RootView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        TabView {
            NavigationStack {
                VStack(spacing: 12) {
                    OnboardingBanner(store: store)
                    RulesListView(
                        store: store.scope(state: \.rules, action: \.rules)
                    )
                }
                .background(Color(.systemGroupedBackground))
            }
            .tabItem {
                Label("Filtres", systemImage: "phone.down.fill")
            }

            PacksView(store: store.scope(state: \.packs, action: \.packs))
                .tabItem {
                    Label("Réglages", systemImage: "gearshape")
                }
        }
        .tint(.indigo)
        .task { await store.send(.task).finish() }
    }
}
