import ComposableArchitecture
import SwiftUI
import WildCallCoreApp

struct PacksView: View {
    @Bindable var store: StoreOf<PacksFeature>
    let appStore: StoreOf<AppFeature>
    @Dependency(\.deviceRegion) private var deviceRegion

    var body: some View {
        NavigationStack {
            List {
                FilterStatusSection(store: appStore)

                if store.packs.isEmpty, store.isLoading {
                    HStack(spacing: 12) {
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
                    packSections
                }

                Section {
                    Button {
                        store.send(.syncButtonTapped)
                    } label: {
                        if store.isSyncing {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Synchronisation…")
                            }
                        } else {
                            Label("Synchroniser maintenant", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(store.isSyncing)
                    .accessibilityLabel(Text(store.isSyncing ? "Synchronisation en cours" : "Synchroniser maintenant"))
                    .accessibilityHint(Text("Récupère les nouveaux packs et les mises à jour depuis Octiplex."))

                    Button {
                        store.send(.addByURLTapped)
                    } label: {
                        Label("Ajouter un pack par URL…", systemImage: "link")
                    }
                    .accessibilityHint(Text("Ouvre un formulaire pour télécharger un pack signé depuis une URL externe."))

                    if let lastSync = store.lastSync {
                        LabeledContent("Dernière synchronisation") {
                            Text(lastSync, style: .relative)
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
                        if store.isExporting {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Préparation…")
                            }
                        } else {
                            Label("Exporter mes règles…", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(store.isExporting)
                    .accessibilityLabel(Text(store.isExporting ? "Préparation de l'export" : "Exporter mes règles"))
                    .accessibilityHint(Text("Prépare un fichier JSON contenant les règles que vous avez ajoutées."))

                    if let url = store.exportFile {
                        ShareLink(item: url) {
                            Label("Partager le fichier JSON", systemImage: "doc")
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

    /// Packs of the device's country first : they are the ones a fresh
    /// install enables. Everything else stays one toggle away.
    @ViewBuilder private var packSections: some View {
        let region = deviceRegion.code()
        let home = store.packs.filter { DefaultPackPolicy.isHomePack(country: $0.country, region: region) }
        let others = store.packs.filter { !DefaultPackPolicy.isHomePack(country: $0.country, region: region) }

        if !home.isEmpty {
            Section {
                ForEach(home) { pack in row(for: pack) }
            } header: {
                Text("Packs pour votre pays")
            }
        }

        if !others.isEmpty {
            Section {
                ForEach(others) { pack in row(for: pack) }
            } header: {
                home.isEmpty ? Text("Packs installés") : Text("Autres pays")
            }
        }

        Section {
            CapacityRow(used: enabledPackNumbers, capacity: WildcardQuotas.default.totalCapacity)
        } footer: {
            Text("iOS accepte un nombre limité de numéros par app. Seuls les packs de votre pays sont activés au départ ; chaque pack activé en plus réduit la place restante pour vos propres règles.")
        }
    }

    private func row(for pack: InstalledPack) -> some View {
        PackRow(
            pack: pack,
            numberCount: store.numberCounts[pack.id],
            isToggling: store.togglingId == pack.id,
            onToggle: { newValue in
                store.send(.toggle(id: pack.id, enabled: newValue))
            }
        )
    }

    private var enabledPackNumbers: Int {
        store.packs.filter(\.enabled).reduce(0) { $0 + (store.numberCounts[$1.id] ?? 0) }
    }

    @ViewBuilder private var syncFooterView: some View {
        if let error = store.lastSyncError {
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if let summary = store.lastSyncSummary {
            if summary.didChangeAnything {
                let parts = [
                    summary.added.isEmpty ? nil : String(localized: "\(summary.added.count) packs ajoutés"),
                    summary.upgraded.isEmpty ? nil : String(localized: "\(summary.upgraded.count) packs mis à jour")
                ].compactMap(\.self)
                Text(verbatim: parts.joined(separator: " · "))
            } else if !summary.failed.isEmpty {
                Text("\(summary.failed.count) packs en erreur, voir les logs")
                    .foregroundStyle(.orange)
            } else {
                Text("Tout est à jour")
            }
        } else {
            Text("La synchronisation récupère les nouveaux packs et les mises à jour depuis Octiplex.")
        }
    }
}

/// The one gauge of the app : how much of what iOS accepts the enabled
/// packs take.
private struct CapacityRow: View {
    let used: Int
    let capacity: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Packs activés")
                Spacer()
                Text(verbatim: "\(FilterStatusFormatting.count(used)) / \(FilterStatusFormatting.count(capacity))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(min(used, capacity)), total: Double(capacity))
                .tint(used > capacity ? Color.orange : Color.accentColor)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Packs activés"))
        .accessibilityValue(Text("\(FilterStatusFormatting.count(used)) numéros sur \(FilterStatusFormatting.count(capacity))"))
    }
}

private struct PackRow: View {
    let pack: InstalledPack
    let numberCount: Int?
    let isToggling: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: PackTitle.localized(pack.displayTitle))
                Text(verbatim: "\(CountryName.localized(pack.country)) · \(pack.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let numberCount {
                    Text("\(FilterStatusFormatting.count(numberCount)) numéros")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
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
        .padding(.vertical, 4)
    }

    private var packDescription: String {
        let country = CountryName.localized(pack.country)
        if let numberCount {
            return String(localized: "Pack \(PackTitle.localized(pack.displayTitle)), \(country), version \(pack.version), \(FilterStatusFormatting.count(numberCount)) numéros")
        }
        return String(localized: "Pack \(PackTitle.localized(pack.displayTitle)), \(country), version \(pack.version)")
    }
}
