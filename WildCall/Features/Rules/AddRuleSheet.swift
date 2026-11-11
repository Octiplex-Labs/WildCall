import ComposableArchitecture
import SwiftUI
import WildCallCoreApp
import WildCallCoreShared

struct AddRuleSheet: View {
    @Bindable var store: StoreOf<AddRuleFeature>
    @FocusState private var numberFieldFocused: Bool

    /// Country names come from the system, in the user's language.
    private static let countryCodes = ["FR", "BE", "CH", "CA", "US", "GB", "DE", "ES", "IT"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Pays", selection: $store.countryCode) {
                        ForEach(Self.countryCodes, id: \.self) { code in
                            Text(verbatim: CountryName.localized(code)).tag(code)
                        }
                    }

                    TextField("06 12 34 56 78 ou 0162*", text: $store.rawNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($numberFieldFocused)
                        .accessibilityLabel(Text("Numéro ou motif"))
                        .accessibilityIdentifier("addRule.number")
                        .accessibilityHint(Text("Terminez par une étoile pour bloquer une famille de numéros."))

                    validationFooter
                } header: {
                    Text("Numéro ou motif")
                } footer: {
                    Text("Terminez par `*` pour bloquer une famille de numéros : `0162*` couvre tous les numéros commençant par 01 62 (jusqu'à 1 000 000 de numéros par motif).")
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
                    .accessibilityIdentifier("addRule.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.validation.isValid || store.isSaving)
                    .accessibilityHint(
                        Text(store.validation.isValid
                            ? "Enregistre la règle dans votre liste."
                            : "Saisissez un numéro ou un motif valide pour activer ce bouton.")
                    )
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
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)

        case .exactValid(let e164):
            Label {
                PatternText(fixedDigits: String(e164.value), font: .footnote.monospaced())
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Numéro valide + \(AccessibilityFormatting.spelledOut(String(e164.value)))"))

        case .wildcardInvalid(let error):
            Label(Self.message(for: error), systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)

        case .wildcardValid(let prefix, let count):
            VStack(alignment: .leading, spacing: 4) {
                PatternText(
                    fixedDigits: prefix.fixedDigits,
                    wildcardLength: prefix.wildcardLength,
                    font: .footnote.monospaced()
                )
                Text("Couvre \(Self.formatted(count)) numéros")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text("Motif valide, préfixe + \(AccessibilityFormatting.spelledOut(prefix.fixedDigits)) suivi de \(prefix.wildcardLength) chiffre\(prefix.wildcardLength > 1 ? "s" : "") variable\(prefix.wildcardLength > 1 ? "s" : ""), couvre \(Self.formatted(count)) numéros.")
            )
        }
    }

    private static func message(for error: ParseError) -> String {
        switch error {
        case .empty:
            return String(localized: "Saisissez un motif.")
        case .missingWildcard:
            return String(localized: "Ajoutez `*` à la fin pour un motif.")
        case .wildcardNotTrailing:
            return String(localized: "Le `*` doit être en dernière position, et un seul.")
        case .unparseable:
            return String(localized: "Motif illisible.")
        case .unknownNationalLength(let country):
            return String(localized: "Longueur nationale inconnue pour \(country).")
        case .fixedTooShort(let minimum):
            return String(localized: "Au moins \(minimum) chiffres avant le `*` (sans compter le 0 initial).")
        case .fixedTooLong(let maximum):
            return String(localized: "Trop de chiffres : maximum \(maximum) pour ce pays.")
        case .exceedsPerPatternQuota(let expanded, let limit):
            return String(localized: "Ce motif couvrirait \(formatted(expanded)) numéros (max \(formatted(limit))).")
        }
    }

    private static func formatted(_ count: Int) -> String {
        FilterStatusFormatting.count(count)
    }
}
