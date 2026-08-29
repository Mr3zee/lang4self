import SwiftUI

/// Placeholder only; the macOS app remains the active product.
struct ContentView: View {
    var body: some View {
        ContentUnavailableView(
            "iOS template",
            systemImage: "iphone",
            description: Text("Connect shared Lang4SelfCore features when the iOS product is started.")
        )
        .navigationTitle("Lang4Self")
    }
}
