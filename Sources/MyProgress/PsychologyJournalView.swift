import SwiftUI

struct PsychologyJournalView: View {

    @EnvironmentObject private var store: JournalStore
    @EnvironmentObject private var tracker: ActivityTracker
    @State private var confirmAnalysis = false
    @State private var deletingEntry: UUID?

    @AppStorage("myprogress.journal.draft") private var noteText = ""
    @State private var aiResult = ""
    @State private var isAnalyzing = false

    private var psychologyEntries: [JournalEntry] {
        store.entries.filter {
            $0.category == "Psychology"
        }
    }

    var body: some View {

        ScrollView {

            VStack(
                alignment: .leading,
                spacing: 20
            ) {

                Text("Психологічний щоденник")
                    .font(.largeTitle)
                    .bold()

                Text("Нова нотатка")
                    .font(.headline)

                TextEditor(text: $noteText)
                    .font(.body)
                    .disabled(isAnalyzing)
                    .frame(minHeight: 180)
                    .padding(10)
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 12
                        )
                        .stroke(.gray.opacity(0.3))
                    }

                HStack(spacing: 12) {

                    Button {
                        store.add(
                            category: "Psychology",
                            text: noteText
                        )

                        if tracker.storageError == nil { noteText = "" }

                    } label: {
                        Label(
                            "Зберегти",
                            systemImage: "square.and.arrow.down"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzing || noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        confirmAnalysis = true
                    } label: {
                        Label(
                            isAnalyzing
                                ? "Аналізую..."
                                : "AI Аналіз",
                            systemImage: "sparkles"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        noteText.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty || isAnalyzing
                    )

                    Button {
                        noteText = ""
                        aiResult = ""
                    } label: {
                        Label(
                            "Очистити",
                            systemImage: "trash"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAnalyzing)
                }

                if !aiResult.isEmpty {

                    Divider()

                    Text("AI-рефлексія")
                        .font(.title2)
                        .bold()

                    Button("Зберегти аналіз у щоденник") {
                        store.add(category: "Psychology", text: "AI-рефлексія\n\nЗапис: \(noteText)\n\nАналіз: \(aiResult)")
                        if tracker.storageError == nil { aiResult = "" }
                    }.disabled(aiResult.hasPrefix("Помилка:"))

                    Text(aiResult)
                        .textSelection(.enabled)
                        .padding()
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .background(
                            RoundedRectangle(
                                cornerRadius: 14
                            )
                            .fill(.quaternary.opacity(0.5))
                        )
                }

                Divider()

                HStack {

                    Text("Мої записи")
                        .font(.title2)
                        .bold()

                    Spacer()

                    Text("\(psychologyEntries.count)")
                        .foregroundStyle(.secondary)
                }

                if psychologyEntries.isEmpty {

                    Text("Записів поки немає")
                        .foregroundStyle(.secondary)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .center
                        )
                        .padding(.vertical, 40)

                } else {

                    VStack(spacing: 12) {

                        ForEach(psychologyEntries) { entry in

                            VStack(
                                alignment: .leading,
                                spacing: 10
                            ) {

                                Text(entry.text)
                                    .textSelection(.enabled)

                                HStack {

                                    Text(
                                        entry.createdAt.formatted(
                                            date: .abbreviated,
                                            time: .shortened
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                    Spacer()

                                    Button {
                                        deletingEntry = entry.id
                                    } label: {
                                        Image(
                                            systemName: "trash"
                                        )
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(
                                    cornerRadius: 14
                                )
                                .fill(
                                    .quaternary.opacity(0.35)
                                )
                            )
                        }
                    }
                }
            }
            .padding(40)
        }
        .onChange(of: noteText) { _, _ in if !isAnalyzing { aiResult = "" } }
        .alert("Надіслати запис для AI-аналізу?", isPresented: $confirmAnalysis) {
            Button("Надіслати") { analyzeNote() }
            Button("Скасувати", role: .cancel) {}
        } message: {
            Text("Текст буде передано до OpenAI. Аналіз є допомогою для рефлексії, а не діагнозом. Щоденник працює і без AI.")
        }
        .alert("Видалити запис?", isPresented: Binding(get: { deletingEntry != nil }, set: { if !$0 { deletingEntry = nil } })) {
            Button("Видалити", role: .destructive) {
                if let id = deletingEntry { store.delete(id: id) }; deletingEntry = nil
            }
            Button("Скасувати", role: .cancel) { deletingEntry = nil }
        }
    }

    private func analyzeNote() {
        let text = noteText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !text.isEmpty else {
            return
        }

        isAnalyzing = true
        aiResult = ""

        Task {
            do {
                let result = try await AIService.shared
                    .analyzePsychologyNote(text)

                aiResult = result

            } catch {
                aiResult = "Помилка: \(error.localizedDescription)"
            }

            isAnalyzing = false
        }
    }
}
