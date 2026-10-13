import Foundation

public struct LearningReport: Codable, Sendable {
    public var id: String
    public var date: String
    public var category: ActivityCategory
    public var summary: String
    public var results: [Item]
    public struct Item: Codable, Sendable {
        public var metric: OutcomeMetric
        public var quantity: Int
    }
    public static func read(_ text: String, now: Date = Date()) throws -> [OutcomeRecord] {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            var lines = clean.components(separatedBy: "\n")
            guard lines.count >= 3, lines.last?.trimmingCharacters(in: .whitespaces) == "```" else { throw OutcomeCSVError.invalidFormat }
            lines.removeFirst(); lines.removeLast(); clean = lines.joined(separator: "\n")
        }
        let report = try JSONDecoder().decode(Self.self, from: Data(clean.utf8))
        let parser = ISO8601DateFormatter()
        guard !report.id.isEmpty, report.id.count <= 200,
              [.english, .learning].contains(report.category), let date = parser.date(from: report.date), date <= now,
              !report.results.isEmpty, report.results.count <= 10,
              Set(report.results.map(\.metric)).count == report.results.count,
              report.results.allSatisfy({
                  [.words, .lessons, .exercises, .conversations, .films].contains($0.metric)
                  && $0.metric.supports(report.category) && (1...1_000_000).contains($0.quantity)
              }) else { throw OutcomeCSVError.invalidRow(1) }
        return report.results.map {
            OutcomeRecord(category: report.category, metric: $0.metric, quantity: $0.quantity,
                          date: date, source: .imported, reference: "chatgpt:\(report.id):\($0.metric.rawValue)",
                          note: "ChatGPT: \(report.summary)")
        }
    }
}
