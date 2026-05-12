import ComposableArchitecture
import SwiftUI
import WildCallCoreApp
import WildCallCoreShared

struct RulesListView: View {
    @Bindable var store: StoreOf<RulesFeature>

    var body: some View {
        Group {
            if store.rules.isEmpty && !store.isLoading {
                ContentUnavailableView(
                    "Aucune règle",
                    systemImage: "phone.down.circle",
                    description: Text("Ajoutez un numéro à bloquer ou identifier.")
                )
            } else {
                List {
                    ForEach(store.rules) { rule in
                        RuleRow(rule: rule)
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
}

private struct RuleRow: View {
    let rule: BlockRule

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: actionIcon)
                .foregroundStyle(actionTint)
                .font(.title3)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayNumber)
                    .font(.body.monospacedDigit())
                if let label = rule.label, !label.isEmpty {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(rule.countryCode)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: .capsule)
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
