import ComposableArchitecture
import SwiftUI
import WildCallCoreApp

struct PackURLImportSheet: View {
    @Bindable var store: StoreOf<PackURLImportFeature>

    var body: some View {
        NavigationStack {
            Group {
                switch store.phase {
                case .idle:
                    inputView

                case .downloading:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Téléchargement…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .combine)

                case .awaitingTrust(let manifest, let fingerprint, _):
                    trustView(manifest: manifest, fingerprint: fingerprint)

                case .installing:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Installation…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .navigationTitle("Ajouter un pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { store.send(.cancelTapped) }
                        .disabled(store.isBusy)
                }
            }
        }
    }

    @ViewBuilder private var inputView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("URL du pack")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            TextField("https://example.com/pack.wildcallpack", text: $store.urlInput)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(Text("URL du pack à télécharger"))

            Text("Le pack doit être signé. Vous verrez l'empreinte du publisher avant d'accepter.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                store.send(.submitTapped)
            } label: {
                Text("Vérifier le pack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .controlSize(.large)
            .disabled(store.urlInput.isEmpty)
            .accessibilityHint(Text("Télécharge le pack et affiche son empreinte de signature avant installation."))
        }
    }

    @ViewBuilder private func trustView(manifest: PackManifest, fingerprint: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(manifest.title ?? manifest.id)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(manifest.id).font(.caption.monospaced()).foregroundStyle(.secondary)

            Divider()

            row("Pays", manifest.country)
            row("Version", manifest.version)
            row("Règles déclarées", "\(manifest.prefixes.count)")
            if let license = manifest.license { row("Licence", license) }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label("Publisher non reconnu", systemImage: "questionmark.shield")
                    .foregroundStyle(.orange)
                    .font(.subheadline.weight(.medium))
                    .accessibilityElement(children: .combine)
                Text("Ce pack n'est pas signé par Octiplex. Avant d'installer, vérifiez que cette empreinte correspond bien à celle publiée hors-bande par l'éditeur :")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(fingerprint)
                    .font(.body.monospaced())
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel(Text("Empreinte du pack : \(AccessibilityFormatting.readableFingerprint(fingerprint))"))
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    store.send(.trustAcceptTapped)
                } label: {
                    Text("Faire confiance et installer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.large)
                .accessibilityHint(Text("Épingle cette empreinte pour ce pack et installe les règles."))

                Button("Refuser") {
                    store.send(.trustRejectTapped)
                }
                .foregroundStyle(.red)
                .accessibilityHint(Text("Annule l'installation sans épingler la clé."))
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.monospaced())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label) : \(value)"))
    }

    @ViewBuilder private func failureView(error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Échec de l'import").font(.headline).accessibilityAddTraits(.isHeader)
            Text(error).font(.caption.monospaced()).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button("Fermer") { store.send(.cancelTapped) }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }
}
