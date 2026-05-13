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
                Section {
                    Picker("Pays", selection: $store.countryCode) {
                        ForEach(Self.countries, id: \.code) { country in
                            Text(country.label).tag(country.code)
                        }
                    }

                    TextField("06 12 34 56 78 ou +33162999*", text: $store.rawNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($numberFieldFocused)

                    validationFooter
                } header: {
                    Text("Numéro ou motif")
                } footer: {
                    Text("Terminez par `*` pour bloquer une famille de numéros (ex. `+33162999*`).")
                        .font(.caption)
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

        case .exactInvalid:
            Label("Numéro invalide pour ce pays.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)

        case .exactValid(let e164):
            Label("+\(e164.value)", systemImage: "checkmark.seal.fill")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.green)

        case .wildcardInvalid(let error):
            Label(Self.message(for: error), systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)

        case .wildcardValid(let prefix, let count):
            VStack(alignment: .leading, spacing: 2) {
                Label("Couvre \(Self.formatted(count)) numéros", systemImage: "scope")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.indigo)
                Text("+\(prefix.fixedDigits) suivi de \(prefix.wildcardLength) chiffre\(prefix.wildcardLength > 1 ? "s" : "")")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func message(for error: ParseError) -> String {
        switch error {
        case .empty:
            return "Saisissez un motif."
        case .missingWildcard:
            return "Ajoutez `*` à la fin pour un motif."
        case .wildcardNotTrailing:
            return "Le `*` doit être en dernière position, et un seul."
        case .unparseable:
            return "Motif illisible."
        case .unknownNationalLength(let country):
            return "Longueur nationale inconnue pour \(country)."
        case .fixedTooShort(let minimum):
            return "Au moins \(minimum) chiffres fixes après l'indicatif pays."
        case .fixedTooLong(let maximum):
            return "Trop de chiffres : maximum \(maximum) pour ce pays."
        case .exceedsPerPatternQuota(let expanded, let limit):
            return "Ce motif couvrirait \(formatted(expanded)) numéros (max \(formatted(limit)))."
        }
    }

    private static func formatted(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{202F}"  // narrow no-break space, French convention
        return formatter.string(from: NSNumber(value: count)) ?? String(count)
    }
}
