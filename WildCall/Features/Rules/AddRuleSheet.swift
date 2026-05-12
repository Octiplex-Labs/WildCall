import ComposableArchitecture
import SwiftUI
import WildCallCoreApp
import WildCallCoreShared

struct AddRuleSheet: View {
    @Bindable var store: StoreOf<AddRuleFeature>
    @FocusState private var numberFieldFocused: Bool

    private static let countries: [(code: String, label: String)] = [
        ("FR", "🇫🇷 France"),
        ("BE", "🇧🇪 Belgique"),
        ("CH", "🇨🇭 Suisse"),
        ("CA", "🇨🇦 Canada"),
        ("US", "🇺🇸 États-Unis"),
        ("GB", "🇬🇧 Royaume-Uni"),
        ("DE", "🇩🇪 Allemagne"),
        ("ES", "🇪🇸 Espagne"),
        ("IT", "🇮🇹 Italie"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Numéro") {
                    Picker("Pays", selection: $store.countryCode) {
                        ForEach(Self.countries, id: \.code) { country in
                            Text(country.label).tag(country.code)
                        }
                    }

                    TextField("06 12 34 56 78", text: $store.rawNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($numberFieldFocused)

                    validationFooter
                }

                Section("Action") {
                    Picker("Action", selection: $store.action) {
                        Text("Bloquer").tag(RuleAction.block)
                        Text("Identifier").tag(RuleAction.identify)
                    }
                    .pickerStyle(.segmented)

                    if store.action == .identify {
                        TextField("Étiquette affichée à l'appel", text: $store.label)
                    }
                }
            }
            .navigationTitle("Nouvelle règle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        store.send(.delegate(.cancelled))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.validation.isValid || store.isSaving)
                }
            }
            .onAppear { numberFieldFocused = true }
            .interactiveDismissDisabled(store.isSaving)
        }
    }

    @ViewBuilder private var validationFooter: some View {
        switch store.validation {
        case .empty:
            EmptyView()
        case .invalid:
            Label("Numéro invalide pour ce pays.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .valid(let e164):
            Label("+\(e164.value)", systemImage: "checkmark.seal.fill")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.green)
        }
    }
}
