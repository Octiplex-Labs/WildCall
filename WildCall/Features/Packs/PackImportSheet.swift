import ComposableArchitecture
import SwiftUI
import WildCallCoreApp

struct PackImportSheet: View {
    @Bindable var store: StoreOf<PackImportFeature>

    var body: some View {
        NavigationStack {
            Group {
                switch store.phase {
                case .reading:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Lecture du pack…")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                case .awaitingConfirmation(let loaded):
                    confirmationView(loaded)

                case .installing:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Installation…")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

                case .failed(let error):
                    failureView(error: error.message)

                case .finished:
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text("Pack installé.")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Importer un pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { store.send(.cancelTapped) }
                }
            }
            .task { await store.send(.task).finish() }
        }
    }

    @ViewBuilder
    private func confirmationView(_ loaded: LoadedPack) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(loaded.manifest.title ?? loaded.manifest.id)
                    .font(.title3.weight(.semibold))
                Text(loaded.manifest.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Divider()

            row(label: String(localized: "Pays"), value: loaded.manifest.country)
            row(label: String(localized: "Version"), value: loaded.manifest.version)
            row(
                label: String(localized: "Type"),
                value: loaded.manifest.kind == .prefixes
                    ? String(localized: "Préfixes")
                    : String(localized: "Liste pré-expansée")
            )
            row(label: String(localized: "Règles"), value: "\(loaded.rules.count)")

            if let license = loaded.manifest.license {
                row(label: String(localized: "Licence"), value: license)
            }

            Divider()

            Label(
                String(localized: "Signé par Octiplex (fingerprint \(OctiplexTrust.fingerprint(of: OctiplexTrust.publicKey)))"),
                systemImage: "checkmark.seal.fill"
            )
                .font(.caption)
                .foregroundStyle(.indigo)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    Text("Signé par Octiplex. Empreinte \(AccessibilityFormatting.readableFingerprint(OctiplexTrust.fingerprint(of: OctiplexTrust.publicKey))).")
                )

            Spacer()

            Button {
                store.send(.confirmTapped)
            } label: {
                Text("Installer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .controlSize(.large)
            .accessibilityHint(Text("Installe le pack et reconstruit votre liste de blocage."))
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value).font(.callout.monospaced())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label) : \(value)"))
    }

    @ViewBuilder
    private func failureView(error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Impossible d'importer ce pack.")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(error)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Fermer") { store.send(.cancelTapped) }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }
}
