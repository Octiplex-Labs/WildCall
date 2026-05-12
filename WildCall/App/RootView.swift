import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Phase 0 — Scaffold") {
                    Text("WildCall is alive.")
                }
            }
            .navigationTitle("WildCall")
        }
    }
}

#Preview {
    RootView()
}
