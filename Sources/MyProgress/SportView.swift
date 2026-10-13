import SwiftUI

// Existing entry point delegates to the shared activity screen.
struct SportView: View {
    var body: some View { ActivityView(category: .sport) }
}
