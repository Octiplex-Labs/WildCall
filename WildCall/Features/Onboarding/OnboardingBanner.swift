import ComposableArchitecture
import SwiftUI
import UIKit
import WildCallCoreApp

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
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        openCallBlockingSettings()
                    } label: {
                        Label("Ouvrir Réglages", systemImage: "gear")
                    }
                    .buttonStyle(.borderedProminent)

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

    private var title: String {
        switch store.extensionStatus {
        case .enabled: String(localized: "Extension activée")
        case .disabled: String(localized: "Activez WildCall dans Réglages")
        case .unknown: String(localized: "Statut de l'extension inconnu")
        }
    }

    private var detail: String {
        switch store.extensionStatus {
        case .enabled:
            String(localized: "WildCall filtre les appels.")
        case .disabled:
            String(localized: "Réglages → Apps → Téléphone → Blocage et identification d'appel → cocher WildCall.")
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
