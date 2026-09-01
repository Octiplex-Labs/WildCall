import SwiftUI
import WildCallCoreApp

struct AboutSection: View {
    @AppStorage("wildcall.has_seen_onboarding") private var hasSeenOnboarding: Bool = false

    var body: some View {
        Section {
            NavigationLink {
                TipJarView()
            } label: {
                Label("Soutenir WildCall", systemImage: "heart.fill")
                    .foregroundStyle(.indigo)
            }
            .accessibilityHint(Text("Ouvre la page des pourboires optionnels."))

            Button {
                hasSeenOnboarding = false
            } label: {
                Label("Revoir l'introduction", systemImage: "play.rectangle.fill")
            }
            .accessibilityHint(Text("Affiche à nouveau l'introduction au prochain retour à l'écran principal."))

            NavigationLink {
                AboutView()
            } label: {
                Label("À propos", systemImage: "info.circle")
            }
            .accessibilityHint(Text("Affiche la version, la clé publisher et les composants tiers."))
        }
    }
}

struct AboutView: View {
    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    private var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
    }

    private var octiplexFingerprint: String {
        OctiplexTrust.fingerprint(of: OctiplexTrust.publicKey)
    }

    var body: some View {
        List {
            Section {
                row("Version", "\(appVersion) (\(buildNumber))")
                fingerprintRow
                    .listRowSeparator(.hidden)
                Text("Cette empreinte doit correspondre à celle publiée sur la page du projet. Si elle ne correspond pas, votre build a été modifié.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Identité")
            }

            Section {
                Link(destination: URL(string: "https://github.com/Octiplex-Labs/WildCall")!) {
                    HStack {
                        Label("Code source", systemImage: "chevron.left.forwardslash.chevron.right")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityHint(Text("Ouvre le dépôt GitHub dans Safari."))

                Link(destination: URL(string: "https://github.com/Octiplex-Labs/WildCall/tree/main/dist/packs")!) {
                    HStack {
                        Label("Catalogue de packs", systemImage: "shippingbox")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityHint(Text("Ouvre le dossier des packs publiés dans Safari."))
            } header: {
                Text("Liens")
            }

            Section {
                acknowledgement("PhoneNumberKit", url: "https://github.com/marmelroy/PhoneNumberKit", license: "MIT")
                acknowledgement("SWCompression", url: "https://github.com/tsolomko/SWCompression", license: "MIT")
                acknowledgement("PointFree swift-composable-architecture", url: "https://github.com/pointfreeco/swift-composable-architecture", license: "MIT")
                acknowledgement("PointFree swift-dependencies", url: "https://github.com/pointfreeco/swift-dependencies", license: "MIT")
                acknowledgement("PointFree swift-snapshot-testing", url: "https://github.com/pointfreeco/swift-snapshot-testing", license: "MIT")
            } header: {
                Text("Composants tiers")
            } footer: {
                Text("WildCall ne collecte aucune donnée d'usage. Toutes les règles, packs et signatures sont traités localement sur votre appareil ; le seul appel réseau est la synchronisation des packs depuis le catalogue Octiplex.")
                    .font(.caption)
            }
        }
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label) : \(value)"))
    }

    private var fingerprintRow: some View {
        HStack {
            Text("Clé publisher Octiplex")
            Spacer()
            Text(octiplexFingerprint)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("Clé publisher Octiplex, empreinte \(AccessibilityFormatting.readableFingerprint(octiplexFingerprint))")
        )
    }

    private func acknowledgement(_ name: String, url: String, license: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name).foregroundStyle(.primary)
                    Spacer()
                    Text(license).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "arrow.up.right.square").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(name), licence \(license)"))
        .accessibilityHint(Text("Ouvre la page du projet dans Safari."))
    }
}
