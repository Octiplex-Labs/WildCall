import ComposableArchitecture
import SwiftUI
import WildCallCoreApp

struct RootView: View {
    @Bindable var store: StoreOf<AppFeature>
    @AppStorage("wildcall.has_seen_onboarding") private var hasSeenOnboarding: Bool = false
    @State private var isShowingOnboarding: Bool = false

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
        .onAppear {
            if !hasSeenOnboarding {
                isShowingOnboarding = true
            }
        }
        .onChange(of: hasSeenOnboarding) { _, newValue in
            // Watch for the user tapping 'Revoir l'introduction' in Réglages.
            if !newValue {
                isShowingOnboarding = true
            }
        }
        .onOpenURL { url in
            store.send(.onOpenURL(url))
        }
        .sheet(item: $store.scope(state: \.importPresentation, action: \.importPresentation)) { importStore in
            PackImportSheet(store: importStore)
        }
        .fullScreenCover(isPresented: $isShowingOnboarding, onDismiss: {
            hasSeenOnboarding = true
        }) {
            OnboardingFlowView(isPresented: $isShowingOnboarding)
        }
    }
}
