import ComposableArchitecture
import SwiftUI
import WildCallCoreApp
import WildCallCoreShared

struct RulesListView: View {
    @Bindable var store: StoreOf<RulesFeature>

    var body: some View {
        Group {
            if store.rules.isEmpty && !store.isLoading {
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
            } else {
                List {
                    ForEach(store.rules) { rule in
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
                }
            }
        }
        .navigationTitle("Règles")
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
                    .font(.body.monospacedDigit())
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
