import SwiftUI
import UIKit

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

/// True if white content would read poorly on this fill — used to keep
/// `SimpleFace` legible across every swatch color, including light ones
/// like gold.
func isLightColor(_ color: Color) -> Bool {
    let resolved = color.resolve(in: EnvironmentValues())
    let luminance = 0.299 * Double(resolved.red) + 0.587 * Double(resolved.green) + 0.114 * Double(resolved.blue)
    return luminance > 0.68
}

// MARK: - InitialBadge — replaces an avatar with a colored circle + face

struct InitialBadge: View {
    let name: String
    var size: CGFloat = 40
    var overrideColor: Color? = nil
    /// A real uploaded photo, when present, replaces the plush-avatar face
    /// entirely — the face is the fallback for everyone who hasn't set one.
    var photoData: Data? = nil
    var breathes: Bool = true

    @State private var breathe = false

    private var fill: Color { overrideColor ?? swatchColor(for: name) }
    private var photoImage: UIImage? { photoData.flatMap(UIImage.init(data:)) }

    var body: some View {
        ZStack {
            if let photoImage {
                Image(uiImage: photoImage).resizable().scaledToFill()
            } else {
                Circle().fill(fill)
                Image("texture-plush")
                    .resizable()
                    .scaledToFill()
                    .blendMode(.multiply)
                    .opacity(0.55)
                SimpleFace(size: size, dark: isLightColor(fill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.Ink.primary.opacity(0.1), lineWidth: 1))
        .scaleEffect(breathe ? 1.045 : 1.0)
        .onAppear {
            guard breathes else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

/// A minimal, calm face — just eyes and a mouth, no other detail — over a
/// fuzzy plush texture (source: ambientcg.com, CC0), so every avatar reads
/// like a soft felt character rather than a flat color chip. `dark` flips
/// the face to near-black on the handful of light swatch colors (gold)
/// where a white face would wash out.
private struct SimpleFace: View {
    var size: CGFloat
    var dark: Bool = false

    /// Blinks on its own randomized clock rather than a fixed
    /// `repeatForever` interval, so a screen full of avatars doesn't blink
    /// in creepy unison — each `SimpleFace` schedules its own next blink
    /// independently.
    @State private var eyesClosed = false

    var body: some View {
        ZStack {
            HStack(spacing: size * 0.22) {
                eye
                eye
            }
            .offset(y: -size * 0.16)

            CheckmarkMouth()
                .stroke(dark ? Theme.Ink.primary : Color.white, style: StrokeStyle(lineWidth: max(1, size * 0.045), lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.26, height: size * 0.12)
                .offset(y: size * 0.15)
        }
        .foregroundStyle(dark ? Theme.Ink.primary : Color.white)
        .onAppear(perform: scheduleNextBlink)
    }

    private var eye: some View {
        Capsule().frame(width: size * 0.06, height: eyesClosed ? size * 0.02 : size * 0.13)
    }

    private func scheduleNextBlink() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 2.2...5.5)) {
            withAnimation(.easeInOut(duration: 0.08)) { eyesClosed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
                withAnimation(.easeInOut(duration: 0.13)) { eyesClosed = false }
                scheduleNextBlink()
            }
        }
    }
}

/// A checkmark-shaped mouth — a short dip then a longer upward stroke,
/// matching the plush-toy reference's content, slightly cheeky expression.
private struct CheckmarkMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.height * 0.25))
        p.addLine(to: CGPoint(x: rect.width * 0.4, y: rect.height))
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        return p
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
                // Real Liquid Glass with a color tint reads noticeably
                // lighter/more translucent than a flat fill — fine for a
                // secondary action, risky for the app's main CTA, which
                // needs to stay the most legible thing on screen. This
                // keeps a fully opaque purple base for contrast, and gets
                // its "candy" gloss from a glass highlight layered on top
                // instead of replacing the fill itself.
                configuration.label
                    .font(Theme.Font.button())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background(Theme.Brand.purple)
                    .overlay(
                        LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)], startPoint: .top, endPoint: .center)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: Theme.Brand.purple.opacity(0.35),
                            radius: configuration.isPressed ? 4 : 12, y: configuration.isPressed ? 2 : 6)
            case .outline:
                configuration.label
                    .font(Theme.Font.button())
                    .foregroundStyle(Theme.Ink.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            case .tinted(let c):
                configuration.label
                    .font(Theme.Font.button())
                    .foregroundStyle(c)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .glassEffect(.regular.tint(c.opacity(0.5)).interactive(), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
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

    /// Applies `transform` only when `value` is non-nil — for optional
    /// modifiers (like a `Namespace.ID` only some call sites of a shared
    /// view actually have) that can't be expressed as a plain `if` inside
    /// a view builder chain without breaking out of it.
    @ViewBuilder
    func ifLet<Value, Content: View>(_ value: Value?, transform: (Self, Value) -> Content) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - Card surface — flat white fill + a soft shadow, no blur. Legible
// first: thin frosted borders read poorly for older eyes, so blur-glass is
// reserved for the few moments something floats over a real photo (see
// `PhotoOverlaySurface` below). Every list row, input, and pill in the app
// shares this one recipe so it reads as one consistent material.

struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.md
    var tint: Color? = nil
    var shadow: Bool = false

    func body(content: Content) -> some View {
        content
            .background(tint?.opacity(0.08) ?? Theme.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tint?.opacity(0.25) ?? Theme.Surface.border, lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(shadow ? 0.08 : 0), radius: shadow ? 16 : 0, y: shadow ? 6 : 0)
    }
}
extension View {
    func glassSurface(cornerRadius: CGFloat = Theme.Radius.md, tint: Color? = nil, shadow: Bool = false) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint, shadow: shadow))
    }

    /// Real Liquid Glass, for the *controls* layer only — floating icon
    /// buttons that sit on top of content (the message-bell button, the
    /// settings gear), same as the tab bar. HIG is specific that Liquid
    /// Glass belongs on navigation/controls floating above content, not on
    /// the content layer itself — which is exactly why this is a separate
    /// modifier from `glassSurface()` above rather than a shared one: this
    /// app's cards, rows, and inputs stay flat and legible on purpose, and
    /// only the small set of floating chrome controls actually get glass.
    func chromeGlass(cornerRadius: CGFloat = Theme.Radius.md, tint: Color? = nil, interactive: Bool = true) -> some View {
        let base = Glass.regular
        let tinted = tint.map { base.tint($0) } ?? base
        return glassEffect(interactive ? tinted.interactive() : tinted, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// The one place real frosted glass survives — floating stat bubbles and
/// pills over a photo hero, where blur genuinely helps it read against a
/// busy image rather than hurting legibility.
struct PhotoOverlaySurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.md
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(0.9))
            .background(Color.black.opacity(0.18))
            .environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.35), lineWidth: 1)
            )
    }
}
extension View {
    func photoOverlaySurface(cornerRadius: CGFloat = Theme.Radius.md) -> some View {
        modifier(PhotoOverlaySurface(cornerRadius: cornerRadius))
    }
}

/// A flat white card. `tint` no longer washes the whole card — a thin
/// colored edge stripe carries the same semantic color-coding (mine vs.
/// theirs, which kind of alert) without diluting contrast for body text.
struct PactCard<Content: View>: View {
    var tint: Color = Theme.Brand.purple
    var showsAccent: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            if showsAccent {
                RoundedRectangle(cornerRadius: 3).fill(tint).frame(width: 4).padding(.vertical, Theme.Space.sm)
            }
            content
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Theme.Radius.card, tint: nil, shadow: true)
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
                                    .background(Theme.Surface.card)
                                    .overlay(Capsule().stroke(Theme.Surface.border, lineWidth: 1.2))
                                    .clipShape(Capsule())
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

// MARK: - Body profile inputs — shared by onboarding and Settings so the
// height/weight/sex/age/activity entry UI only exists in one place.

struct BodyProfileEditor: View {
    @Binding var profile: BodyProfile
    @Binding var units: UnitSystem
    /// Onboarding needs every field open for first-time entry. Settings
    /// passes `false`: height and sex don't change day to day, so they're
    /// locked to what onboarding captured, and age advances on its own
    /// (see `AppModel.advanceAgeIfAnniversaryPassed`) rather than being
    /// hand-cranked. Weight is the one thing that actually fluctuates, so
    /// it stays editable either way.
    var allowsIdentityEditing: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Picker("Units", selection: $units) {
                ForEach(UnitSystem.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .tint(Theme.Brand.purple)

            field(label: "Height") {
                if allowsIdentityEditing {
                    if units == .imperial {
                        let hw = profile.heightFeetInches
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(hw.feet) ft \(hw.inches) in").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                            RulerScale(value: Binding(
                                get: { profile.heightCm / 2.54 },
                                set: { profile.heightCm = $0 * 2.54 }
                            ), range: 40...84, step: 1)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(Int(profile.heightCm)) cm").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                            RulerScale(value: $profile.heightCm, range: 100...230, step: 1)
                        }
                    }
                } else if units == .imperial {
                    let hw = profile.heightFeetInches
                    Text("\(hw.feet) ft \(hw.inches) in").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                } else {
                    Text("\(Int(profile.heightCm)) cm").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                }
            }

            field(label: "Weight") {
                if units == .imperial {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(Int(profile.weightLb)) lb").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        RulerScale(value: Binding(
                            get: { profile.weightLb },
                            set: { profile.setWeightLb($0) }
                        ), range: 60...400, step: 1)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(Int(profile.weightKg)) kg").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        RulerScale(value: $profile.weightKg, range: 30...180, step: 1)
                    }
                }
            }

            field(label: "Age") {
                if allowsIdentityEditing {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(profile.age) years old").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        RulerScale(value: Binding(
                            get: { Double(profile.age) },
                            set: { profile.age = Int($0) }
                        ), range: 13...100, step: 1)
                    }
                } else {
                    Text("\(profile.age) years old").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("SEX").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                if allowsIdentityEditing {
                    Text("Used only for the calorie-burn estimate below.").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    HStack(spacing: Theme.Space.sm) {
                        ForEach(Sex.allCases) { s in
                            let on = profile.sex == s
                            Button { profile.sex = s } label: {
                                Text(s.rawValue).font(Theme.Font.caption()).fontWeight(.semibold)
                                    .foregroundStyle(on ? .white : Theme.Ink.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(on ? Theme.Brand.purple : Theme.Surface.card)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).stroke(Theme.Surface.border, lineWidth: on ? 0 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text(profile.sex.rawValue).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                }
            }
        }
    }

    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
            content()
                .padding(Theme.Space.md)
                .glassSurface(cornerRadius: Theme.Radius.md)
        }
    }
}

struct ActivityLevelPicker: View {
    @Binding var level: ActivityLevel

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            ForEach(ActivityLevel.allCases) { l in
                let on = level == l
                Button { level = l } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l.rawValue).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                            Text(l.subtitle).font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                        }
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22)).foregroundStyle(on ? Theme.Brand.purple : Theme.Ink.tertiary)
                    }
                    .padding(Theme.Space.md)
                    .frame(minHeight: 56)
                    .glassSurface(cornerRadius: Theme.Radius.md, tint: on ? Theme.Brand.purple : nil)
                }
                .buttonStyle(.plain)
            }
        }
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

    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = CGFloat((value - 1) / 9)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Surface.border2).frame(height: 6)
                ForEach([0.0, 0.5, 1.0], id: \.self) { t in
                    Circle().fill(Theme.Surface.bg).frame(width: 4, height: 4)
                        .offset(x: width * CGFloat(t) - 2)
                }
                Capsule().fill(tint).frame(width: max(14, width * fraction), height: 6)
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(tint, lineWidth: 3))
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    .scaleEffect(isDragging ? 1.3 : 1.0)
                    .offset(x: max(0, min(width, width * fraction)) - 12)
                    .animation(Theme.Motion.pop, value: isDragging)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { g in
                        let frac = min(max(0, g.location.x / width), 1)
                        value = (Double(frac) * 9 + 1).rounded()
                    }
            )
        }
        .frame(height: 24)
        .sensoryFeedback(.selection, trigger: value)
    }
}

// MARK: - Ruler scale (onboarding/settings body-profile fields: height,
// weight, age) — a horizontally-scrubbable tick-mark ruler with a fixed
// center indicator, the same picker language as Apple's own Health app for
// entering exactly this kind of value, in place of the plain capsule-track
// slider these fields used before. Built on the real scroll-snapping APIs
// (scrollTargetLayout/scrollPosition/scrollTargetBehavior) rather than
// hand-rolled drag math, so the momentum/bounce feel is the system's own.

// A real timer-style wheel — the same UIPickerView-derived control the
// Clock app's timer uses, via SwiftUI's native `.wheel` picker style,
// rather than a hand-built horizontal ruler. Everything about how it
// centers the selection, fades neighboring rows, and scrolls/snaps is the
// system's own — the previous horizontal tick-mark version read as too
// far from that familiar "spin a wheel of numbers" feel.
struct RulerScale: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var tint: Color = Theme.Brand.purple

    private var values: [Int] {
        Array(stride(from: Int(range.lowerBound), through: Int(range.upperBound), by: max(1, Int(step))))
    }

    private var selection: Binding<Int> {
        Binding(
            get: { Int(value.rounded()) },
            set: { newValue in value = Double(newValue) }
        )
    }

    var body: some View {
        Picker("", selection: selection) {
            ForEach(values, id: \.self) { v in
                Text("\(v)").font(Theme.Font.h2()).foregroundStyle(tint).tag(v)
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 130)
        .sensoryFeedback(.selection, trigger: value)
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
                Text(trailing).font(Theme.Font.caption()).foregroundStyle(Theme.Brand.purple)
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
    @State private var burst = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 8 sparkles radiating outward at even angles around the main icon.
    private var sparkles: [(dx: CGFloat, dy: CGFloat, angle: Angle)] {
        (0..<8).map { i in
            let a = Double(i) / 8 * 2 * .pi
            return (cos(a) * 74, sin(a) * 74, .radians(a))
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(visible ? 0.55 : 0)

            if !reduceMotion {
                ForEach(Array(sparkles.enumerated()), id: \.offset) { _, spark in
                    Image(systemName: "sparkle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint)
                        .rotationEffect(spark.angle)
                        .opacity(burst ? 0 : 1)
                        .offset(x: burst ? spark.dx : 0, y: burst ? spark.dy : 0)
                }
            }

            VStack(spacing: Theme.Space.sm) {
                Image(systemName: icon)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(tint)
                    .scaleEffect(visible ? 1 : 0.3)
                    .rotationEffect(.degrees(visible ? 0 : -15))
                    // The real SF Symbol "just arrived" gesture on top of the
                    // scale/rotate-in, not a substitute for it — a genuine
                    // system animation family (Siri, notifications) rather
                    // than only a hand-built transform.
                    .symbolEffect(.bounce, value: visible)
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
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(Theme.Motion.pop) { visible = true }
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.8).delay(0.05)) { burst = true }
            }
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

/// Flat warm paper — no gradient, no ambient glow. A busy backdrop is the
/// first thing to go when the goal is legibility for older eyes; the two
/// hero photo moments (challenge detail, suggested card) carry all the
/// visual richness instead.
struct PactBackground: View {
    var body: some View {
        Theme.Surface.bg.ignoresSafeArea()
    }
}

// MARK: - Pact mark — two interlocking rings, the app's signature glyph
// (an agreement between two people), used wherever the wordmark appears.

struct PactMark: View {
    var size: CGFloat = 32
    /// Off for the splash screen specifically — that's a brief, one-beat
    /// moment before the real screen takes over, not a place a continuous
    /// color flow has time to read as anything but a flash. On everywhere
    /// else (Home, Sign In, onboarding, lock screen) by default.
    var animated: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// An angular sweep through the *same three brand colors* `holo`
    /// already uses, rotated continuously — a plain `.hueRotation()` was
    /// sweeping through the entire spectrum, which meant the logo spent
    /// most of its cycle showing colors nowhere in the app's actual
    /// palette. Rotating an AngularGradient never changes what the colors
    /// *are*, only where they sit, which is the "lava lamp"
    /// blobs-of-the-same-colors-drifting feel instead.
    ///
    /// Driven by `TimelineView` rather than a `@State` angle animated via
    /// `withAnimation` — a `ShapeStyle` value like `AngularGradient` isn't
    /// guaranteed to interpolate smoothly frame-to-frame the way an
    /// `Animatable` view *modifier* (`.hueRotation`, `.rotationEffect`) is,
    /// and in practice it didn't visibly move at all. Computing the angle
    /// straight from elapsed wall-clock time and rebuilding the gradient
    /// every frame sidesteps that entirely — there's no interpolation to
    /// rely on, just a fresh, correct render each tick.
    private func flowingHolo(at date: Date) -> AngularGradient {
        let seconds = date.timeIntervalSinceReferenceDate
        let cycle = 8.0
        let progress = (seconds.truncatingRemainder(dividingBy: cycle)) / cycle
        return AngularGradient(
            colors: [Theme.Brand.purple, Theme.Brand.gold, Theme.Brand.pink, Theme.Brand.purple],
            center: .center, angle: .degrees(progress * 360)
        )
    }

    var body: some View {
        TimelineView(.animation(paused: !animated || reduceMotion)) { context in
            let gradient = flowingHolo(at: context.date)
            ZStack {
                Circle()
                    .stroke(gradient, lineWidth: size * 0.11)
                    .frame(width: size, height: size)
                    .offset(x: -size * 0.22)
                Circle()
                    .stroke(gradient, lineWidth: size * 0.11)
                    .frame(width: size, height: size)
                    .offset(x: size * 0.22)
            }
            .frame(width: size * 1.5, height: size)
        }
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

    /// A Catmull-Rom spline, not the midpoint-quad-curve trick this used to
    /// use. That old technique never actually touched most of the real data
    /// points — it curved *toward* the midpoint between each pair and used
    /// the real point only as a bezier control, so a genuine day-to-day
    /// swing in `progressHistory` (which `Fixtures.history`'s wobble term
    /// guarantees exists) was visibly flattened out. It also had a bugged
    /// first segment (curved away from a stationary control point instead
    /// of a normal line-in) and a bugged last segment (a hard straight line
    /// instead of a curve, since the loop always stops one midpoint short).
    /// A Catmull-Rom spline still renders smooth, but passes through every
    /// real value exactly, at its correct x position — accurate *and*
    /// good-looking, not one traded for the other.
    private func path(for line: Line, size: CGSize) -> Path {
        let values = line.points.isEmpty ? [0, 0] : line.points
        let points: [CGPoint] = values.enumerated().map { i, v in
            let t = values.count > 1 ? Double(i) / Double(values.count - 1) : 0
            return CGPoint(x: size.width * t, y: size.height * (1 - max(0, min(1, v))))
        }
        var path = Path()
        path.move(to: points[0])
        guard points.count > 1 else { return path }
        for i in 0..<points.count - 1 {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]
            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }
}

// MARK: - Journey path — a winding line connecting real progress waypoints,
// each with a floating stat bubble. Only the curve is decorative; the x-axis
// underneath is still time, left to right, and every value is real data.

struct JourneyPathView: View {
    struct Waypoint { let label: String; let value: String; let progress: Double }
    let waypoints: [Waypoint]
    var tint: Color = Theme.Brand.purple
    var height: CGFloat = 230

    /// Draws the line in left-to-right on appear instead of materializing
    /// already-complete, and each stat bubble pops in a beat after the
    /// line reaches it instead of every bubble just being there from frame
    /// one — the same "show the data arriving" treatment as the fitness
    /// ring and suggestion carousel elsewhere in the app.
    @State private var drawn: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 22
            let topMargin: CGFloat = 76
            let n = max(waypoints.count, 1)
            let usableW = max(1, geo.size.width - inset * 2)
            let usableH = max(1, geo.size.height - topMargin - 20)
            let points: [CGPoint] = waypoints.enumerated().map { i, w in
                let t = n > 1 ? CGFloat(i) / CGFloat(n - 1) : 0.5
                let x = inset + t * usableW
                let y = topMargin + (usableH - CGFloat(max(0, min(1, w.progress))) * usableH)
                return CGPoint(x: x, y: y)
            }
            let fullCurve = curve(points)
            let baseline = geo.size.height

            ZStack(alignment: .topLeading) {
                // A soft fill under the line grounds it against the
                // baseline instead of the curve floating on blank space —
                // fades out with distance from the line the way a real
                // area chart's gradient does.
                areaFill(points, baseline: baseline)
                    .fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .opacity(drawn)

                fullCurve
                    .trim(from: 0, to: drawn)
                    .stroke(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: tint.opacity(0.45), radius: 5)

                ForEach(Array(points.enumerated()), id: \.offset) { i, pt in
                    let pointT = n > 1 ? CGFloat(i) / CGFloat(n - 1) : 0
                    let arrived = drawn >= pointT - 0.02
                    Circle().fill(tint).frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Theme.Surface.card, lineWidth: 2.5))
                        .position(pt)
                        .scaleEffect(arrived ? 1 : 0.01)

                    bubble(waypoints[i])
                        .position(x: pt.x.clamped(to: 44...(geo.size.width - 44)), y: max(38, pt.y - 50))
                        .scaleEffect(arrived ? 1 : 0.4)
                        .opacity(arrived ? 1 : 0)
                }
            }
        }
        .frame(height: height)
        .onAppear {
            drawn = 0
            if reduceMotion {
                drawn = 1
            } else {
                // Deferred a tick, same reason as the fitness ring: this
                // view can appear as part of a push/zoom navigation
                // transition, and an ambient transaction from that can
                // silently swallow a `withAnimation` called directly from
                // `onAppear`. A fresh run-loop tick escapes it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 1.4)) { drawn = 1 }
                }
            }
        }
    }

    private func bubble(_ w: Waypoint) -> some View {
        VStack(spacing: 1) {
            Text(w.value).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
            Text(w.label).font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 6)
        .background(Theme.Surface.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
        .fixedSize()
    }

    private func curve(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        for i in 0..<points.count - 1 {
            let p0 = points[i], p1 = points[i + 1]
            let c1 = CGPoint(x: (p0.x + p1.x) / 2, y: p0.y)
            let c2 = CGPoint(x: (p0.x + p1.x) / 2, y: p1.y)
            path.addCurve(to: p1, control1: c1, control2: c2)
        }
        return path
    }

    private func areaFill(_ points: [CGPoint], baseline: CGFloat) -> Path {
        var path = curve(points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: baseline))
        path.addLine(to: CGPoint(x: first.x, y: baseline))
        path.closeSubpath()
        return path
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}

// MARK: - Race track — an oval double progress ring for head-to-head
// competition, echoing a literal running track. Built for exactly two
// racers (you vs. the leader) but tolerant of more.

struct RaceTrackProgress: View {
    struct Racer { let name: String; let progress: Double; let color: Color }
    let racers: [Racer]
    var lineWidth: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(racers.enumerated()), id: \.offset) { i, racer in
                    let inset = CGFloat(i) * (lineWidth + 8)
                    let w = max(10, geo.size.width - inset * 2)
                    let h = max(10, geo.size.height - inset * 2)
                    RoundedRectangle(cornerRadius: min(w, h) / 2, style: .continuous)
                        .stroke(racer.color.opacity(0.14), lineWidth: lineWidth)
                        .frame(width: w, height: h)
                    RoundedRectangle(cornerRadius: min(w, h) / 2, style: .continuous)
                        .trim(from: 0, to: max(0.015, min(1, racer.progress)))
                        .stroke(racer.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .frame(width: w, height: h)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Pill tab bar — one floating capsule; the active tab expands to
// show its label in a dark pill, everything else stays icon-only so the
// bar stays quiet until you look for the thing you want.

struct PillTabBar: View {
    var selection: Tab
    var onSelect: (Tab) -> Void
    /// Ties every tab's highlight background to one shared geometry, so
    /// switching tabs slides the *pill* laterally from the old icon to the
    /// new one instead of fading out in one spot and back in at another —
    /// the page behind the bar still cuts instantly (see `MainTabView`).
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { tab in
                let isOn = tab == selection
                Button {
                    onSelect(tab)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                            // `value` only ever flips when motion is allowed —
                            // holding it at `false` under Reduce Motion means
                            // the bounce simply never has anything to trigger on.
                            .symbolEffect(.bounce, value: reduceMotion ? false : isOn)
                        if isOn {
                            Text(tab.rawValue).font(Theme.Font.h3()).lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    .foregroundStyle(isOn ? Color.white : Theme.Ink.tertiary)
                    .padding(.horizontal, isOn ? 16 : 14)
                    .frame(height: 48)
                    .background {
                        if isOn {
                            // Real Liquid Glass, not a hand-rolled material
                            // stack — `.tint` carries the same cyan the old
                            // fill used, `.interactive()` gives it the same
                            // press-response every system glass control has.
                            Capsule()
                                .glassEffect(.regular.tint(Theme.Brand.cyan.opacity(0.92)).interactive(), in: Capsule())
                                .matchedGeometryEffect(id: "activeTabPill", in: indicator)
                        }
                    }
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .shadow(color: Theme.Brand.purple.opacity(0.22), radius: 14, y: 4)
        .shadow(color: Theme.Brand.pink.opacity(0.16), radius: 12, x: -5, y: 2)
        .shadow(color: Theme.Brand.blue.opacity(0.16), radius: 12, x: 5, y: 2)
    }
}
