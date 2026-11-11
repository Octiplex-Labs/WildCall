import SwiftUI
import WildCallCoreApp
import WildCallCoreShared

struct OnboardingFlowView: View {
    @Binding var isPresented: Bool
    @State private var index: Int = 0

    private let totalPanels = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if index < totalPanels - 1 {
                    Button("Passer") { dismiss() }
                        .foregroundStyle(.secondary)
                        .accessibilityHint(Text("Ferme l'introduction et passe directement à l'app."))
                }
            }
            .padding(.horizontal, Metrics.pageMargin)
            .frame(height: 44)

            TabView(selection: $index) {
                WelcomePanel().tag(0)
                WildcardsPanel().tag(1)
                PacksPanel().tag(2)
                ActivationPanel(dismiss: dismiss).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .accessibilityValue(Text("Page \(index + 1) sur \(totalPanels)"))

            // The last panel carries its own actions.
            if index < totalPanels - 1 {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        index = min(index + 1, totalPanels - 1)
                    }
                } label: {
                    Text("Suivant")
                        .foregroundStyle(Color.onAccent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .accessibilityIdentifier("onboarding.next")
                .accessibilityHint(Text("Affiche la prochaine page de l'introduction."))
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func dismiss() {
        isPresented = false
    }
}

// MARK: - Panels

private struct WelcomePanel: View {
    var body: some View {
        OnboardingPanelLayout(
            title: Text("Bloquez des familles entières de numéros"),
            body: Text("Une règle WildCall couvre une tranche complète : le démarchage est refusé avant que le téléphone sonne.")
        ) {
            HashMark()
                .frame(width: 72, height: 72)
        } detail: {
            Text("Aucune donnée n'est collectée. Tout reste sur votre iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WildcardsPanel: View {
    var body: some View {
        OnboardingPanelLayout(
            title: Text("Une règle, jusqu'à un million de numéros"),
            body: Text("Terminez un numéro par `*` pour couvrir tous ceux qui commencent pareil.")
        ) {
            EmptyView()
        } detail: {
            VStack(spacing: 0) {
                example(fixedDigits: "33162", wildcardLength: 6, caption: Text("01 62, tranche réservée au démarchage en France"))
                Divider().padding(.leading, Metrics.cardPadding)
                example(fixedDigits: "34400", wildcardLength: 6, caption: Text("400, tranche des appels commerciaux en Espagne"))
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Metrics.cardRadius))
        }
    }

    private func example(fixedDigits: String, wildcardLength: Int, caption: Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PatternText(fixedDigits: fixedDigits, wildcardLength: wildcardLength, font: .title3.monospaced())
            caption
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.cardPadding)
        .accessibilityElement(children: .combine)
    }
}

private struct PacksPanel: View {
    /// The lists the app ships, by source. Country names come from the system.
    private static let sources: [(country: String, source: String)] = [
        ("FR", "ARCEP"),
        ("DE", "Bundesnetzagentur"),
        ("ES", "CNMC"),
        ("US", "FTC, FCC"),
        ("PE", "MTC"),
    ]

    var body: some View {
        OnboardingPanelLayout(
            title: Text("Des listes tenues par les régulateurs"),
            body: Text("Les packs reprennent les tranches et les numéros publiés par les autorités de chaque pays. Seuls ceux de votre pays sont activés au départ.")
        ) {
            EmptyView()
        } detail: {
            VStack(spacing: 0) {
                ForEach(Array(Self.sources.enumerated()), id: \.offset) { offset, entry in
                    if offset > 0 {
                        Divider().padding(.leading, Metrics.cardPadding)
                    }
                    HStack {
                        Text(verbatim: CountryName.localized(entry.country))
                        Spacer()
                        Text(verbatim: entry.source)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Metrics.cardRadius))
        }
    }
}

private struct ActivationPanel: View {
    let dismiss: () -> Void

    var body: some View {
        OnboardingPanelLayout(
            title: Text("Activez les \(ExtensionSlot.count) lignes WildCall"),
            body: Text("iOS limite chaque extension de blocage à 2 millions de numéros. WildCall en embarque \(ExtensionSlot.count) : cochez-les toutes dans Réglages.")
        ) {
            EmptyView()
        } detail: {
            VStack(spacing: 16) {
                Button {
                    CallBlockingSettings.open()
                    dismiss()
                } label: {
                    Text("Activer dans Réglages")
                        .foregroundStyle(Color.onAccent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint(Text("Ouvre l'app Réglages sur la page Blocage et identification d'appel."))

                Button("Plus tard") { dismiss() }
                    .foregroundStyle(.secondary)
                    .accessibilityHint(Text("Ferme l'introduction sans ouvrir Réglages."))
            }
        }
    }
}

// MARK: - Shared layout

/// Left-aligned panel : an optional mark, the title, one paragraph, then
/// the panel's own content. Scrolls when Dynamic Type makes it taller
/// than the screen.
private struct OnboardingPanelLayout<Mark: View, Detail: View>: View {
    private let title: Text
    private let descriptionText: Text
    private let mark: Mark
    private let detail: Detail

    init(
        title: Text,
        body: Text,
        @ViewBuilder mark: () -> Mark,
        @ViewBuilder detail: () -> Detail
    ) {
        self.title = title
        self.descriptionText = body
        self.mark = mark()
        self.detail = detail()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                mark
                    .padding(.bottom, 8)

                title
                    .font(.title.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                descriptionText
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                detail
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 64)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
