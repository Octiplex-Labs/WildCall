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

                case .awaitingConfirmation(let loaded):
                    confirmationView(loaded)

                case .installing:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Installation…")
                            .foregroundStyle(.secondary)
                    }

                case .failed(let error):
                    failureView(error: error.message)

                case .finished:
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        Text("Pack installé.")
                    }
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

            row(label: "Pays", value: loaded.manifest.country)
            row(label: "Version", value: loaded.manifest.version)
            row(label: "Type", value: loaded.manifest.kind == .prefixes ? "Préfixes" : "Liste pré-expansée")
            row(label: "Règles", value: "\(loaded.rules.count)")

            if let license = loaded.manifest.license {
                row(label: "Licence", value: license)
            }

            Divider()

            Label("Signé par Octiplex (fingerprint \(OctiplexTrust.fingerprint(of: OctiplexTrust.publicKey)))",
                  systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.indigo)

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
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.monospaced())
        }
    }

    @ViewBuilder
    private func failureView(error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Impossible d'importer ce pack.")
                .font(.headline)
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
