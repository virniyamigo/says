import Foundation

// Retains the original journal's Codable keys so existing entries can be migrated.
public struct JournalEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var category: String
    public var text: String
    public var createdAt: Date
    public init(id: UUID = UUID(), category: String, text: String, createdAt: Date = Date()) {
        self.id = id; self.category = category; self.text = text; self.createdAt = createdAt
    }
}
