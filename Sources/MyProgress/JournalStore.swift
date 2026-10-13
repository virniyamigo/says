import Foundation
import Combine
import MyProgressCore

/// Keeps the original journal API, backed by the shared, observable document.
@MainActor
final class JournalStore: ObservableObject {
    @Published private(set) var entries: [JournalEntry] = []
    private let tracker: ActivityTracker
    private var subscription: AnyCancellable?
    init(tracker: ActivityTracker) {
        self.tracker = tracker
        entries = tracker.document.journal
        subscription = tracker.$document.sink { [weak self] in self?.entries = $0.journal }
    }
    func add(category: String, text: String) { tracker.addNote(category: category, text: text) }
    func delete(id: UUID) { tracker.deleteNote(id) }
}
