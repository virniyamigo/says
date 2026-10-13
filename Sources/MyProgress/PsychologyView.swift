import SwiftUI

struct PsychologyView: View {
    var body: some View {
        TabView {
            PsychologyJournalView().tabItem { Label("Щоденник", systemImage: "book") }
            ActivityView(category: .psychology).tabItem { Label("Активність", systemImage: "timer") }
        }
    }
}
