import SwiftUI

private struct MoodMetric: Identifiable {
    let id: String
    let label: String
    let icon: String
    let color: Color
}

/// The full check-in, reached only by tapping Home's mood bubble — not
/// embedded inline anymore.
struct MoodSurveyView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var energy: Double = 7
    @State private var mood: Double = 7
    @State private var motivation: Double = 6
    @State private var sleep: Double = 7

    private let metrics: [MoodMetric] = [
        MoodMetric(id: "energy", label: "Energy", icon: "bolt.fill", color: Theme.Brand.gold),
        MoodMetric(id: "mood", label: "Mood", icon: "face.smiling.fill", color: Theme.Brand.pink),
        MoodMetric(id: "motivation", label: "Motivation", icon: "scope", color: Theme.Brand.purple),
        MoodMetric(id: "sleep", label: "Sleep", icon: "moon.fill", color: Theme.Brand.blue),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.Ink.secondary)
                            .frame(width: 40, height: 40)
                            .glassSurface(cornerRadius: 20)
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.top, Theme.Space.md)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mood Check-in").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                    Text("Takes 10 seconds.").font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                }

                StatChip(label: "Streak", value: "\(app.moodStreak)d", tint: Theme.Brand.gold)

                ForEach(metrics) { metric in
                    sliderCard(for: metric)
                }

                Button(app.moodLoggedToday ? "Logged for today" : "Log Check-in") { logIt() }
                    .buttonStyle(PactButtonStyle(kind: app.moodLoggedToday ? .tinted(Theme.Brand.lime) : .primary))
                    .disabled(app.moodLoggedToday)

                if !app.moodHistory.isEmpty {
                    historyStrip
                }
            }
            .padding(Theme.Space.lg)
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(PactBackground())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func binding(for id: String) -> Binding<Double> {
        switch id {
        case "energy": return $energy
        case "mood": return $mood
        case "motivation": return $motivation
        default: return $sleep
        }
    }

    private func sliderCard(for metric: MoodMetric) -> some View {
        let value = binding(for: metric.id)
        return PactCard(tint: metric.color) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: metric.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(metric.color)
                    Text(metric.label).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                    Spacer()
                    Text("\(Int(value.wrappedValue))").font(Theme.Font.number(22)).foregroundStyle(metric.color)
                    Text("/10").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                }
                PactSlider(value: value, tint: metric.color)
            }
        }
    }

    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Last 7 Days")
            HStack(alignment: .bottom, spacing: Theme.Space.xs) {
                ForEach(app.moodHistory.suffix(7)) { entry in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.Brand.purple.opacity(0.75))
                            .frame(width: 22, height: max(6, entry.average * 8))
                        Text(entry.date.formatted(.dateTime.weekday(.narrow)))
                            .font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                    }
                }
            }
            .frame(height: 96, alignment: .bottom)
        }
    }

    private func logIt() {
        withAnimation(Theme.Motion.pop) {
            app.logMoodCheckIn(energy: energy, mood: mood, motivation: motivation, sleep: sleep)
        }
    }
}

#Preview {
    NavigationStack { MoodSurveyView() }.environment(AppModel())
}
