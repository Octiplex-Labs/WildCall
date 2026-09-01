import ComposableArchitecture
import SwiftUI
import WildCallCoreApp

struct PacksView: View {
    @Bindable var store: StoreOf<PacksFeature>
    let appStore: StoreOf<AppFeature>

    var body: some View {
        NavigationStack {
            List {
                FilterStatusSection(store: appStore)

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
                                numberCount: store.numberCounts[pack.id],
                                isToggling: store.togglingId == pack.id,
                                onToggle: { newValue in
                                    store.send(.toggle(id: pack.id, enabled: newValue))
                                }
                            )
                        }
                    } header: {
                        Text("Packs installés")
                    } footer: {
                        Text("WildCall peut envoyer \(FilterStatusFormatting.count(WildcardQuotas.default.totalCapacity)) numéros à iOS (\(FilterStatusFormatting.count(enabledPackNumbers)) actuellement via les packs). Les packs désactivés ne contribuent plus à la liste de blocage. Vos propres règles ne sont pas affectées.")
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
                    .accessibilityLabel(Text(store.isSyncing ? "Synchronisation en cours" : "Synchroniser maintenant"))
                    .accessibilityHint(Text("Récupère les nouveaux packs et les mises à jour depuis Octiplex."))

                    Button {
                        store.send(.addByURLTapped)
                    } label: {
                        HStack {
                            Image(systemName: "link.badge.plus")
                            Text("Ajouter un pack par URL…")
                            Spacer()
                        }
                    }
                    .accessibilityHint(Text("Ouvre un formulaire pour télécharger un pack signé depuis une URL externe."))

                    if let lastSync = store.lastSync {
                        HStack {
                            Text("Dernière synchronisation")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Mises à jour")
                } footer: {
                    syncFooterView
                }

                Section {
                    Button {
                        store.send(.exportButtonTapped)
                    } label: {
                        HStack {
                            if store.isExporting {
                                ProgressView()
                                Text("Préparation…")
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                Text("Exporter mes règles…")
                            }
                            Spacer()
                        }
                    }
                    .disabled(store.isExporting)
                    .accessibilityLabel(Text(store.isExporting ? "Préparation de l'export" : "Exporter mes règles"))
                    .accessibilityHint(Text("Prépare un fichier JSON contenant les règles que vous avez ajoutées."))

                    if let url = store.exportFile {
                        ShareLink(item: url) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                    .foregroundStyle(.indigo)
                                Text("Partager le fichier JSON")
                                Spacer()
                            }
                        }
                        .accessibilityHint(Text("Ouvre la feuille de partage pour envoyer le fichier vers une autre application."))
                        .simultaneousGesture(TapGesture().onEnded {
                            // Clear the file slot after the user picks a target;
                            // they can regenerate by tapping Export again.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                store.send(.exportFileConsumed)
                            }
                        })
                    }
                } header: {
                    Text("Données")
                } footer: {
                    Text("L'export ne contient que les règles que vous avez ajoutées vous-même. Les packs Octiplex ne sont pas inclus : ils se réinstallent automatiquement à la synchronisation.")
                        .font(.caption)
                }

                AboutSection()
            }
            .navigationTitle("Réglages")
            .task { await store.send(.task).finish() }
            .sheet(item: $store.scope(state: \.urlImportPresentation, action: \.urlImportPresentation)) { urlStore in
                PackURLImportSheet(store: urlStore)
            }
        }
    }

    private var enabledPackNumbers: Int {
        store.packs.filter(\.enabled).reduce(0) { $0 + (store.numberCounts[$1.id] ?? 0) }
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
                Text("\(summary.failed.count) pack(s) en erreur, voir les logs.")
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
    let numberCount: Int?
    let isToggling: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(pack.displayTitle)
                    .font(.body.weight(.medium))
                Text("\(pack.id) · \(pack.country) · version \(pack.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let numberCount {
                    Text("\(FilterStatusFormatting.count(numberCount)) numéros")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isToggling {
                ProgressView()
                    .accessibilityLabel(Text("Application en cours"))
            } else {
                Toggle(packDescription, isOn: Binding(
                    get: { pack.enabled },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
                .accessibilityLabel(Text(packDescription))
                .accessibilityHint(Text("Activez ou désactivez la contribution de ce pack à votre liste de blocage."))
            }
        }
        .padding(.vertical, 2)
    }

    private var packDescription: String {
        let country = Locale.current.localizedString(forRegionCode: pack.country) ?? pack.country
        if let numberCount {
            return String(localized: "Pack \(pack.id), \(country), version \(pack.version), \(FilterStatusFormatting.count(numberCount)) numéros")
        }
        return String(localized: "Pack \(pack.id), \(country), version \(pack.version)")
    }
}
