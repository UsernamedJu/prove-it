import SwiftUI

// MARK: - Stable per-identity color (no avatar generation, just a deterministic tag)

func stableHash(_ s: String) -> Int {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in s.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return Int(hash % 1_000_000)
}

func swatchColor(for name: String) -> Color {
    Theme.Brand.swatch[stableHash(name) % Theme.Brand.swatch.count]
}

// MARK: - InitialBadge — replaces an avatar with a colored circle + initials

struct InitialBadge: View {
    let name: String
    var size: CGFloat = 40
    var overrideColor: Color? = nil

    @State private var breathe = false

    var body: some View {
        Circle()
            .fill(overrideColor ?? swatchColor(for: name))
            .frame(width: size, height: size)
            .overlay(SimpleFace(size: size))
            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
            .scaleEffect(breathe ? 1.045 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
            }
    }
}

/// A minimal, calm face — just eyes and a mouth, no other detail. The look
/// (and the gentle breathing scale on `InitialBadge`) is deliberately borrowed
/// from meditation/breathing apps rather than a literal illustrated avatar.
private struct SimpleFace: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            HStack(spacing: size * 0.24) {
                Circle().frame(width: size * 0.09, height: size * 0.09)
                Circle().frame(width: size * 0.09, height: size * 0.09)
            }
            .offset(y: -size * 0.07)

            SmileShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: max(1, size * 0.045), lineCap: .round))
                .frame(width: size * 0.34, height: size * 0.15)
                .offset(y: size * 0.13)
        }
        .foregroundStyle(.white)
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.width, y: 0), control: CGPoint(x: rect.width / 2, y: rect.height))
        return p
    }
}

// MARK: - Glass button style — translucent pill, soft glow instead of a flat keycap shadow

struct PactButtonStyle: ButtonStyle {
    enum Kind {
        case primary, outline
        case tinted(Color)
    }
    var kind: Kind = .primary
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        Group {
            switch kind {
            case .primary:
                configuration.label
                    .font(Theme.Font.button())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background(Theme.Brand.holo)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .shadow(color: Theme.Brand.purple.opacity(0.55),
                            radius: configuration.isPressed ? 4 : 10, y: configuration.isPressed ? 1 : 4)
            case .outline:
                configuration.label
                    .font(Theme.Font.button())
                    .foregroundStyle(Theme.Ink.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .glassSurface(cornerRadius: Theme.Radius.md)
            case .tinted(let c):
                configuration.label
                    .font(Theme.Font.button())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .glassSurface(cornerRadius: Theme.Radius.md, tint: c)
                    .background(c.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .shadow(color: c.opacity(0.5), radius: configuration.isPressed ? 4 : 10, y: configuration.isPressed ? 1 : 4)
            }
        }
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Press-scale for non-button tappables (cards, list rows).
struct Pressable: ViewModifier {
    @GestureState private var pressed = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(Theme.Motion.pop, value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, state, _ in state = true }
            )
    }
}
extension View {
    func pressable() -> some View { modifier(Pressable()) }
}

// MARK: - Glassmorphism surface — real blur material + the signature
// top-lit edge highlight, shared by every card/pill/input in the app so the
// glass effect reads as one consistent material rather than a flat tint.

struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.md
    var tint: Color? = nil
    var shadow: Bool = false

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background((tint ?? .white).opacity(tint == nil ? 0.06 : 0.10))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [.white.opacity(0.55), (tint ?? .white).opacity(0.12)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: .black.opacity(shadow ? 0.28 : 0), radius: shadow ? 18 : 0, y: shadow ? 10 : 0)
    }
}
extension View {
    func glassSurface(cornerRadius: CGFloat = Theme.Radius.md, tint: Color? = nil, shadow: Bool = false) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint, shadow: shadow))
    }
}

struct PactCard<Content: View>: View {
    var tint: Color = Theme.Brand.purple
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.Space.md)
            .glassSurface(cornerRadius: Theme.Radius.card, tint: tint, shadow: true)
    }
}

// MARK: - Dot stepper (progress through a multi-step flow)

struct DotStepper: View {
    var total: Int
    var current: Int // 0-indexed

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < current ? Theme.Brand.lime : (i == current ? Theme.Brand.purple : Theme.Surface.border2))
                    .frame(width: i == current ? 24 : 8, height: 8)
            }
        }
        .animation(Theme.Motion.settle, value: current)
    }
}

// MARK: - Flow header (Back + step counter, used across onboarding/create flows)

struct FlowHeader: View {
    var step: Int
    var total: Int
    var onBack: (() -> Void)?

    var body: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(Theme.Font.h3())
                    .foregroundStyle(Theme.Ink.secondary)
                }
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            } else {
                Spacer().frame(width: 44)
            }
            Spacer()
            DotStepper(total: total, current: step)
            Spacer()
            Text("\(step + 1)/\(total)")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Ink.tertiary)
                .frame(minWidth: 44, alignment: .trailing)
        }
    }
}

// MARK: - Pill single-select row (duration/type presets)

struct PillRow<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.xs) {
                ForEach(options, id: \.value) { opt in
                    let isOn = selection == opt.value
                    Button {
                        withAnimation(Theme.Motion.pop) { selection = opt.value }
                    } label: {
                        Group {
                            if isOn {
                                Text(opt.label)
                                    .font(Theme.Font.h3())
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, Theme.Space.md)
                                    .frame(height: 46)
                                    .background(Theme.Brand.purple)
                                    .clipShape(Capsule())
                            } else {
                                Text(opt.label)
                                    .font(Theme.Font.h3())
                                    .foregroundStyle(Theme.Ink.secondary)
                                    .padding(.horizontal, Theme.Space.md)
                                    .frame(height: 46)
                                    .background(Capsule().fill(.ultraThinMaterial))
                                    .background(Capsule().fill(Color.white.opacity(0.06)))
                                    .overlay(
                                        Capsule().stroke(
                                            LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.08)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Dropdown menu picker (compact, replaces a full step/screen for small option sets)

struct PactDropdown<T: Hashable>: View {
    let label: String
    let options: [(value: T, title: String, subtitle: String?)]
    @Binding var selection: T

    private var current: (value: T, title: String, subtitle: String?)? {
        options.first { $0.value == selection }
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { opt in
                Button {
                    withAnimation(Theme.Motion.pop) { selection = opt.value }
                } label: {
                    if let subtitle = opt.subtitle {
                        Text("\(opt.title) — \(subtitle)")
                    } else {
                        Text(opt.title)
                    }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased()).font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                    Text(current?.title ?? "Select")
                        .font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                    if let subtitle = current?.subtitle {
                        Text(subtitle).font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Ink.tertiary)
            }
            .padding(Theme.Space.md)
            .glassSurface(cornerRadius: Theme.Radius.md)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat chip (small metric block)

struct StatChip: View {
    let label: String
    let value: String
    var tint: Color = Theme.Brand.purple

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.Font.number(19)).foregroundStyle(tint)
            Text(label.uppercased()).font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.sm)
        .glassSurface(cornerRadius: Theme.Radius.sm)
    }
}

// MARK: - Tag badge (Blind Reveal, Fair Play, Complete…)

struct TagBadge: View {
    let text: String
    var icon: String? = nil
    var tint: Color = Theme.Brand.purple
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
            }
            Text(text)
        }
        .font(Theme.Font.caption())
        .foregroundStyle(filled ? Color.white : tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.18)))
        .clipShape(Capsule())
    }
}

// MARK: - A consistently-sized icon glyph, replacing an emoji leading mark

struct KindIcon: View {
    var systemName: String
    var size: CGFloat = 28
    var tint: Color = Theme.Ink.primary

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
    }
}

// MARK: - Progress pill (linear progress, supports the blind-reveal blur)

struct ProgressPill: View {
    var progress: Double // 0...1
    var tint: Color = Theme.Brand.purple
    var height: CGFloat = 8
    var blurred: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Surface.border)
                Capsule().fill(tint).frame(width: geo.size.width * max(0, min(1, progress)))
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .blur(radius: blurred ? 6 : 0)
    }
}

// MARK: - Two-tone fill slider (mood check-in)

struct PactSlider: View {
    @Binding var value: Double // 1...10
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = CGFloat((value - 1) / 9)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Surface.border2).frame(height: 6)
                Capsule().fill(tint).frame(width: max(14, width * fraction), height: 6)
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(tint, lineWidth: 3))
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    .offset(x: max(0, min(width, width * fraction)) - 12)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let frac = min(max(0, g.location.x / width), 1)
                        value = (Double(frac) * 9 + 1).rounded()
                    }
            )
        }
        .frame(height: 24)
    }
}

// MARK: - Holographic display number (point balances, pot totals)

struct HoloNumber: View {
    let text: String
    var size: CGFloat = 44

    var body: some View {
        Text(text)
            .font(Theme.Font.display(size))
            .foregroundStyle(Theme.Brand.holo)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title).font(Theme.Font.h2()).foregroundStyle(Theme.Ink.primary)
            Spacer()
            if let trailing {
                Text(trailing).font(Theme.Font.caption()).foregroundStyle(Theme.Brand.cyan)
            }
        }
    }
}

// MARK: - Screen background — the deep gradient plus ambient glow, so it
// reads as a designed surface rather than a flat CSS-gradient template.

/// A brief full-screen celebration — used on challenge creation and reveal.
/// Pops in, holds, fades out, then calls `onFinished` to clear the trigger.
struct CelebrationOverlay: View {
    var icon: String
    var tint: Color
    var title: String
    var subtitle: String?
    var onFinished: () -> Void

    @State private var visible = false

    var body: some View {
        ZStack {
            Color.black.opacity(visible ? 0.55 : 0)
            VStack(spacing: Theme.Space.sm) {
                Image(systemName: icon)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(tint)
                    .scaleEffect(visible ? 1 : 0.3)
                    .rotationEffect(.degrees(visible ? 0 : -15))
                Text(title).font(Theme.Font.h1()).foregroundStyle(.white).multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle).font(Theme.Font.body()).foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                }
            }
            .padding(.horizontal, Theme.Space.lg)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(Theme.Motion.pop) { visible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(Theme.Motion.fade) { visible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onFinished() }
            }
        }
    }
}

/// A collapsible card section — the app's accordion primitive, used wherever
/// a screen has several dense blocks of info (Challenge Details, etc.).
struct AccordionSection<Content: View>: View {
    var title: String
    var icon: String? = nil
    var tint: Color = Theme.Brand.purple
    @State private var isOpen: Bool
    @ViewBuilder var content: () -> Content

    init(title: String, icon: String? = nil, tint: Color = Theme.Brand.purple, initiallyOpen: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self._isOpen = State(initialValue: initiallyOpen)
        self.content = content
    }

    var body: some View {
        PactCard(tint: tint) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(Theme.Motion.pop) { isOpen.toggle() }
                } label: {
                    HStack(spacing: Theme.Space.sm) {
                        if let icon { Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint) }
                        Text(title).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.Ink.tertiary)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)
                if isOpen {
                    content()
                        .padding(.top, Theme.Space.sm)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

struct PactBackground: View {
    var body: some View {
        ZStack {
            Theme.Surface.bg
            AmbientGlow()
        }
        .ignoresSafeArea()
    }
}

private struct AmbientGlow: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle().fill(Theme.Brand.purple.opacity(0.30))
                    .frame(width: geo.size.width * 0.75)
                    .blur(radius: 70)
                    .offset(x: -geo.size.width * 0.28, y: -geo.size.height * 0.06)
                Circle().fill(Theme.Brand.cyan.opacity(0.20))
                    .frame(width: geo.size.width * 0.6)
                    .blur(radius: 70)
                    .offset(x: geo.size.width * 0.32, y: geo.size.height * 0.02)
                Circle().fill(Theme.Brand.pink.opacity(0.16))
                    .frame(width: geo.size.width * 0.65)
                    .blur(radius: 80)
                    .offset(x: -geo.size.width * 0.1, y: geo.size.height * 0.42)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Pact mark — two interlocking rings, the app's signature glyph
// (an agreement between two people), used wherever the wordmark appears.

struct PactMark: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Brand.holo, lineWidth: size * 0.11)
                .frame(width: size, height: size)
                .offset(x: -size * 0.22)
            Circle()
                .stroke(Theme.Brand.holo, lineWidth: size * 0.11)
                .frame(width: size, height: size)
                .offset(x: size * 0.22)
        }
        .frame(width: size * 1.5, height: size)
    }
}

// MARK: - Rivalry chart — diverging progress lines drawn from *real* stored
// daily history (`Standing.progressHistory`), not synthesized noise.

struct RivalryChart: View {
    struct Line { let name: String; let color: Color; let points: [Double] }
    let lines: [Line]
    var height: CGFloat = 130

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<3) { i in
                    Rectangle().fill(Theme.Surface.border).frame(height: 1)
                        .offset(y: geo.size.height * (CGFloat(i) / 2) - geo.size.height / 2)
                }
                ForEach(lines, id: \.name) { line in
                    path(for: line, size: geo.size)
                        .stroke(line.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .shadow(color: line.color.opacity(0.6), radius: 4)
                }
            }
        }
        .frame(height: height)
    }

    private func path(for line: Line, size: CGSize) -> Path {
        let values = line.points.isEmpty ? [0, 0] : line.points
        let points: [CGPoint] = values.enumerated().map { i, v in
            let t = values.count > 1 ? Double(i) / Double(values.count - 1) : 0
            return CGPoint(x: size.width * t, y: size.height * (1 - max(0, min(1, v))))
        }
        var path = Path()
        path.move(to: points[0])
        for i in 0..<points.count - 1 {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points.last!)
        return path
    }
}
