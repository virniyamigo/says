import Foundation

public enum OutcomeCSVError: LocalizedError {
    case invalidFormat, invalidRow(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Очікується CSV із заголовком source,external_id,date,category,metric,quantity,note."
        case .invalidRow(let row): return "Некоректний CSV-рядок \(row). Перевірте дату, напрям, метрику та додатну кількість."
        }
    }
}

public enum OutcomeCSV {
    /// Explicit import format until a user's learning-service API is identified.
    public static func read(_ text: String, now: Date = Date()) throws -> [OutcomeRecord] {
        let rows = try split(text)
        guard rows.first == ["source", "external_id", "date", "category", "metric", "quantity", "note"] else {
            throw OutcomeCSVError.invalidFormat
        }
        let dateParser = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try rows.dropFirst().enumerated().map { index, row in
            guard row.count == 7, !row[0].isEmpty, !row[1].isEmpty,
                  let date = dateParser.date(from: row[2]) ?? fractional.date(from: row[2]), date <= now,
                  let category = ActivityCategory(rawValue: row[3]), let metric = OutcomeMetric(rawValue: row[4]),
                  !metric.isDerived, metric.supports(category), let quantity = Int(row[5]),
                  (1...1_000_000).contains(quantity) else { throw OutcomeCSVError.invalidRow(index + 2) }
            // Length prefix prevents collisions between service names and external identifiers.
            let reference = "csv:\(row[0].utf8.count):\(row[0]):\(row[1])"
            return .init(category: category, metric: metric, quantity: quantity, date: date,
                         source: .imported, reference: reference, note: row[6])
        }
    }
    private static func split(_ text: String) throws -> [[String]] {
        var text = text
        if text.first == "\u{FEFF}" { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let chars = Array(text)
        var rows: [[String]] = []; var row: [String] = []; var field = ""
        var quoted = false; var closedQuote = false; var index = 0
        func finishField() { row.append(field); field = ""; closedQuote = false }
        func finishRow() { finishField(); if row != [""] { rows.append(row) }; row = [] }
        while index < chars.count {
            let char = chars[index]
            if quoted {
                if char == "\"" {
                    if index + 1 < chars.count && chars[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { quoted = false; closedQuote = true }
                } else { field.append(char) }
            } else if char == "," { finishField() }
            else if char == "\n" { finishRow() }
            else if char == "\"" && field.isEmpty && !closedQuote { quoted = true }
            else {
                guard !closedQuote && char != "\"" else { throw OutcomeCSVError.invalidFormat }
                field.append(char)
            }
            index += 1
        }
        guard !quoted else { throw OutcomeCSVError.invalidFormat }
        if !field.isEmpty || !row.isEmpty || closedQuote { finishRow() }
        return rows
    }
}
