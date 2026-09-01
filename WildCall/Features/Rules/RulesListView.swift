import ComposableArchitecture
import SwiftUI
import WildCallCoreApp
import WildCallCoreShared

struct RulesListView: View {
    @Bindable var store: StoreOf<RulesFeature>
    @Dependency(\.wildcardExpander) private var expander

    var body: some View {
        Group {
            if store.isEmpty && !store.isLoading {
                emptyState
            } else {
                List {
                    let grouped = RuleGrouping.group(rules: Array(store.rules), packs: store.packs, count: expander.count)

                    if !grouped.packs.isEmpty {
                        Section {
                            ForEach(grouped.packs) { group in
                                NavigationLink {
                                    PackDetailView(group: group)
                                } label: {
                                    PackGroupRow(group: group)
                                }
                                .accessibilityLabel(Self.accessibilityLabel(for: group))
                                .accessibilityHint(Text("Affiche les plages de numéros de ce pack."))
                            }
                        } header: {
                            Text("Packs")
                        } footer: {
                            Text("Activez ou désactivez un pack dans Réglages. Touchez un pack pour voir ses plages.")
                        }
                    }

                    Section {
                        if grouped.user.isEmpty {
                            Text("Aucune règle personnelle. Touchez + pour en ajouter une.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(grouped.user) { rule in
                            RuleRow(rule: rule)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(Self.accessibilityLabel(for: rule))
                                .accessibilityHint(Text("Balayez vers la gauche pour supprimer ou vers la droite pour changer l'action."))
                                .swipeActions(edge: .leading) {
                                    Button {
                                        store.send(.toggleActionRequested(id: rule.id))
                                    } label: {
                                        switch rule.action {
                                        case .block:
                                            Label("Identifier", systemImage: "tag")
                                        case .identify:
                                            Label("Bloquer", systemImage: "phone.down")
                                        }
                                    }
                                    .tint(.indigo)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        store.send(.deleteRequested(id: rule.id))
                                    } label: {
                                        Label("Supprimer", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text("Mes règles")
                    }
                }
            }
        }
        .navigationTitle("Filtres")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.send(.addButtonTapped)
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
            }
        }
        .task { await store.send(.task).finish() }
        .sheet(item: $store.scope(state: \.addRule, action: \.addRule)) { addRuleStore in
            AddRuleSheet(store: addRuleStore)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Aucune règle", systemImage: "shield.lefthalf.filled")
                .foregroundStyle(.indigo)
        } description: {
            Text("Ajoutez un motif avec des jokers pour bloquer toute une famille de numéros indésirables en une fois.")
        } actions: {
            VStack(spacing: 14) {
                Button {
                    store.send(.addButtonTapped)
                } label: {
                    Label("Nouvelle règle", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.large)
                .accessibilityHint(Text("Ouvre le formulaire pour saisir un numéro ou un motif."))

                Button {
                    store.send(.syncFromEmptyStateTapped)
                } label: {
                    VStack(spacing: 2) {
                        Text("Synchroniser les packs")
                            .font(.subheadline.weight(.medium))
                        Text("Récupère les listes Octiplex de numéros connus.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.indigo)
                .accessibilityElement(children: .combine)
                .accessibilityHint(Text("Télécharge les derniers packs publiés par Octiplex."))
            }
            .padding(.horizontal, 24)
        }
    }

    private static func accessibilityLabel(for group: PackGroup) -> Text {
        let state = group.pack.enabled ? String(localized: "activé") : String(localized: "désactivé")
        return Text("Pack \(group.pack.displayTitle), \(state), \(FilterStatusFormatting.count(group.numberCount)) numéros, \(group.roots.count) racines")
    }

    private static func accessibilityLabel(for rule: BlockRule) -> Text {
        let actionLabel: String = switch rule.action {
        case .block: String(localized: "Bloquer")
        case .identify: String(localized: "Identifier")
        }
        let countryLabel = Locale.current.localizedString(forRegionCode: rule.countryCode) ?? rule.countryCode

        let numberLabel: String = switch rule.kind {
        case .exact(let e164):
            String(localized: "numéro + \(AccessibilityFormatting.spelledOut(String(e164.value)))")
        case .prefix(let prefix):
            String(
                localized: "préfixe + \(AccessibilityFormatting.spelledOut(prefix.fixedDigits)) suivi de \(prefix.wildcardLength) chiffre\(prefix.wildcardLength > 1 ? "s" : "") variable\(prefix.wildcardLength > 1 ? "s" : "")"
            )
        }

        if let label = rule.label, !label.isEmpty {
            return Text("\(actionLabel), \(numberLabel), libellé \(label), pays \(countryLabel)")
        } else {
            return Text("\(actionLabel), \(numberLabel), pays \(countryLabel)")
        }
    }
}

private struct PackGroupRow: View {
    let group: PackGroup

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(group.pack.enabled ? Color.indigo : Color.secondary)
                .font(.title3)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.pack.displayTitle)
                    .font(.body.weight(.medium))
                Text("\(FilterStatusFormatting.count(group.numberCount)) numéros · \(group.roots.count) racines")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !group.pack.enabled {
                Text("Désactivé")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One row per number root ("01 62"), expandable to its blocks when the
/// pack lists more than one pattern under that root.
struct PackDetailView: View {
    let group: PackGroup

    var body: some View {
        List {
            Section {
                ForEach(group.roots) { root in
                    if root.isSinglePattern, let rule = root.rules.first {
                        RuleRow(rule: rule)
                    } else {
                        DisclosureGroup {
                            ForEach(root.rules) { rule in
                                RuleRow(rule: rule)
                            }
                        } label: {
                            RootRow(root: root)
                        }
                    }
                }
            } header: {
                Text("\(FilterStatusFormatting.count(group.numberCount)) numéros dans \(group.roots.count) racines")
            } footer: {
                Text("\(group.pack.id) · version \(group.pack.version) · \(group.ruleCount) motifs")
            }
        }
        .navigationTitle(group.pack.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RootRow: View {
    let root: RootGroup

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(RuleDisplay.rootLabel(root))
                    .font(.body.monospaced())
                Text("\(FilterStatusFormatting.count(root.numberCount)) numéros · \(root.rules.count) blocs")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

enum RuleDisplay {
    /// "33162" → "+33 162 …" so the root reads like a dialling prefix.
    static func rootLabel(_ root: RootGroup) -> String {
        let callingCodeLength = root.root.count - RuleGrouping.rootNationalDigits
        let code = root.root.prefix(max(0, callingCodeLength))
        let national = root.root.dropFirst(max(0, callingCodeLength))
        return "+\(code) \(national)…"
    }
}

private struct RuleRow: View {
    let rule: BlockRule
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: actionIcon)
                .foregroundStyle(actionTint)
                .font(.title3)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayNumber)
                    .font(.body.monospaced())
                if let label = rule.label, !label.isEmpty {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    Text(rule.countryCode)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if !dynamicTypeSize.isAccessibilitySize {
                Text(rule.countryCode)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
    }

    private var displayNumber: String {
        switch rule.kind {
        case .exact(let e164):
            return "+\(e164.value)"
        case .prefix(let prefix):
            return "+\(prefix.fixedDigits)\(String(repeating: "*", count: prefix.wildcardLength))"
        }
    }

    private var actionIcon: String {
        switch rule.action {
        case .block: "phone.down.fill"
        case .identify: "tag.fill"
        }
    }

    private var actionTint: Color {
        switch rule.action {
        case .block: .red
        case .identify: .indigo
        }
    }
}
