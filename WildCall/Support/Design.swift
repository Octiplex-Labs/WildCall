import CallKit
import SwiftUI
import UIKit

/// Shared values of the interface. Spacing sits on a 4 pt grid, surfaces
/// are the system greys, and the accent (`AccentColor` in the asset
/// catalog) is kept for the primary action and the wildcard asterisks.
enum Metrics {
    static let cardRadius: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let pageMargin: CGFloat = 16
    /// Leading icon column of a list row, so labels line up.
    static let iconColumn: CGFloat = 28
}

extension Color {
    /// Text on an accent fill : white in light mode, near-black in dark
    /// mode where the accent is too bright for white text.
    static let onAccent = Color("OnAccent")
}

/// WildCall's signature : a number set in monospaced digits, the fixed
/// part in the text colour and the wildcard part in the accent.
struct PatternText: View {
    let fixedDigits: String
    var wildcardLength: Int = 0
    var font: Font = .body.monospaced()

    var body: some View {
        Text(attributed).font(font)
    }

    private var attributed: AttributedString {
        var text = AttributedString("+\(fixedDigits)")
        var wildcards = AttributedString(String(repeating: "*", count: wildcardLength))
        wildcards.swiftUI.foregroundColor = .accentColor
        text.append(wildcards)
        return text
    }
}

/// A raised surface for the status messages shown above the rules list.
struct StatusCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.cardPadding)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Metrics.cardRadius))
            .padding(.horizontal, Metrics.pageMargin)
    }
}

/// The app's mark, the same four bars as the icon, drawn in code so the
/// introduction opens on the product instead of a stock symbol.
struct HashMark: View {
    var body: some View {
        Canvas { context, size in
            // Geometry of the 1024 pt icon : bars 100 wide and 720 long,
            // centred 216 from the middle.
            let unit = min(size.width, size.height) / 720
            let bar = 100 * unit
            let length = 720 * unit
            let origin = CGPoint(x: (size.width - length) / 2, y: (size.height - length) / 2)
            let offsets = [94 * unit, 526 * unit]
            var path = Path()
            for offset in offsets {
                path.addRoundedRect(
                    in: CGRect(x: origin.x + offset, y: origin.y, width: bar, height: length),
                    cornerSize: CGSize(width: bar / 2, height: bar / 2)
                )
                path.addRoundedRect(
                    in: CGRect(x: origin.x, y: origin.y + offset, width: length, height: bar),
                    cornerSize: CGSize(width: bar / 2, height: bar / 2)
                )
            }
            context.fill(path, with: .foreground)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

enum CountryName {
    /// "France" for "FR" in the user's language, the code itself otherwise.
    static func localized(_ regionCode: String) -> String {
        Locale.current.localizedString(forRegionCode: regionCode) ?? regionCode
    }
}

/// Opens Réglages → Apps → Téléphone → Blocage et identification d'appel
/// through CallKit's public entry point, with the app's own settings page
/// as a fallback.
enum CallBlockingSettings {
    @MainActor
    static func open() {
        Task { @MainActor in
            let opened = await requestOpen()
            guard !opened else { return }
            if let url = URL(string: UIApplication.openSettingsURLString) {
                _ = await UIApplication.shared.open(url)
            }
        }
    }

    private nonisolated static func requestOpen() async -> Bool {
        await withCheckedContinuation { continuation in
            CXCallDirectoryManager.sharedInstance.openSettings { error in
                continuation.resume(returning: error == nil)
            }
        }
    }
}

enum PackTitle {
    /// Pack titles are written in French in the manifests. The string
    /// catalog carries translations for the Octiplex packs ; a title it
    /// does not know is shown as written.
    static func localized(_ title: String) -> String {
        String(localized: String.LocalizationValue(title))
    }
}
