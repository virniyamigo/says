import SwiftUI
import MyProgressCore

struct TrackingSettingsView: View {
    @EnvironmentObject private var tracker: ActivityTracker
    @State private var bundleID = ""
    @State private var category = ActivityCategory.programming
    @State private var apiKey = ""
    @State private var keyMessage = ""
    @State private var passive = false
    @AppStorage("myprogress.showMenuBar") private var showMenuBar = true
    @AppStorage("myprogress.appearance") private var appearance = "dark"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: "Налаштування", subtitle: "Зроби трекінг своїм — від стилю до автоматизації", symbol: "slider.horizontal.3")
                Picker("Вигляд", selection: $appearance) {
                    Text("Темний").tag("dark"); Text("Світлий").tag("light"); Text("Як у системі").tag("system")
                }.pickerStyle(.segmented)
                Panel {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Показувати швидке керування в меню macOS", isOn: $showMenuBar)
                        LoginSettingsView()
                    }
                }
                GitSettingsPanel()
                Text("Щоденні цілі").font(.title2.bold())
                ForEach(ActivityCategory.allCases) { item in
                    Stepper(value: Binding(get: { tracker.document.goals.first { $0.category == item }?.dailyMinutes ?? 30 },
                                           set: { tracker.setGoal(item, minutes: $0) }), in: 1...1440, step: 5) {
                        Text("\(item.title): \(tracker.document.goals.first { $0.category == item }?.dailyMinutes ?? 30) хв")
                    }
                }
                Divider()
                Text("Автоматичний трекінг").font(.title2.bold())
                Toggle("Враховувати активну програму за правилами", isOn: Binding(
                    get: { tracker.document.settings.automaticEnabled }, set: { tracker.setAutomatic($0) }))
                Picker("Пауза після бездіяльності", selection: Binding(
                    get: { tracker.document.settings.idleSeconds }, set: { tracker.setIdle($0) })) {
                    Text("1 хв").tag(60.0); Text("2 хв").tag(120.0); Text("5 хв").tag(300.0); Text("10 хв").tag(600.0)
                }
                Text("Ручна сесія має пріоритет. Сон і бездіяльність призупиняють облік. Ми не читаємо заголовки вікон, тексти, адреси сайтів або натиснуті клавіші. Час активної програми — наближена оцінка, а не доказ навчання.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(tracker.document.settings.rules) { rule in
                    HStack {
                        Text(rule.bundleIdentifier).textSelection(.enabled)
                        Spacer(); Text(rule.category.title)
                        Toggle("Пауза за бездіяльністю", isOn: Binding(get: { rule.pauseWhenIdle }, set: { tracker.setRuleIdle(rule.id, enabled: $0) }))
                            .font(.caption).toggleStyle(.checkbox)
                        Button(role: .destructive) { tracker.removeRule(rule.id) } label: { Image(systemName: "trash") }
                    }
                }
                HStack {
                    Picker("Напрям програми", selection: $category) { ForEach(ActivityCategory.allCases) { Text($0.title).tag($0) } }
                    Toggle("Перегляд / читання без пауз", isOn: $passive)
                    Button("Вибрати програму…") { tracker.chooseAutomaticApp(category: category, passive: passive) }
                        .buttonStyle(.borderedProminent)
                }
                Text("Виберіть ChatGPT чи свій відеоплеєр і напрям «Англійська». Для фільмів увімкніть режим без пауз; він рахує час, поки вибрана програма активна, а не перевіряє факт відтворення.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Bundle ID, наприклад com.apple.dt.Xcode", text: $bundleID)
                    Picker("Напрям", selection: $category) { ForEach(ActivityCategory.allCases) { Text($0.title).tag($0) } }
                    Button("Додати / оновити") { tracker.addRule(bundleID: bundleID, category: category, pauseWhenIdle: !passive); bundleID = "" }
                        .disabled(bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Активна програма: \(tracker.frontmostBundleID.isEmpty ? "невідома" : tracker.frontmostBundleID)")
                    .font(.caption).textSelection(.enabled)
                Text("Bundle ID можна отримати в Terminal: osascript -e 'id of app \"Xcode\"'. Браузерне правило враховує весь браузер; спорт слід записувати вручну.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("AI для щоденника (необов’язково)").font(.title2.bold())
                Text("Ключ зберігається у macOS Keychain. Аналіз надсилається лише за вашою дією. Модель за замовчуванням: gpt-4.1-mini; її можна змінити змінною MYPROGRESS_AI_MODEL.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("OpenAI API key", text: $apiKey)
                HStack {
                    Button("Зберегти ключ у Keychain") {
                        do { try AIKeychain.save(apiKey); apiKey = ""; keyMessage = "Ключ збережено." }
                        catch { keyMessage = error.localizedDescription }
                    }.disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Видалити ключ", role: .destructive) {
                        do { try AIKeychain.delete(); keyMessage = "Ключ видалено." }
                        catch { keyMessage = error.localizedDescription }
                    }
                }
                if !keyMessage.isEmpty { Text(keyMessage).font(.caption) }
                Divider()
                Text("Дані та резервні копії").font(.title2.bold())
                Text(tracker.repository.url.path).font(.caption).textSelection(.enabled)
                HStack {
                    Button("Експортувати JSON…") { tracker.exportData() }
                    Button("Відновити з JSON…") { tracker.importData() }
                }
                Text("Усі записи зберігаються локально. Експорт містить особистий щоденник, але не API-ключ. Перед відновленням створюється резервна копія поточних даних.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(30)
        }.frame(minWidth: 760, minHeight: 650).background(AppCanvas()).disabled(!tracker.writable)
    }
}
