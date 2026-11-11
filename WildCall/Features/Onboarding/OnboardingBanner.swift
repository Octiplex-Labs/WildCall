import ComposableArchitecture
import SwiftUI
import WildCallCoreApp
import WildCallCoreShared

/// Guides the user through enabling every WildCall extension. iOS lists
/// one toggle per extension ("WildCall 1" to "WildCall 4"): the filter is
/// complete only when all of them are on.
struct OnboardingBanner: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        if store.extensionStatus != .enabled {
            StatusCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text(title).font(.headline)
                    } icon: {
                        Image(systemName: icon)
                            .foregroundStyle(tint)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    slotIndicators
                    HStack(spacing: 12) {
                        Button {
                            CallBlockingSettings.open()
                        } label: {
                            Text("Ouvrir Réglages")
                                .foregroundStyle(Color.onAccent)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint(Text("Ouvre l'app Réglages pour activer WildCall."))

                        Button {
                            store.send(.refreshStatusButtonTapped)
                        } label: {
                            if store.isCheckingStatus {
                                ProgressView()
                            } else {
                                Text("Vérifier")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isCheckingStatus)
                        .accessibilityLabel(Text(store.isCheckingStatus ? "Vérification en cours" : "Vérifier le statut"))
                        .accessibilityHint(Text("Demande à iOS si les extensions sont activées."))
                    }
                }
            }
        }
    }

    private var slotIndicators: some View {
        HStack(spacing: 12) {
            ForEach(ExtensionSlot.all) { slot in
                let status = store.extensionStatuses[slot.index] ?? .unknown
                Label {
                    Text(verbatim: "\(slot.index)")
                } icon: {
                    Image(systemName: status == .enabled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(status == .enabled ? Color.green : Color.secondary)
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(slot.displayName), \(status == .enabled ? String(localized: "activée") : String(localized: "à activer"))"))
            }
        }
    }

    private var title: String {
        switch store.extensionStatus {
        case .enabled:
            return String(localized: "Extensions activées")
        case .disabled:
            let missing = store.disabledSlots.count
            return missing == ExtensionSlot.count
                ? String(localized: "Activez WildCall dans Réglages")
                : String(localized: "\(missing) extensions WildCall à activer")
        case .unknown:
            return String(localized: "Statut des extensions inconnu")
        }
    }

    private var detail: String {
        switch store.extensionStatus {
        case .enabled:
            String(localized: "WildCall filtre les appels.")
        case .disabled:
            String(localized: "Réglages → Apps → Téléphone → Blocage et identification d'appel → cochez chaque ligne WildCall. iOS limite chaque extension à 2 millions de numéros, WildCall en embarque donc \(ExtensionSlot.count).")
        case .unknown:
            String(localized: "Lancez la vérification pour interroger le système.")
        }
    }

    private var icon: String {
        switch store.extensionStatus {
        case .enabled: "checkmark.circle.fill"
        case .disabled: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    private var tint: Color {
        switch store.extensionStatus {
        case .enabled: .green
        case .disabled: .orange
        case .unknown: .secondary
        }
    }
}
