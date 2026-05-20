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
                        description: Text("Synchronisez pour récupérer les packs communautaires.")
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

                Section {
                    Button {
                        store.send(.syncButtonTapped)
                    } label: {
                        HStack {
                            if store.isSyncing {
                                ProgressView()
                                Text("Synchronisation…")
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Synchroniser maintenant")
                            }
                            Spacer()
                        }
                    }
                    .disabled(store.isSyncing)

                    if let lastSync = store.lastSync {
                        HStack {
                            Text("Dernière synchronisation")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                    }
                } header: {
                    Text("Mises à jour")
                } footer: {
                    syncFooterView
                }
            }
            .navigationTitle("Réglages")
            .task { await store.send(.task).finish() }
        }
    }

    @ViewBuilder private var syncFooterView: some View {
        if let error = store.lastSyncError {
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        } else if let summary = store.lastSyncSummary {
            if summary.didChangeAnything {
                let parts = [
                    summary.added.isEmpty ? nil : "\(summary.added.count) ajouté(s)",
                    summary.upgraded.isEmpty ? nil : "\(summary.upgraded.count) mis à jour"
                ].compactMap(\.self)
                Text(parts.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !summary.failed.isEmpty {
                Text("\(summary.failed.count) pack(s) en erreur — voir les logs.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("Tout est à jour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("La synchronisation récupère les nouveaux packs et les mises à jour depuis Octiplex.")
                .font(.caption)
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
