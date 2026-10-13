import SwiftUI
import MyProgressCore

struct GitSettingsPanel: View {
    @EnvironmentObject private var tracker: ActivityTracker
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 16) {
                Label("Результати програмування", systemImage: "arrow.triangle.branch").font(.title2.bold())
                Toggle("Автоматично збирати мої Git-коміти", isOn: Binding(
                    get: { tracker.document.gitTracking.enabled }, set: { tracker.setGitEnabled($0) }))
                Text("Оновлення щохвилини, поки застосунок відкритий. Читаються локальні коміти за останні 30 днів у вибраних папках, лише для заданого email автора. Той самий SHA не рахується двічі, навіть у кількох копіях репозиторію.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(tracker.document.gitTracking.repositories) { repo in GitRepositoryRow(repository: repo) }
                HStack {
                    Button("Додати папку Git-репозиторію…") { tracker.chooseGitRepository() }
                    Button(tracker.gitRefreshing ? "Оновлення…" : "Оновити зараз") { tracker.refreshGit() }
                        .disabled(!tracker.document.gitTracking.enabled || tracker.gitRefreshing)
                }
                Text(tracker.gitStatus).font(.caption).foregroundStyle(.secondary)
                if let last = tracker.lastGitSync { Text("Остання перевірка: \(last.formatted(date: .omitted, time: .shortened))").font(.caption) }
                Divider()
                Toggle("Завершувати задачі за явною позначкою в коміті", isOn: Binding(
                    get: { tracker.document.gitTracking.completeReferencedTasks }, set: { tracker.setGitTaskCompletion($0) }))
                Text("У задачі є код MP-XXXXXXXX. Повідомлення «Done MP-XXXXXXXX» або «Fixes MP-XXXXXXXX» завершить саме цю задачу після нового коміту. Звичайний коміт не закриває задач. Merge-коміти пропускаються; Git fetch/push застосунок не виконує.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct GitRepositoryRow: View {
    let repository: TrackedGitRepository
    @EnvironmentObject private var tracker: ActivityTracker
    @State private var email: String
    init(repository: TrackedGitRepository) { self.repository = repository; _email = State(initialValue: repository.authorEmail) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(repository.name, systemImage: "folder").font(.headline)
                Spacer()
                Button(role: .destructive) { tracker.removeGitRepository(repository.id) } label: { Image(systemName: "trash") }
            }
            Text(repository.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                TextField("Email автора комітів", text: $email)
                Button("Зберегти email") { tracker.updateGitAuthor(repository.id, email: email) }
            }
        }.padding(14).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}
