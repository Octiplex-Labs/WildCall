import ComposableArchitecture
import SwiftUI
import WildCallCoreApp

struct PacksView: View {
    @Bindable var store: StoreOf<PacksFeature>

    var body: some View {
        NavigationStack {
            List {
                if store.packs.isEmpty, store.isLoading {
                    HStack {
                        ProgressView()
                        Text("Chargement des packs…")
                            .foregroundStyle(.secondary)
                    }
                } else if store.packs.isEmpty {
                    ContentUnavailableView(
                        "Aucun pack installé",
                        systemImage: "shippingbox",
                        description: Text("Les packs communautaires arriveront dans une phase future.")
                    )
                } else {
                    Section {
                        ForEach(store.packs) { pack in
                            PackRow(
                                pack: pack,
                                isToggling: store.togglingId == pack.id,
                                onToggle: { newValue in
                                    store.send(.toggle(id: pack.id, enabled: newValue))
                                }
                            )
                        }
                    } header: {
                        Text("Packs installés")
                    } footer: {
                        Text("Les packs désactivés ne contribuent plus à la liste de blocage. Les règles que vous avez ajoutées vous-même ne sont pas affectées.")
                    }
                }
            }
            .navigationTitle("Réglages")
            .task { await store.send(.task).finish() }
        }
    }
}

private struct PackRow: View {
    let pack: InstalledPack
    let isToggling: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(pack.id)
                    .font(.body.monospaced())
                Text("\(pack.country) · version \(pack.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isToggling {
                ProgressView()
            } else {
                Toggle("", isOn: Binding(
                    get: { pack.enabled },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
            }
        }
        .padding(.vertical, 2)
    }
}
