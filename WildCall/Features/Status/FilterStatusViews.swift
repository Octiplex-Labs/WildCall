import ComposableArchitecture
import SwiftUI
import WildCallCoreApp
import WildCallCoreShared

/// Shown in the Filtres tab while a cycle is running or after a failure.
/// When the store is ready the banner disappears : the details live in
/// Réglages (`FilterStatusSection`).
struct FilterStatusBanner: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        switch store.storeStatus {
        case .building:
            card(tint: .indigo) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Préparation du filtre…")
                        .font(.subheadline)
                }
            }
        case .reloading(let numbers):
            card(tint: .indigo) {
                HStack(alignment: .top, spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iOS charge \(FilterStatusFormatting.count(numbers)) numéros")
                            .font(.subheadline.weight(.medium))
                        Text("Cela peut prendre plusieurs minutes. Vous pouvez continuer à utiliser l'app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .failed(let failure, _, _):
            card(tint: .orange) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(FilterStatusFormatting.title(for: failure), systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(FilterStatusFormatting.detail(for: failure))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        store.send(.rebuildButtonTapped)
                    } label: {
                        Label("Réessayer", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(Text("Reconstruit le filtre et le renvoie à iOS."))
                }
            }
        case .unknown, .ready:
            EmptyView()
        }
    }

    private func card<Content: View>(tint: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(tint.opacity(0.08), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            }
            .padding(.horizontal)
    }
}

/// Réglages section : what iOS currently holds, when it was loaded, and a
/// manual rebuild button. This is also the on-device instrument for
/// measuring how long the extension takes to ingest a given volume.
struct FilterStatusSection: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        Section {
            statusRow

            if let run = store.lastExtensionRun {
                row("Dernier chargement iOS", FilterStatusFormatting.summary(of: run))
                if let duration = run.duration {
                    row("Durée", FilterStatusFormatting.duration(duration))
                }
                if run.outcome == .failed, let error = run.errorDescription {
                    Text(error)
                        .font(.caption.monospaced())
                        .foregroundStyle(.orange)
                }
            }

            Button {
                store.send(.rebuildButtonTapped)
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Reconstruire le filtre")
                    Spacer()
                }
            }
            .disabled(store.storeStatus.isBusy)
            .accessibilityHint(Text("Régénère la liste et demande à iOS de la recharger."))
        } header: {
            Text("État du filtre")
        } footer: {
            Text("iOS ne journalise pas les appels bloqués : ils n'apparaissent ni dans Récents ni en notification. Pour vérifier qu'une règle est active, préférez l'action Identifier : l'étiquette s'affiche sur l'appel entrant et dans Récents. Les numéros présents dans vos contacts ne sont jamais filtrés.")
                .font(.caption)
        }
    }

    @ViewBuilder private var statusRow: some View {
        switch store.storeStatus {
        case .unknown:
            row("Filtre", String(localized: "Non construit"))
        case .building:
            HStack {
                ProgressView()
                Text("Préparation du filtre…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .reloading(let numbers):
            HStack {
                ProgressView()
                Text("iOS charge \(FilterStatusFormatting.count(numbers)) numéros…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .ready(let numbers, let date):
            VStack(alignment: .leading, spacing: 2) {
                Label("\(FilterStatusFormatting.count(numbers)) numéros actifs", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Chargé \(date, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .failed(let failure, let numbers, let date):
            VStack(alignment: .leading, spacing: 2) {
                Label(FilterStatusFormatting.title(for: failure), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(FilterStatusFormatting.detail(for: failure))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(FilterStatusFormatting.count(numbers)) numéros · échec \(date, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

enum FilterStatusFormatting {
    static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{202F}"
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func count(_ value: Int64) -> String {
        count(Int(value))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return String(localized: "moins d'une seconde") }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 60 ? [.minute, .second] : [.second]
        formatter.unitsStyle = .short
        return formatter.string(from: seconds) ?? "\(Int(seconds)) s"
    }

    static func summary(of run: ExtensionRunReport) -> String {
        switch run.outcome {
        case .running:
            return String(localized: "En cours…")
        case .completed:
            return String(localized: "\(count(run.blockNumbers)) bloqués, \(count(run.identNumbers)) identifiés")
        case .failed:
            return String(localized: "Échec")
        }
    }

    static func title(for failure: ReloadFailure) -> String {
        switch failure {
        case .extensionDisabled:
            String(localized: "WildCall n'est pas activé dans Réglages")
        case .noExtensionFound:
            String(localized: "Extension introuvable")
        case .currentlyLoading:
            String(localized: "iOS charge déjà une liste")
        case .loadingInterrupted:
            String(localized: "Chargement interrompu par iOS")
        case .entriesOutOfOrder, .duplicateEntries, .unexpectedIncrementalRemoval:
            String(localized: "Liste rejetée par iOS")
        case .maximumEntriesExceeded:
            String(localized: "Trop de numéros pour iOS")
        case .unknown:
            String(localized: "Le chargement a échoué")
        }
    }

    static func detail(for failure: ReloadFailure) -> String {
        switch failure {
        case .extensionDisabled:
            String(localized: "Réglages → Apps → Téléphone → Blocage et identification d'appel → activez WildCall, puis réessayez.")
        case .noExtensionFound:
            String(localized: "L'extension de blocage n'est pas installée avec l'app. Réinstallez WildCall.")
        case .currentlyLoading:
            String(localized: "Attendez la fin du chargement en cours puis réessayez.")
        case .loadingInterrupted:
            String(localized: "L'app a été suspendue pendant le chargement. Relancez-le en gardant WildCall au premier plan.")
        case .entriesOutOfOrder, .duplicateEntries, .unexpectedIncrementalRemoval:
            String(localized: "Le fichier partagé est incohérent. Reconstruisez le filtre ; si le problème persiste, signalez-le.")
        case .maximumEntriesExceeded:
            String(localized: "Désactivez un pack ou réduisez vos motifs, puis reconstruisez le filtre.")
        case .unknown(let description):
            description
        }
    }
}
