import SwiftUI
import UIKit

struct OnboardingFlowView: View {
    @Binding var isPresented: Bool
    @State private var index: Int = 0

    private let totalPanels = 4

    var body: some View {
        VStack(spacing: 0) {
            // Skip button top-right (idle until the last panel)
            HStack {
                Spacer()
                if index < totalPanels - 1 {
                    Button("Passer") { dismiss() }
                        .foregroundStyle(.secondary)
                        .accessibilityHint(Text("Ferme l'introduction et passe directement à l'app."))
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
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

            // Bottom action zone
            VStack(spacing: 12) {
                if index < totalPanels - 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            index = min(index + 1, totalPanels - 1)
                        }
                    } label: {
                        Text("Suivant")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .controlSize(.large)
                    .accessibilityHint(Text("Affiche la prochaine page de l'introduction."))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }

    private func dismiss() {
        isPresented = false
    }
}

// MARK: - Panels

private struct WelcomePanel: View {
    var body: some View {
        OnboardingPanelLayout(
            icon: "shield.lefthalf.filled",
            iconTint: .indigo,
            title: Text("Bienvenue dans WildCall"),
            body: Text("Bloquez les appels indésirables avant même qu'ils ne sonnent. Démarchage, spam, faux numéros, appels IA… silencieusement filtrés."),
            footnote: Text("Aucune donnée n'est collectée. Tout reste sur votre iPhone.")
        ) {
            Text("WildCall est gratuit. Les pourboires sont optionnels mais appréciés.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 24)
        }
    }
}

private struct WildcardsPanel: View {
    var body: some View {
        OnboardingPanelLayout(
            icon: "asterisk.circle.fill",
            iconTint: .indigo,
            title: Text("Une règle : des milliers de numéros"),
            body: Text("Saisissez un motif comme `+33162*` pour bloquer toute une famille de numéros en une seule règle. Pas besoin d'ajouter chaque numéro manuellement.")
        ) {
            VStack(alignment: .leading, spacing: 8) {
                wildcardExample("+33162*", subtitle: Text("≈ 1 000 000 numéros démarchage Paris"))
                wildcardExample("+1800555*", subtitle: Text("≈ 10 000 numéros gratuits US"))
            }
            .padding(.top, 12)
        }
    }

    private func wildcardExample(_ pattern: String, subtitle: Text) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: pattern)
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(.indigo)
                subtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

private struct PacksPanel: View {
    var body: some View {
        OnboardingPanelLayout(
            icon: "shippingbox.fill",
            iconTint: .indigo,
            title: Text("Packs communautaires"),
            body: Text("WildCall maintient des listes de préfixes connus : ARCEP en France, numéros gratuits US, premium-rate UK. Synchronisation quotidienne en arrière-plan.")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                packBullet("🇫🇷", title: Text("Démarchage FR"), subtitle: Text("Plages ARCEP 0162-0165, 0568-0569"))
                packBullet("🇺🇸", title: Text("Spam US"), subtitle: Text("Numéros gratuits 1-800-555-*"))
                packBullet("🇬🇧", title: Text("Premium-rate UK"), subtitle: Text("0843, 0844 démarchage"))
            }
            .padding(.top, 12)
        }
    }

    private func packBullet(_ flag: String, title: Text, subtitle: Text) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: flag).font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                title.font(.subheadline.weight(.medium))
                subtitle.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ActivationPanel: View {
    let dismiss: () -> Void

    var body: some View {
        OnboardingPanelLayout(
            icon: "checkmark.shield.fill",
            iconTint: .indigo,
            title: Text("Activer WildCall"),
            body: Text("iOS demande votre autorisation pour que l'app puisse filtrer les appels. Cela prend 10 secondes dans Réglages.")
        ) {
            VStack(spacing: 12) {
                Button {
                    openCallBlockingSettings()
                    dismiss()
                } label: {
                    Label {
                        Text("Activer dans Réglages")
                    } icon: {
                        Image(systemName: "arrow.up.right.square.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.large)
                .accessibilityHint(Text("Ouvre l'app Réglages sur la page Blocage et identification d'appel."))

                Button("Plus tard") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHint(Text("Ferme l'introduction sans ouvrir Réglages."))
            }
            .padding(.top, 24)
        }
    }

    private func openCallBlockingSettings() {
        let preferred = URL(string: "App-prefs:Phone&path=CALL_BLOCKING")
        let fallback = URL(string: UIApplication.openSettingsURLString)
        if let url = preferred, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = fallback {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Shared layout

private struct OnboardingPanelLayout<Bottom: View>: View {
    let icon: String
    let iconTint: Color
    let title: Text
    let descriptionText: Text
    var footnote: Text? = nil
    let bottom: Bottom

    init(
        icon: String,
        iconTint: Color,
        title: Text,
        body: Text,
        footnote: Text? = nil,
        @ViewBuilder bottom: () -> Bottom = { EmptyView() }
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.descriptionText = body
        self.footnote = footnote
        self.bottom = bottom()
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            Image(systemName: icon)
                .font(.system(size: 80))
                .foregroundStyle(iconTint)
                .padding(.bottom, 8)
                .accessibilityHidden(true)

            title
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            descriptionText
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            bottom
                .padding(.horizontal, 24)

            if let footnote {
                footnote
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
            }

            Spacer(minLength: 20)
        }
    }
}

// Convenience initializer when there's no bottom builder.
extension OnboardingPanelLayout where Bottom == EmptyView {
    init(
        icon: String,
        iconTint: Color,
        title: Text,
        body: Text,
        footnote: Text? = nil
    ) {
        self.init(icon: icon, iconTint: iconTint, title: title, body: body, footnote: footnote, bottom: { EmptyView() })
    }
}
