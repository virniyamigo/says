import SwiftUI
import AppKit
import MyProgressCore

struct LearningReportView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var reportID = UUID().uuidString
    @State private var records: [OutcomeRecord] = []
    @State private var error: String?
    private var prompt: String {
        """
        Підсумуй наше заняття англійською для MyProgress. Поверни лише JSON без markdown.
        Враховуй лише те, що ми справді виконали, не вигадуй досягнень. Пропускай нульові метрики.
        Формат:
        {"id":"\(reportID)","date":"\(ISO8601DateFormatter().string(from: Date()))","category":"english","summary":"короткий підсумок","results":[{"metric":"words","quantity":10},{"metric":"exercises","quantity":2}]}
        Дозволені метрики: words (опрацьовані слова), exercises (завершені вправи), lessons (завершені уроки), conversations (окрема практика розмови). Кількість — додатне ціле число.
        Не змінюй зазначений id. Збережи той самий id і дату, якщо я повторно прошу звіт цього ж заняття. Якщо результатів немає, скажи про це замість JSON.
        """
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeading(title: "Заняття з ChatGPT", subtitle: "Один підсумок — оновлені результати та цілі", symbol: "bubble.left.and.bubble.right")
            Text("1. Скопіюй запит і надішли його наприкінці заняття в ChatGPT.\n2. Скопіюй JSON-відповідь, встав її тут і перевір кількості.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Скопіювати запит для ChatGPT") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(prompt, forType: .string)
                }
                Button("Вставити звіт") { text = NSPasteboard.general.string(forType: .string) ?? "" }
            }
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(height: 180)
                .padding(8).overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.25)))
            Button("Перевірити підсумок") { validate() }.disabled(text.isEmpty)
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(records) { record in
                HStack { Text(record.metric.title); Spacer(); Text("\(record.quantity)").bold() }
            }
            Text("Застосунок не читає історію ChatGPT. Зберігай лише підтверджені тобою результати. Повторне вставлення того самого звіту з незмінним id не збільшує прогрес.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Скасувати") { dismiss() }
                Spacer()
                Button("Підтверджую — зберегти") {
                    tracker.importOutcomes(records)
                    if tracker.storageError == nil { dismiss() }
                }.buttonStyle(.borderedProminent).disabled(records.isEmpty)
            }
        }.padding(26).frame(width: 630)
            .onChange(of: text) { _, _ in records = []; error = nil }
    }
    private func validate() {
        do { records = try LearningReport.read(text); error = nil }
        catch { records = []; self.error = "Не вдалося прочитати підсумок. Потрібен JSON зазначеного формату з датою ISO 8601, коректними метриками та кількостями." }
    }
}
