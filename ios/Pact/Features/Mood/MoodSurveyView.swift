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
    @State private var justLogged = false
    @State private var barsShown = false

    private let metrics: [MoodMetric] = [
        MoodMetric(id: "energy", label: "Energy", icon: "bolt.fill", color: Theme.Brand.gold),
        MoodMetric(id: "mood", label: "Mood", icon: "face.smiling.fill", color: Theme.Brand.pink),
        MoodMetric(id: "motivation", label: "Motivation", icon: "scope", color: Theme.Brand.purple),
        MoodMetric(id: "sleep", label: "Sleep", icon: "moon.fill", color: Theme.Brand.blue),
    ]

    private var average: Double { (energy + mood + motivation + sleep) / 4 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Ink.secondary)
                        .frame(width: 40, height: 40)
                        .glassSurface(cornerRadius: 20)
                        .clipShape(Circle())
                }
                .padding(.top, Theme.Space.md)

                reactiveHeader

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
        .overlay {
            if justLogged {
                CelebrationOverlay(icon: "sparkles", tint: Theme.Brand.lime,
                                    title: "Logged!", subtitle: "\(app.moodStreak)d streak — keep it going.") {
                    justLogged = false
                }
            }
        }
    }

    // MARK: Reactive face — mirrors the live average as you drag the sliders

    private var reactiveHeader: some View {
        VStack(spacing: Theme.Space.sm) {
            ZStack {
                Circle().fill(app.meColor)
                Image("texture-plush")
                    .resizable()
                    .scaledToFill()
                    .blendMode(.multiply)
                    .opacity(0.55)
                MoodFaceView(curvature: curvature(for: average), dark: isLightColor(app.meColor))
            }
            .frame(width: 88, height: 88)
            .clipShape(Circle())
            .overlay(Circle().stroke(Theme.Ink.primary.opacity(0.1), lineWidth: 1))
            // The glow itself carries the mood, not just the face inside
            // it — warmer and brighter the higher the average climbs,
            // rather than a fixed shadow regardless of how the check-in's
            // actually going.
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            .shadow(color: Theme.Brand.gold.opacity(max(0, (average - 6) / 4) * 0.5), radius: 22)
            .animation(Theme.Motion.settle, value: average)

            Text(rudyLine(for: average))
                .font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(Theme.Motion.fade, value: rudyLine(for: average))
        }
        .frame(maxWidth: .infinity)
    }

    private func curvature(for average: Double) -> CGFloat {
        CGFloat((average - 1) / 9 * 1.6 - 0.6)
    }

    private func rudyLine(for average: Double) -> String {
        switch average {
        case ..<3: return "Rough one, huh? Logging it counts for something."
        case 3..<5: return "Not your best day. Let's note it and move on."
        case 5..<7: return "Steady as she goes."
        case 7..<8.5: return "Pretty good day out there."
        default: return "Look at you go. Great day."
        }
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
        let maxedOut = value.wrappedValue >= 10
        return PactCard(tint: metric.color) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: metric.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(metric.color)
                        // A little flourish for maxing out a slider,
                        // instead of 10/10 looking identical to any other
                        // value.
                        .symbolEffect(.bounce, value: maxedOut)
                    Text(metric.label).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                    Spacer()
                    Text("\(Int(value.wrappedValue))").font(Theme.Font.number(22)).foregroundStyle(metric.color)
                        .contentTransition(.numericText(value: value.wrappedValue))
                        .animation(Theme.Motion.pop, value: value.wrappedValue)
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
                            .frame(width: 22, height: barsShown ? max(6, entry.average * 8) : 6)
                        Text(entry.date.formatted(.dateTime.weekday(.narrow)))
                            .font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                    }
                }
            }
            .frame(height: 96, alignment: .bottom)
        }
        .onAppear {
            withAnimation(Theme.Motion.settle.delay(0.1)) { barsShown = true }
        }
    }

    private func logIt() {
        withAnimation(Theme.Motion.pop) {
            app.logMoodCheckIn(energy: energy, mood: mood, motivation: motivation, sleep: sleep)
            justLogged = true
        }
    }
}

/// The mood screen's own reactive face — separate from `InitialBadge`'s
/// static `SimpleFace` since it animates live with the slider values, and
/// across the whole curve, not just the mouth. The old version only ever
/// moved the mouth and shrank the eyes slightly at the happy end, which
/// left a sad mood reading as barely different from neutral, and the eyes
/// themselves were two flat capsules with no real character. Eyebrows
/// (tilting down and in as it gets sadder) and a blush that warms in as it
/// gets happier give both ends of the range something to actually show.
private struct MoodFaceView: View {
    var curvature: CGFloat // -1 (frown) ... 1 (big smile)
    var dark: Bool
    var size: CGFloat = 88

    private var happiness: CGFloat { max(0, curvature) }
    private var sadness: CGFloat { max(0, -curvature) }

    var body: some View {
        ZStack {
            HStack(spacing: size * 0.48) {
                Circle().frame(width: size * 0.15, height: size * 0.095)
                Circle().frame(width: size * 0.15, height: size * 0.095)
            }
            .foregroundStyle(Theme.Brand.pink.opacity(0.4 * happiness))
            .offset(y: size * 0.05)

            HStack(spacing: size * 0.24) {
                Capsule().frame(width: size * 0.15, height: size * 0.028)
                    .rotationEffect(.degrees(Double(sadness) * 16))
                Capsule().frame(width: size * 0.15, height: size * 0.028)
                    .rotationEffect(.degrees(Double(sadness) * -16))
            }
            .offset(y: -size * (0.29 + 0.03 * sadness))

            HStack(spacing: size * 0.22) {
                Capsule().frame(width: size * 0.085, height: size * (0.17 - 0.1 * happiness))
                Capsule().frame(width: size * 0.085, height: size * (0.17 - 0.1 * happiness))
            }
            .offset(y: -size * (0.13 + 0.015 * happiness))

            MoodMouth(curvature: curvature)
                .stroke(style: StrokeStyle(lineWidth: max(2, size * 0.055), lineCap: .round))
                .frame(width: size * 0.42, height: size * 0.18)
                .offset(y: size * 0.2)
        }
        .foregroundStyle(dark ? Theme.Ink.primary : Color.white)
        .animation(Theme.Motion.settle, value: curvature)
    }
}

/// A mouth that curves from a gentle frown to a big smile as `curvature`
/// moves from -1 to 1 — `animatableData` lets it interpolate smoothly as
/// the mood sliders move instead of snapping between fixed expressions.
private struct MoodMouth: Shape {
    var curvature: CGFloat

    var animatableData: CGFloat {
        get { curvature }
        set { curvature = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let start = CGPoint(x: 0, y: rect.height * 0.5)
        let end = CGPoint(x: rect.width, y: rect.height * 0.5)
        let control = CGPoint(x: rect.width * 0.5, y: rect.height * 0.5 + curvature * rect.height * 1.4)
        p.move(to: start)
        p.addQuadCurve(to: end, control: control)
        return p
    }
}

#Preview {
    NavigationStack { MoodSurveyView() }.environment(AppModel())
}
