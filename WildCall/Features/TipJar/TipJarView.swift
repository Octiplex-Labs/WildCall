import StoreKit
import SwiftUI

struct TipJarView: View {
    @State private var products: [Product] = []
    @State private var isLoading: Bool = true
    @State private var loadError: String? = nil
    @State private var purchaseInProgress: String? = nil
    @State private var lastPurchaseThanks: Bool = false

    /// Product identifiers that must be registered in App Store Connect as
    /// **consumable** in-app purchases under the WildCall app. Until they're
    /// created and approved, `Product.products(for:)` returns an empty array
    /// and the UI shows the "indisponible" message.
    static let productIdentifiers: Set<String> = [
        "com.octiplex.wildcall.tip.small",
        "com.octiplex.wildcall.tip.medium",
        "com.octiplex.wildcall.tip.large"
    ]

    var body: some View {
        List {
            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Chargement…").foregroundStyle(.secondary)
                    }
                } else if let error = loadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                } else if products.isEmpty {
                    ContentUnavailableView(
                        "Soutiens indisponibles",
                        systemImage: "heart.slash",
                        description: Text("Les pourboires apparaîtront ici une fois la configuration App Store finalisée.")
                    )
                } else {
                    ForEach(products, id: \.id) { product in
                        TipRow(
                            product: product,
                            isPurchasing: purchaseInProgress == product.id,
                            onTap: { Task { await purchase(product) } }
                        )
                    }
                }
            } header: {
                Text("Soutenir WildCall")
            } footer: {
                Text("WildCall est gratuit et sans publicité. Si l'app vous est utile, vous pouvez laisser un pourboire — c'est totalement optionnel.")
                    .font(.caption)
            }

            if lastPurchaseThanks {
                Section {
                    Label("Merci 💜", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.indigo)
                }
            }
        }
        .navigationTitle("Pourboire")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadProducts()
        }
    }

    private func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIdentifiers)
            await MainActor.run {
                self.products = loaded.sorted { $0.price < $1.price }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.loadError = "Impossible de joindre l'App Store (\(error.localizedDescription))."
                self.isLoading = false
            }
        }
    }

    private func purchase(_ product: Product) async {
        await MainActor.run { purchaseInProgress = product.id }
        defer { Task { @MainActor in purchaseInProgress = nil } }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await MainActor.run { lastPurchaseThanks = true }
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            // Surface failures via the inline loadError slot so we don't
            // need an alert sheet for a tip-jar that's purely optional.
            await MainActor.run {
                loadError = error.localizedDescription
            }
        }
    }
}

private struct TipRow: View {
    let product: Product
    let isPurchasing: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName).font(.body)
                    if !product.description.isEmpty {
                        Text(product.description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isPurchasing {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.indigo)
                }
            }
        }
        .disabled(isPurchasing)
    }
}
