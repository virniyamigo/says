import SwiftUI
import MyProgressCore

extension ActivityCategory {
    var tint: Color {
        switch self {
        case .learning: return .purple
        case .programming: return .cyan
        case .english: return .orange
        case .psychology: return .pink
        case .sport: return .green
        }
    }
}

struct AppCanvas: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            (scheme == .dark ? Color(red: 0.035, green: 0.05, blue: 0.09) : Color(red: 0.95, green: 0.965, blue: 0.99))
            LinearGradient(colors: [.indigo.opacity(0.14), .clear, .cyan.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }.ignoresSafeArea()
    }
}

struct Panel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.primary.opacity(0.06)))
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.cyan)
                .frame(width: 54, height: 54).background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(.bottom, 6)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .cyan
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: symbol).font(.title3).foregroundStyle(tint)
                    .frame(width: 38, height: 38).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                Text(value).font(.system(size: 27, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyPanel: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }.padding(35).frame(maxWidth: .infinity)
    }
}

struct OutcomeGoalCard: View {
    let goal: OutcomeGoal
    @EnvironmentObject private var tracker: ActivityTracker
    var body: some View {
        let value = tracker.outcomeStats.progress(goal)
        let fraction = min(Double(value) / Double(goal.target), 1)
        Panel {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(goal.category.tint.opacity(0.12), lineWidth: 7)
                    Circle().trim(from: 0, to: fraction).stroke(goal.category.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: fraction >= 1 ? "checkmark" : goal.metric.symbol).foregroundStyle(goal.category.tint)
                }.frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 5) {
                    Text(goal.metric.title).font(.headline)
                    Text("\(goal.category.title) · \(goal.period.title.lowercased())").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(value) / \(goal.target)").font(.title3.bold()).monospacedDigit()
            }
        }
    }
}
