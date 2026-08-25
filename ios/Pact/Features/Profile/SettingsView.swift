import SwiftUI

/// Personalization — name, color, and Fair Play age band. Reached from the
/// gear icon on Me; a plain sheet, not a Route, since nothing else links here.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var colorIndex: Int
    @State private var ageBand: AgeBand

    init(app: AppModel) {
        _name = State(initialValue: app.me.name)
        _colorIndex = State(initialValue: Theme.Brand.swatch.firstIndex(of: app.meColor) ?? 0)
        _ageBand = State(initialValue: app.me.ageBand)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PactBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        HStack(spacing: Theme.Space.md) {
                            InitialBadge(name: name.isEmpty ? "?" : name, size: 60, overrideColor: Theme.Brand.swatch[colorIndex])
                            TextField("Your name", text: $name)
                                .font(Theme.Font.h2())
                                .foregroundStyle(Theme.Ink.primary)
                                .padding(.horizontal, Theme.Space.md)
                                .frame(height: 56)
                                .glassSurface(cornerRadius: Theme.Radius.md)
                        }

                        Text("COLOR").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                        HStack(spacing: Theme.Space.sm) {
                            ForEach(Theme.Brand.swatch.indices, id: \.self) { i in
                                Circle()
                                    .fill(Theme.Brand.swatch[i])
                                    .frame(width: 36, height: 36)
                                    .overlay(Circle().stroke(.white, lineWidth: colorIndex == i ? 3 : 0))
                                    .onTapGesture { withAnimation(Theme.Motion.pop) { colorIndex = i } }
                            }
                        }

                        PactDropdown(
                            label: "Fair Play age band",
                            options: AgeBand.allCases.map { (value: $0, title: $0.rawValue, subtitle: "\($0.fairPlayStepTarget.formatted()) steps/day target") },
                            selection: $ageBand
                        )

                        Spacer(minLength: Theme.Space.xl)
                        Button("Save Changes") { save() }
                            .buttonStyle(PactButtonStyle(kind: .primary))
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(Theme.Space.lg)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Ink.secondary)
                }
                ToolbarItem(placement: .principal) {
                    Text("Settings").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { app.me.name = trimmed }
        app.meColorIndex = colorIndex
        app.me.ageBand = ageBand
        dismiss()
    }
}

#Preview {
    SettingsView(app: AppModel()).environment(AppModel())
}
