import SwiftUI

// Existing entry point delegates to the shared activity screen.
struct ProgrammingView: View {
    var body: some View { ActivityView(category: .programming) }
}
