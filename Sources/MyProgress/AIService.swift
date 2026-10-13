import Foundation

struct OpenAIResponse: Decodable {
    let output: [OutputItem]

    struct OutputItem: Decodable {
        let content: [ContentItem]?
    }

    struct ContentItem: Decodable {
        let type: String
        let text: String?
    }

    var text: String {
        output
            .compactMap { $0.content }
            .flatMap { $0 }
            .filter { $0.type == "output_text" }
            .compactMap { $0.text }
            .joined(separator: "\n")
    }
}

@MainActor
final class AIService {

    static let shared = AIService()

    private init() {}

    func analyzePsychologyNote(
        _ note: String
    ) async throws -> String {

        let storedKey = try AIKeychain.read()
        guard let apiKey = storedKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            throw AIError.missingAPIKey
        }

        let url = URL(
            string: "https://api.openai.com/v1/responses"
        )!

        let prompt = """
        Ти допомагаєш структурувати особистий психологічний щоденник.

        Не став діагнозів.
        Не видавай припущення за факти.
        Відповідай українською.

        Проаналізуй запис і дай:

        1. Короткий підсумок
        2. Основні емоції
        3. Думки та переживання
        4. Можливі тригери
        5. Що можна обговорити з психотерапевтом
        6. Один маленький практичний наступний крок

        Запис користувача:
        \(note)
        """

        let body: [String: Any] = [
            "model": ProcessInfo.processInfo.environment["MYPROGRESS_AI_MODEL"] ?? "gpt-4.1-mini",
            "input": prompt
        ]

        let data = try JSONSerialization.data(
            withJSONObject: body
        )

        var request = URLRequest(url: url)
        request.timeoutInterval = 60

        request.httpMethod = "POST"

        request.setValue(
            "Bearer \(apiKey)",
            forHTTPHeaderField: "Authorization"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.httpBody = data

        let (responseData, response) =
            try await URLSession.shared.data(
                for: request
            )

        guard let httpResponse =
                response as? HTTPURLResponse
        else {
            throw AIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode
        else {
            throw AIError.apiError("HTTP \(httpResponse.statusCode). Перевірте ключ, доступ до моделі та квоту.")
        }

        let decoded =
            try JSONDecoder().decode(
                OpenAIResponse.self,
                from: responseData
            )

        guard !decoded.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.invalidResponse
        }
        return decoded.text
    }
}

enum AIError: LocalizedError {

    case missingAPIKey
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {

        switch self {

        case .missingAPIKey:
            return "Додайте OpenAI API key у налаштуваннях застосунку (Keychain)."

        case .invalidResponse:
            return "Некоректна відповідь сервера."

        case .apiError(let message):
            return "OpenAI API error: \(message)"
        }
    }
}
