import ComposableArchitecture
import SwiftUI
import UIKit
import WildCallCoreApp
import WildCallCoreShared

/// Guides the user through enabling every WildCall extension. iOS lists
/// one toggle per extension ("WildCall 1" to "WildCall 4"): the filter is
/// complete only when all of them are on.
struct OnboardingBanner: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        if store.extensionStatus != .enabled {
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
                HStack {
                    Button {
                        openCallBlockingSettings()
                    } label: {
                        Label("Ouvrir Réglages", systemImage: "gear")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint(Text("Ouvre l'app Réglages pour activer WildCall."))

                    Button {
                        store.send(.refreshStatusButtonTapped)
                    } label: {
                        if store.isCheckingStatus {
                            ProgressView()
                        } else {
                            Label("Vérifier", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isCheckingStatus)
                    .accessibilityLabel(Text(store.isCheckingStatus ? "Vérification en cours" : "Vérifier le statut"))
                    .accessibilityHint(Text("Demande à iOS si les extensions sont activées."))
                }
            }
            .padding()
            .background(tint.opacity(0.08), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            }
            .padding(.horizontal)
        }
    }

    private var slotIndicators: some View {
        HStack(spacing: 8) {
            ForEach(ExtensionSlot.all) { slot in
                let status = store.extensionStatuses[slot.index] ?? .unknown
                Label {
                    Text(slot.displayName)
                } icon: {
                    Image(systemName: status == .enabled ? "checkmark.circle.fill" : "circle")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(status == .enabled ? Color.green : Color.secondary)
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
                : String(localized: "\(missing) extension(s) WildCall à activer")
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
        case .unknown: .gray
        }
    }

    private func openCallBlockingSettings() {
        // The dedicated path is undocumented and may break. We try it first,
        // then fall back to the generic app-settings URL.
        let preferredURL = URL(string: "App-prefs:Phone&path=CALL_BLOCKING")
        let fallbackURL = URL(string: UIApplication.openSettingsURLString)

        if let url = preferredURL, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = fallbackURL {
            UIApplication.shared.open(url)
        }
    }
}
